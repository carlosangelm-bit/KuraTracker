"""Dibujo del overlay sobre la imagen rectificada (contorno + anotaciones)."""

from __future__ import annotations

from typing import Optional

import cv2
import numpy as np

from .homography import Rectification
from .measure import Measurement
from .scale import ScaleCheck


def draw_overlay(
    rectified: np.ndarray,
    rect: Rectification,
    contour_mm: Optional[np.ndarray] = None,
    measurement: Optional[Measurement] = None,
    scale: Optional[ScaleCheck] = None,
) -> np.ndarray:
    img = rectified.copy()
    if img.ndim == 2:
        img = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)

    # regla de 10 mm como referencia visual
    p0 = rect.mm_to_rect(np.array([2.0, 2.0])).reshape(2).astype(int)
    p1 = rect.mm_to_rect(np.array([12.0, 2.0])).reshape(2).astype(int)
    cv2.line(img, tuple(p0), tuple(p1), (0, 200, 255), 2)
    cv2.putText(img, "10 mm", (p0[0], p0[1] - 6), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 200, 255), 1, cv2.LINE_AA)

    # circulo detectado
    if scale is not None and scale.detected and scale.center_rect_px is not None:
        c = (int(scale.center_rect_px[0]), int(scale.center_rect_px[1]))
        r = int((scale.measured_diameter_mm / 2.0) * rect.px_per_mm)
        cv2.circle(img, c, r, (255, 128, 0), 2)

    # contorno de la herida
    if contour_mm is not None and len(contour_mm) >= 3:
        pts = rect.mm_to_rect(contour_mm).reshape(-1, 1, 2).astype(np.int32)
        cv2.polylines(img, [pts], isClosed=True, color=(60, 60, 255), thickness=2)
        overlay = img.copy()
        cv2.fillPoly(overlay, [pts], (60, 60, 255))
        img = cv2.addWeighted(overlay, 0.18, img, 0.82, 0)

    # panel de medidas
    if measurement is not None:
        lines = [
            f"area: {measurement.area_cm2:.2f} cm2",
            f"largo: {measurement.largo_cm:.2f} cm",
            f"ancho: {measurement.ancho_cm:.2f} cm",
            f"perim: {measurement.perimetro_cm:.2f} cm",
            f"escala: {rect.mm_per_px:.3f} mm/px",
        ]
        y = 18
        for ln in lines:
            cv2.putText(img, ln, (8, y), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 0, 0), 3, cv2.LINE_AA)
            cv2.putText(img, ln, (8, y), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 255, 255), 1, cv2.LINE_AA)
            y += 20

    return img
