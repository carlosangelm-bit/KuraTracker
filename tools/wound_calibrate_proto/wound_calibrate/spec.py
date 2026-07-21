"""Carga y validacion de card_spec.json (la 'verdad' fisica de la tarjeta)."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np


@dataclass
class TagSpec:
    id: int
    center_mm: Tuple[float, float]
    size_mm: float
    corner: str = ""


@dataclass
class CircleSpec:
    diameter_mm: float
    center_mm: Tuple[float, float]


@dataclass
class RulerSpec:
    origin_mm: Tuple[float, float]
    direction: Tuple[float, float]
    length_mm: float


@dataclass
class Tolerances:
    planarity_max_side_error_pct: float = 5.0
    circle_diameter_tol_pct: float = 3.0
    overexposed_max_fraction: float = 0.02
    overexposed_threshold_255: int = 250
    distance_min_cm: float = 10.0
    distance_max_cm: float = 30.0


@dataclass
class CardSpec:
    is_placeholder: bool
    card_family: str
    card_size_mm: Tuple[float, float]
    tags: List[TagSpec]
    circle: CircleSpec
    ruler: Optional[RulerSpec]
    focal_length_px: Optional[float]
    tol: Tolerances = field(default_factory=Tolerances)

    @property
    def expected_ids(self) -> List[int]:
        return sorted(t.id for t in self.tags)

    def tag_by_id(self, tag_id: int) -> Optional[TagSpec]:
        for t in self.tags:
            if t.id == tag_id:
                return t
        return None

    def tag_centers_mm(self) -> Dict[int, np.ndarray]:
        return {t.id: np.array(t.center_mm, dtype=np.float64) for t in self.tags}


def load_spec(path: str | Path) -> CardSpec:
    path = Path(path)
    data = json.loads(path.read_text(encoding="utf-8"))

    tags = [
        TagSpec(
            id=int(t["id"]),
            center_mm=tuple(float(v) for v in t["center_mm"]),
            size_mm=float(t["size_mm"]),
            corner=str(t.get("corner", "")),
        )
        for t in data["tags"]
    ]
    if len({t.id for t in tags}) != 4:
        raise ValueError(
            "card_spec: se requieren exactamente 4 tags con IDs DISTINTOS "
            f"(recibidos: {[t.id for t in tags]})"
        )

    circ = data["reference_circle"]
    circle = CircleSpec(
        diameter_mm=float(circ["diameter_mm"]),
        center_mm=tuple(float(v) for v in circ["center_mm"]),
    )

    ruler = None
    if "ruler" in data and data["ruler"]:
        r = data["ruler"]
        ruler = RulerSpec(
            origin_mm=tuple(float(v) for v in r["origin_mm"]),
            direction=tuple(float(v) for v in r["direction"]),
            length_mm=float(r["length_mm"]),
        )

    focal = None
    cam = data.get("camera") or {}
    if cam.get("focal_length_px") is not None:
        focal = float(cam["focal_length_px"])

    tol_data = data.get("quality_tolerances", {})
    tol = Tolerances(
        planarity_max_side_error_pct=float(tol_data.get("planarity_max_side_error_pct", 5.0)),
        circle_diameter_tol_pct=float(tol_data.get("circle_diameter_tol_pct", 3.0)),
        overexposed_max_fraction=float(tol_data.get("overexposed_max_fraction", 0.02)),
        overexposed_threshold_255=int(tol_data.get("overexposed_threshold_255", 250)),
        distance_min_cm=float(tol_data.get("distance_min_cm", 10.0)),
        distance_max_cm=float(tol_data.get("distance_max_cm", 30.0)),
    )

    return CardSpec(
        is_placeholder=bool(data.get("is_placeholder", False)),
        card_family=str(data.get("card_family", "tag36h11")),
        card_size_mm=tuple(float(v) for v in data["card_size_mm"].values() if isinstance(v, (int, float)))
        if isinstance(data["card_size_mm"], dict)
        else tuple(float(v) for v in data["card_size_mm"]),
        tags=tags,
        circle=circle,
        ruler=ruler,
        focal_length_px=focal,
        tol=tol,
    )
