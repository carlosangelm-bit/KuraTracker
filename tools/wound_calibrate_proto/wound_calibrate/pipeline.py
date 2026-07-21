"""Orquestacion del pipeline completo: foto -> medidas + calidad + rectificada."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Optional

import cv2
import numpy as np

from .detect import TagDetection, detect_tags
from .homography import Rectification, build_rectification, warp_to_rectified
from .measure import Measurement, measure_contour_mm
from .overlay import draw_overlay
from .quality import QualityReport, evaluate_quality
from .scale import ScaleCheck, check_scale_with_circle
from .spec import CardSpec


@dataclass
class PipelineResult:
    ok: bool
    reason: str = ""
    quality: Optional[QualityReport] = None
    scale: Optional[ScaleCheck] = None
    measurement: Optional[Measurement] = None
    rectification: Optional[Rectification] = None
    rectified_image: Optional[np.ndarray] = None
    overlay_image: Optional[np.ndarray] = None
    detections: Dict[int, TagDetection] = field(default_factory=dict)

    def as_dict(self) -> dict:
        out: dict = {"ok": self.ok, "reason": self.reason}
        if self.rectification is not None:
            out["mm_por_px"] = round(self.rectification.mm_per_px, 5)
            out["px_por_mm"] = round(self.rectification.px_per_mm, 5)
        out["tags_detectados"] = sorted(self.detections.keys())
        if self.scale is not None:
            out["escala_check"] = {
                "detectado": self.scale.detected,
                "diametro_medido_mm": (
                    None if self.scale.measured_diameter_mm is None
                    else round(self.scale.measured_diameter_mm, 3)
                ),
                "diametro_esperado_mm": self.scale.expected_diameter_mm,
                "desvio_pct": (
                    None if self.scale.deviation_pct is None
                    else round(self.scale.deviation_pct, 3)
                ),
            }
        if self.quality is not None:
            out["calidad"] = self.quality.as_dict()
        if self.measurement is not None:
            m = self.measurement
            out["medidas"] = {
                "area_cm2": round(m.area_cm2, 4),
                "largo_cm": round(m.largo_cm, 4),
                "ancho_cm": round(m.ancho_cm, 4),
                "perimetro_cm": round(m.perimetro_cm, 4),
                "n_puntos_contorno": m.n_puntos,
            }
        return out


def run_pipeline(
    image: np.ndarray,
    spec: CardSpec,
    contour_mm: Optional[np.ndarray] = None,
    px_per_mm: float = 12.0,
    enforce_gates: bool = True,
) -> PipelineResult:
    """Ejecuta el pipeline. `image` es BGR (como la lee cv2.imread).

    Si `contour_mm` es None se hace todo menos la medicion (util para validar
    escala/calidad). Si `enforce_gates` es True y falla una compuerta, la medida
    igual se calcula pero `ok=False` y `reason` explica el motivo.
    """
    gray = image if image.ndim == 2 else cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

    detections = detect_tags(gray)
    if len(detections) < 4 or any(i not in detections for i in spec.expected_ids):
        found = sorted(detections.keys())
        missing = [i for i in spec.expected_ids if i not in detections]
        quality = evaluate_quality(image, gray, spec, detections, None, None)
        return PipelineResult(
            ok=False,
            reason=f"No se detectaron los 4 tags esperados (faltan {missing}, detectados {found}).",
            quality=quality,
            detections=detections,
        )

    rect = build_rectification(spec, detections, px_per_mm=px_per_mm)
    rectified = warp_to_rectified(image, rect)
    scale = check_scale_with_circle(rectified, spec, rect)
    quality = evaluate_quality(image, gray, spec, detections, rect, scale)

    measurement = None
    if contour_mm is not None:
        measurement = measure_contour_mm(contour_mm)

    overlay = draw_overlay(rectified, rect, contour_mm, measurement, scale)

    ok = quality.passed if enforce_gates else True
    reason = "" if ok else "Compuertas de calidad no superadas: " + "; ".join(quality.failures)

    return PipelineResult(
        ok=ok,
        reason=reason,
        quality=quality,
        scale=scale,
        measurement=measurement,
        rectification=rect,
        rectified_image=rectified,
        overlay_image=overlay,
        detections=detections,
    )
