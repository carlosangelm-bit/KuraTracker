"""Compuertas de calidad: rechazan la foto (con motivo) si no es medible."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Optional

import cv2
import numpy as np

from .detect import TagDetection
from .homography import Rectification, planarity_side_error
from .scale import ScaleCheck
from .spec import CardSpec


@dataclass
class Gate:
    name: str
    passed: bool
    detail: str
    value: Optional[float] = None


@dataclass
class QualityReport:
    gates: List[Gate] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return all(g.passed for g in self.gates)

    @property
    def failures(self) -> List[str]:
        return [f"{g.name}: {g.detail}" for g in self.gates if not g.passed]

    def as_dict(self) -> dict:
        return {
            "passed": self.passed,
            "gates": [
                {"name": g.name, "passed": g.passed, "detail": g.detail, "value": g.value}
                for g in self.gates
            ],
            "failures": self.failures,
        }


def _card_mask(image_shape, detections: Dict[int, TagDetection]) -> Optional[np.ndarray]:
    """Mascara del area util de la tarjeta: envolvente de los tags MENOS los
    propios tags (sus celdas blancas son legitimamente 255 y no son reflejos)."""
    pts = np.vstack([d.corners_px for d in detections.values()]).astype(np.int32)
    if len(pts) < 3:
        return None
    hull = cv2.convexHull(pts)
    mask = np.zeros(image_shape[:2], dtype=np.uint8)
    cv2.fillConvexPoly(mask, hull, 255)
    # excluye la region de cada tag (con un pequenio margen)
    for d in detections.values():
        quad = d.corners_px.astype(np.int32)
        c = quad.mean(axis=0)
        quad = (c + (quad - c) * 1.25).astype(np.int32)  # infla ~25%
        cv2.fillConvexPoly(mask, quad, 0)
    return mask


def evaluate_quality(
    image: np.ndarray,
    gray: np.ndarray,
    spec: CardSpec,
    detections: Dict[int, TagDetection],
    rect: Optional[Rectification],
    scale: Optional[ScaleCheck],
) -> QualityReport:
    tol = spec.tol
    rep = QualityReport()

    # 1) 4 tags con los IDs esperados
    found = sorted(detections.keys())
    expected = spec.expected_ids
    missing = [i for i in expected if i not in detections]
    rep.gates.append(
        Gate(
            name="tags_detectados",
            passed=(len(missing) == 0),
            detail=(
                "4/4 tags esperados detectados"
                if not missing
                else f"faltan tags {missing} (detectados: {found}). No se ve la tarjeta completa."
            ),
            value=float(len(detections)),
        )
    )

    # 2) planaridad (error de reproyeccion independiente)
    if rect is not None:
        max_err, per_tag = planarity_side_error(spec, detections, rect.H_img2mm)
        ok = max_err <= tol.planarity_max_side_error_pct
        rep.gates.append(
            Gate(
                name="planaridad",
                passed=ok,
                detail=(
                    f"error max de lado {max_err:.2f}% (limite {tol.planarity_max_side_error_pct}%)"
                    + ("" if ok else ". Aplana la tarjeta / ponla paralela a la superficie.")
                ),
                value=float(max_err),
            )
        )

    # 3) circulo en tolerancia
    if scale is not None:
        ok = scale.within(tol.circle_diameter_tol_pct)
        if not scale.detected:
            detail = "circulo de referencia no detectado en la imagen rectificada."
        else:
            detail = (
                f"diametro medido {scale.measured_diameter_mm:.2f} mm vs "
                f"{scale.expected_diameter_mm:.2f} mm (desvio {scale.deviation_pct:+.2f}%, "
                f"limite +-{tol.circle_diameter_tol_pct}%)"
            )
            if not ok:
                detail += ". Escala fuera de tolerancia."
        rep.gates.append(
            Gate(
                name="escala_circulo",
                passed=ok,
                detail=detail,
                value=(None if scale.deviation_pct is None else float(scale.deviation_pct)),
            )
        )

    # 4) sobreexposicion / reflejos dentro de la tarjeta
    mask = _card_mask(image.shape, detections)
    if mask is not None:
        region = gray[mask > 0]
        if region.size > 0:
            frac = float(np.mean(region >= tol.overexposed_threshold_255))
            ok = frac <= tol.overexposed_max_fraction
            rep.gates.append(
                Gate(
                    name="sobreexposicion",
                    passed=ok,
                    detail=(
                        f"{frac*100:.2f}% de pixeles saturados (limite "
                        f"{tol.overexposed_max_fraction*100:.1f}%)"
                        + ("" if ok else ". Evita el reflejo / baja la exposicion.")
                    ),
                    value=frac,
                )
            )

    # 5) distancia 10-30 cm inferida del tamano de tag en px
    mean_tag_px = float(np.mean([d.mean_side_px for d in detections.values()])) if detections else 0.0
    if spec.focal_length_px and mean_tag_px > 0:
        tag_size_mm = float(np.mean([spec.tag_by_id(i).size_mm for i in detections if spec.tag_by_id(i)]))
        distance_cm = spec.focal_length_px * tag_size_mm / mean_tag_px / 10.0
        ok = tol.distance_min_cm <= distance_cm <= tol.distance_max_cm
        msg = f"distancia estimada {distance_cm:.1f} cm (rango {tol.distance_min_cm:.0f}-{tol.distance_max_cm:.0f} cm)"
        if not ok:
            msg += ". Acercate." if distance_cm > tol.distance_max_cm else ". Alejate un poco."
        rep.gates.append(Gate(name="distancia", passed=ok, detail=msg, value=distance_cm))
    else:
        rep.gates.append(
            Gate(
                name="distancia",
                passed=True,
                detail=(
                    f"tag ~{mean_tag_px:.0f} px (proxy). Compuerta en cm OMITIDA: "
                    "define camera.focal_length_px en card_spec.json para evaluarla."
                ),
                value=mean_tag_px,
            )
        )

    return rep
