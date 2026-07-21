"""Medicion de la herida en el espacio metrico rectificado.

El contorno se traza (manual en Fase 1) sobre la imagen rectificada. Se acepta
como lista de puntos, en px del rectificado o directamente en mm.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import List

import cv2
import numpy as np

from .homography import Rectification


@dataclass
class Measurement:
    area_cm2: float
    largo_cm: float       # eje mayor del rect. rotado minimo
    ancho_cm: float       # eje menor
    perimetro_cm: float
    n_puntos: int

    def as_dict(self) -> dict:
        return asdict(self)


def _polygon_area_mm2(pts_mm: np.ndarray) -> float:
    x = pts_mm[:, 0]
    y = pts_mm[:, 1]
    return 0.5 * abs(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1)))


def _perimeter_mm(pts_mm: np.ndarray) -> float:
    d = pts_mm - np.roll(pts_mm, -1, axis=0)
    return float(np.sum(np.linalg.norm(d, axis=1)))


def measure_contour_mm(pts_mm: np.ndarray) -> Measurement:
    pts_mm = np.asarray(pts_mm, dtype=np.float64).reshape(-1, 2)
    if len(pts_mm) < 3:
        raise ValueError("El contorno necesita al menos 3 puntos")

    area_mm2 = _polygon_area_mm2(pts_mm)
    perim_mm = _perimeter_mm(pts_mm)

    rect = cv2.minAreaRect(pts_mm.astype(np.float32))
    (w, h) = rect[1]
    largo_mm = max(w, h)
    ancho_mm = min(w, h)

    return Measurement(
        area_cm2=area_mm2 / 100.0,
        largo_cm=largo_mm / 10.0,
        ancho_cm=ancho_mm / 10.0,
        perimetro_cm=perim_mm / 10.0,
        n_puntos=len(pts_mm),
    )


def load_contour(path: str | Path, rect: Rectification) -> np.ndarray:
    """Carga un contorno desde JSON y lo devuelve en mm.

    Formato: {"coords": "rect_px"|"mm", "points": [[x,y], ...]}
    """
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    coords = data.get("coords", "rect_px")
    pts = np.asarray(data["points"], dtype=np.float64).reshape(-1, 2)
    if coords == "mm":
        return pts
    if coords == "rect_px":
        return rect.rect_to_mm(pts)
    raise ValueError(f"coords desconocido: {coords!r} (usa 'rect_px' o 'mm')")
