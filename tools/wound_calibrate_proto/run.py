#!/usr/bin/env python3
"""CLI del motor WoundCalibrate (Fase 1a).

Uso:
  python run.py --image foto.jpg --spec card_spec.json --contour contorno.json --out out/

Genera en --out:
  result.json      medidas + mm_por_px + flags de calidad
  rectified.png    imagen rectificada (vista cenital)
  overlay.png      rectificada con contorno + medidas dibujadas
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import cv2

from wound_calibrate import load_spec
from wound_calibrate.measure import load_contour
from wound_calibrate.pipeline import run_pipeline


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="WoundCalibrate proto (Fase 1a)")
    ap.add_argument("--image", required=True, help="foto con la tarjeta visible")
    ap.add_argument("--spec", default=str(Path(__file__).parent / "card_spec.json"))
    ap.add_argument("--contour", default=None, help="JSON con el contorno de la herida (opcional)")
    ap.add_argument("--out", default=str(Path(__file__).parent / "out"))
    ap.add_argument("--px-per-mm", type=float, default=12.0)
    ap.add_argument("--no-gates", action="store_true", help="no bloquear medida si falla una compuerta")
    args = ap.parse_args(argv)

    spec = load_spec(args.spec)
    if spec.is_placeholder:
        print(
            "[AVISO] card_spec.json esta marcado is_placeholder=true: las medidas "
            "NO son confiables hasta cargar la geometria real de la tarjeta.",
            file=sys.stderr,
        )

    image = cv2.imread(args.image, cv2.IMREAD_COLOR)
    if image is None:
        print(f"[ERROR] no se pudo leer la imagen: {args.image}", file=sys.stderr)
        return 2

    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)

    # Necesitamos la rectificacion para convertir un contorno en rect_px -> mm,
    # asi que primero corremos sin contorno, luego (si hay) medimos.
    result = run_pipeline(image, spec, contour_mm=None, px_per_mm=args.px_per_mm,
                          enforce_gates=not args.no_gates)

    if args.contour and result.rectification is not None:
        contour_mm = load_contour(args.contour, result.rectification)
        result = run_pipeline(image, spec, contour_mm=contour_mm,
                              px_per_mm=args.px_per_mm, enforce_gates=not args.no_gates)

    (outdir / "result.json").write_text(
        json.dumps(result.as_dict(), indent=2, ensure_ascii=False), encoding="utf-8"
    )
    if result.rectified_image is not None:
        cv2.imwrite(str(outdir / "rectified.png"), result.rectified_image)
    if result.overlay_image is not None:
        cv2.imwrite(str(outdir / "overlay.png"), result.overlay_image)

    print(json.dumps(result.as_dict(), indent=2, ensure_ascii=False))
    print(f"\n[OK] salida en {outdir}/", file=sys.stderr)
    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
