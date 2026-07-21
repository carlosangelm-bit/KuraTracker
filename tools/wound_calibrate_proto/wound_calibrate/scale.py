"""Verificacion independiente de escala: detecta el circulo de 12.7 mm en la
imagen rectificada y compara su diametro medido con el esperado."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import cv2
import numpy as np

from .homography import Rectification
from .spec import CardSpec


@dataclass
class ScaleCheck:
    detected: bool
    measured_diameter_mm: Optional[float]
    expected_diameter_mm: float
    deviation_pct: Optional[float]
    center_rect_px: Optional[tuple]

    def within(self, tol_pct: float) -> bool:
        return self.detected and self.deviation_pct is not None and abs(self.deviation_pct) <= tol_pct


def check_scale_with_circle(
    rectified: np.ndarray, spec: CardSpec, rect: Rectification
) -> ScaleCheck:
    """Mide el diametro del circulo de referencia en la imagen rectificada.

    Recorta una ventana alrededor de la posicion esperada (del spec), aisla la
    marca oscura por umbral y ajusta el circulo minimo que la contiene
    (minEnclosingCircle sobre el contorno externo). Esto mide el borde EXTERNO
    de la marca -> exacto para un disco/marca solida de 12.7 mm. Si la marca real
    fuera un anillo fino, ajustar aqui (usar la linea media del anillo).
    """
    expected_d_mm = spec.circle.diameter_mm
    expected_r_px = (expected_d_mm / 2.0) * rect.px_per_mm
    center_expected = rect.mm_to_rect(np.array(spec.circle.center_mm)).reshape(2)

    gray = rectified if rectified.ndim == 2 else cv2.cvtColor(rectified, cv2.COLOR_BGR2GRAY)

    # ventana de busqueda: 1.8x el radio esperado alrededor del centro esperado
    win = int(round(expected_r_px * 1.8))
    cx, cy = int(round(center_expected[0])), int(round(center_expected[1]))
    x0, y0 = max(0, cx - win), max(0, cy - win)
    x1, y1 = min(gray.shape[1], cx + win), min(gray.shape[0], cy + win)
    if x1 - x0 < 5 or y1 - y0 < 5:
        return ScaleCheck(False, None, expected_d_mm, None, None)
    roi = gray[y0:y1, x0:x1]

    roi_blur = cv2.medianBlur(roi, 3)
    _, mask = cv2.threshold(roi_blur, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))

    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    best = None
    best_score = None
    for c in contours:
        (mx, my), mr = cv2.minEnclosingCircle(c)
        if mr < expected_r_px * 0.5 or mr > expected_r_px * 1.6:
            continue
        # circularidad: area del contorno vs area del circulo que lo contiene
        area = cv2.contourArea(c)
        circularity = area / (np.pi * mr * mr + 1e-9)
        center_off = np.hypot(mx - (center_expected[0] - x0), my - (center_expected[1] - y0))
        score = circularity - 0.01 * center_off  # premia redondo y centrado
        if best_score is None or score > best_score:
            best_score = score
            best = (mx + x0, my + y0, mr)

    if best is None:
        return ScaleCheck(False, None, expected_d_mm, None, None)

    measured_d_mm = 2.0 * best[2] * rect.mm_per_px
    deviation = (measured_d_mm - expected_d_mm) / expected_d_mm * 100.0
    return ScaleCheck(
        detected=True,
        measured_diameter_mm=float(measured_d_mm),
        expected_diameter_mm=expected_d_mm,
        deviation_pct=float(deviation),
        center_rect_px=(float(best[0]), float(best[1])),
    )
