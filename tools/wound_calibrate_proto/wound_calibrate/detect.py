"""Deteccion de AprilTags 36h11 con pupil-apriltags."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List

import numpy as np


@dataclass
class TagDetection:
    id: int
    center_px: np.ndarray      # (2,)
    corners_px: np.ndarray     # (4,2), en el orden/winding que entrega el detector
    decision_margin: float

    @property
    def mean_side_px(self) -> float:
        c = self.corners_px
        sides = [np.linalg.norm(c[(i + 1) % 4] - c[i]) for i in range(4)]
        return float(np.mean(sides))


def detect_tags(gray: np.ndarray) -> Dict[int, TagDetection]:
    """Detecta tags 36h11 en una imagen en escala de grises. Devuelve {id: TagDetection}.

    Si un ID aparece mas de una vez, se conserva la deteccion con mayor decision_margin.
    """
    try:
        from pupil_apriltags import Detector
    except ImportError as e:  # pragma: no cover
        raise ImportError(
            "Falta 'pupil-apriltags'. Instala las dependencias: "
            "pip install -r requirements.txt"
        ) from e

    if gray.ndim != 2:
        raise ValueError("detect_tags espera una imagen en escala de grises (2D)")

    detector = Detector(
        families="tag36h11",
        nthreads=2,
        quad_decimate=1.0,
        refine_edges=True,
        decode_sharpening=0.25,
    )
    raw = detector.detect(gray)

    out: Dict[int, TagDetection] = {}
    for d in raw:
        det = TagDetection(
            id=int(d.tag_id),
            center_px=np.asarray(d.center, dtype=np.float64),
            corners_px=np.asarray(d.corners, dtype=np.float64),
            decision_margin=float(d.decision_margin),
        )
        prev = out.get(det.id)
        if prev is None or det.decision_margin > prev.decision_margin:
            out[det.id] = det
    return out
