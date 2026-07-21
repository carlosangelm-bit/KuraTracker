"""Homografia imagen -> metrica (mm) y generacion de la imagen rectificada.

La homografia se estima a partir de los 4 CENTROS de tag (correspondencias
mm <-> px). Usar centros es robusto a la orientacion/winding de las esquinas:
no hay que emparejar esquina-con-esquina, solo centro-con-centro.

Como 4 puntos definen la homografia de forma exacta, el error de reproyeccion
sobre esos mismos centros seria ~0 y no serviria como senal de calidad. Por eso
la planaridad se mide de forma INDEPENDIENTE (ver planarity_side_error): se
rectifican las 4 esquinas de cada tag a mm y se comparan sus lados con el
size_mm conocido. Si la tarjeta no esta plana/paralela, esos lados se desvian.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Tuple

import cv2
import numpy as np

from .detect import TagDetection
from .spec import CardSpec


@dataclass
class Rectification:
    H_img2mm: np.ndarray        # 3x3, px imagen -> mm
    px_per_mm: float
    origin_mm: np.ndarray       # (2,) esquina sup-izq del lienzo rectificado, en mm
    size_px: Tuple[int, int]    # (w, h) del lienzo rectificado
    warp_img2rect: np.ndarray   # 3x3, px imagen -> px rectificado

    @property
    def mm_per_px(self) -> float:
        return 1.0 / self.px_per_mm

    def mm_to_rect(self, pts_mm: np.ndarray) -> np.ndarray:
        pts_mm = np.asarray(pts_mm, dtype=np.float64).reshape(-1, 2)
        return (pts_mm - self.origin_mm) * self.px_per_mm

    def rect_to_mm(self, pts_rect: np.ndarray) -> np.ndarray:
        pts_rect = np.asarray(pts_rect, dtype=np.float64).reshape(-1, 2)
        return pts_rect / self.px_per_mm + self.origin_mm


def _apply_h(H: np.ndarray, pts: np.ndarray) -> np.ndarray:
    pts = np.asarray(pts, dtype=np.float64).reshape(-1, 2)
    hom = np.hstack([pts, np.ones((len(pts), 1))])
    out = (H @ hom.T).T
    return out[:, :2] / out[:, 2:3]


def estimate_homography(
    spec: CardSpec, detections: Dict[int, TagDetection]
) -> np.ndarray:
    """H tal que mm = H @ px (imagen), estimada con los 4 centros de tag."""
    centers_mm = spec.tag_centers_mm()
    src_px, dst_mm = [], []
    for tag_id, det in detections.items():
        if tag_id in centers_mm:
            src_px.append(det.center_px)
            dst_mm.append(centers_mm[tag_id])
    if len(src_px) < 4:
        raise ValueError(
            f"Se necesitan 4 centros de tag para la homografia; hay {len(src_px)}"
        )
    src = np.asarray(src_px, dtype=np.float64)
    dst = np.asarray(dst_mm, dtype=np.float64)
    H, _ = cv2.findHomography(src, dst, method=0)  # exacta con 4 puntos
    if H is None:
        raise ValueError("cv2.findHomography no pudo estimar la homografia")
    return H


def build_rectification(
    spec: CardSpec,
    detections: Dict[int, TagDetection],
    px_per_mm: float = 12.0,
    margin_mm: float = 6.0,
) -> Rectification:
    """Construye la rectificacion metrica cubriendo toda la tarjeta + margen."""
    H = estimate_homography(spec, detections)

    w_mm, h_mm = spec.card_size_mm
    origin_mm = np.array([-margin_mm, -margin_mm], dtype=np.float64)
    out_w = int(round((w_mm + 2 * margin_mm) * px_per_mm))
    out_h = int(round((h_mm + 2 * margin_mm) * px_per_mm))

    # S: mm -> px rectificado.  out_px = (mm - origin_mm) * px_per_mm
    S = np.array(
        [
            [px_per_mm, 0.0, -origin_mm[0] * px_per_mm],
            [0.0, px_per_mm, -origin_mm[1] * px_per_mm],
            [0.0, 0.0, 1.0],
        ],
        dtype=np.float64,
    )
    warp = S @ H  # px imagen -> px rectificado

    return Rectification(
        H_img2mm=H,
        px_per_mm=px_per_mm,
        origin_mm=origin_mm,
        size_px=(out_w, out_h),
        warp_img2rect=warp,
    )


def warp_to_rectified(image: np.ndarray, rect: Rectification) -> np.ndarray:
    return cv2.warpPerspective(
        image, rect.warp_img2rect, rect.size_px, flags=cv2.INTER_LINEAR
    )


def planarity_side_error(
    spec: CardSpec, detections: Dict[int, TagDetection], H_img2mm: np.ndarray
) -> Tuple[float, Dict[int, float]]:
    """Rectifica las esquinas de cada tag a mm y compara sus lados con size_mm.

    Devuelve (error_max_pct, {tag_id: error_pct}). Independiente del winding de
    esquinas porque solo usa longitudes entre esquinas consecutivas.
    """
    per_tag: Dict[int, float] = {}
    for tag_id, det in detections.items():
        tag_spec = spec.tag_by_id(tag_id)
        if tag_spec is None:
            continue
        corners_mm = _apply_h(H_img2mm, det.corners_px)
        sides = [
            np.linalg.norm(corners_mm[(i + 1) % 4] - corners_mm[i]) for i in range(4)
        ]
        errs = [abs(s - tag_spec.size_mm) / tag_spec.size_mm * 100.0 for s in sides]
        per_tag[tag_id] = float(max(errs))
    max_err = max(per_tag.values()) if per_tag else float("inf")
    return max_err, per_tag
