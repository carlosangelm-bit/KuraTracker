#!/usr/bin/env python3
"""Harness de validacion: mide el error de area/longitud del motor contra
'verdad de terreno'.

Dos modos:
  - sintetico (default): usa las fotos generadas por make_synthetic.py, donde la
    herida es una elipse verde de dimensiones conocidas. Segmenta el verde en la
    imagen RECTIFICADA, mide, y compara con el ground truth. Prueba TODA la
    cadena (deteccion -> homografia -> escala -> medicion).
  - real: apunta a una carpeta con foto(s) + un manifest de medidas conocidas
    (regla) para reportar el error real. Pendiente hasta tener tarjeta impresa.

Criterios (spec): area < 5%, longitud < 3%. Cross-check de escala: circulo 12.7 mm +-3%.

Uso:
  python validate.py                 # valida el set sintetico en samples/synthetic
  python validate.py --dir samples/synthetic
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Optional

import cv2
import numpy as np

from wound_calibrate import load_spec
from wound_calibrate.measure import measure_contour_mm
from wound_calibrate.pipeline import run_pipeline

AREA_TOL_PCT = 5.0
LENGTH_TOL_PCT = 3.0


def segment_green_contour_mm(rectified: np.ndarray, rect) -> Optional[np.ndarray]:
    """Segmenta la herida verde en la imagen rectificada -> contorno en mm."""
    hsv = cv2.cvtColor(rectified, cv2.COLOR_BGR2HSV)
    mask = cv2.inRange(hsv, (40, 80, 80), (80, 255, 255))
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None
    c = max(contours, key=cv2.contourArea)
    if cv2.contourArea(c) < 50:
        return None
    pts_rect = c.reshape(-1, 2).astype(np.float64)
    return rect.rect_to_mm(pts_rect)


def pct_err(measured: float, truth: float) -> float:
    return abs(measured - truth) / truth * 100.0


def validate_synthetic(spec, directory: Path) -> int:
    gt_path = directory / "ground_truth.json"
    if not gt_path.exists():
        print(f"[ERROR] no existe {gt_path}. Corre primero: python make_synthetic.py")
        return 2
    gt = json.loads(gt_path.read_text(encoding="utf-8"))
    truth = gt["wound"]

    rows = []
    areas, largos = [], []
    for name in gt["images"]:
        img = cv2.imread(str(directory / name), cv2.IMREAD_COLOR)
        if img is None:
            print(f"[skip] no se pudo leer {name}")
            continue
        res = run_pipeline(img, spec, contour_mm=None, enforce_gates=False)
        if res.rectification is None:
            rows.append((name, None, "sin rectificacion (tags no detectados)"))
            continue
        contour_mm = segment_green_contour_mm(res.rectified_image, res.rectification)
        if contour_mm is None:
            rows.append((name, None, "herida no segmentada"))
            continue
        m = measure_contour_mm(contour_mm)
        ea = pct_err(m.area_cm2, truth["area_cm2"])
        el = pct_err(m.largo_cm, truth["largo_cm"])
        scale_dev = None if res.scale is None else res.scale.deviation_pct
        areas.append(ea)
        largos.append(el)
        rows.append((name, (m, ea, el, scale_dev), None))

    print("\n=== Validacion sintetica (ground truth conocido) ===")
    print(f"Herida real: area={truth['area_cm2']} cm2, largo={truth['largo_cm']} cm, "
          f"ancho={truth['ancho_cm']} cm\n")
    print(f"{'foto':<18}{'area cm2':>10}{'err area':>10}{'largo cm':>10}{'err largo':>11}{'circ dev':>10}")
    for name, data, err in rows:
        if data is None:
            print(f"{name:<18}  --  {err}")
            continue
        m, ea, el, sd = data
        sd_s = "n/a" if sd is None else f"{sd:+.2f}%"
        print(f"{name:<18}{m.area_cm2:>10.3f}{ea:>9.2f}%{m.largo_cm:>10.3f}{el:>10.2f}%{sd_s:>10}")

    if not areas:
        print("\n[FALLO] ninguna foto pudo medirse.")
        return 1

    max_area, max_len = max(areas), max(largos)
    # reproducibilidad: dispersion entre fotos
    all_area_vals = [r[1][0].area_cm2 for r in rows if r[1]]
    repro = (max(all_area_vals) - min(all_area_vals)) / np.mean(all_area_vals) * 100.0

    print("\n--- Resumen ---")
    print(f"error de area  : max {max_area:.2f}%  (criterio < {AREA_TOL_PCT}%)  -> "
          f"{'PASA' if max_area < AREA_TOL_PCT else 'FALLA'}")
    print(f"error de largo : max {max_len:.2f}%  (criterio < {LENGTH_TOL_PCT}%)  -> "
          f"{'PASA' if max_len < LENGTH_TOL_PCT else 'FALLA'}")
    print(f"reproducibilidad area entre fotos: {repro:.2f}%  (objetivo ~<5%)")
    print("\nNOTA: esto valida la CORRECCION del algoritmo sobre imagenes sinteticas.")
    print("El numero de exactitud con hardware real requiere card_spec.json real +")
    print("tarjeta impresa + objeto de medida conocida (pendiente).")

    ok = max_area < AREA_TOL_PCT and max_len < LENGTH_TOL_PCT
    return 0 if ok else 1


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Validacion WoundCalibrate")
    ap.add_argument("--spec", default=str(Path(__file__).parent / "card_spec.json"))
    ap.add_argument("--dir", default=str(Path(__file__).parent / "samples" / "synthetic"))
    args = ap.parse_args(argv)
    spec = load_spec(args.spec)
    return validate_synthetic(spec, Path(args.dir))


if __name__ == "__main__":
    raise SystemExit(main())
