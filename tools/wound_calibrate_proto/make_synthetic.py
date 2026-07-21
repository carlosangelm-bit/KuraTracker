#!/usr/bin/env python3
"""Generador de fotos SINTETICAS de la tarjeta WoundCalibrate para validar el
motor contra 'verdad de terreno' (ground truth) sin hardware fisico.

Renderiza la tarjeta (4 AprilTags 36h11 reales + circulo de 12.7 mm + una herida
sintetica de dimensiones conocidas) en el espacio metrico, y luego aplica una
homografia de perspectiva (tilt/rotacion) para simular una foto tomada en angulo.

Como conocemos las dimensiones reales de la herida en mm, podemos medir el error
de area/longitud que introduce toda la cadena (deteccion -> homografia -> escala
-> medicion). Es una prueba de CORRECCION del algoritmo, no un sustituto de la
validacion con tarjeta impresa + objeto real (eso sigue pendiente).

La herida se dibuja en VERDE puro (0,255,0) para poder segmentarla luego en la
imagen rectificada (ver validate.py).

Uso:
  python make_synthetic.py --spec card_spec.json --out samples/synthetic --n 3
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np

from wound_calibrate import load_spec
from wound_calibrate.spec import CardSpec

# Herida sintetica: elipse de semiejes conocidos (mm), centrada en la tarjeta.
WOUND = {
    "center_mm": (28.0, 42.0),
    "semi_axis_a_mm": 11.0,   # eje X
    "semi_axis_b_mm": 7.0,    # eje Y
    "color_bgr": (0, 255, 0),
}
WOUND_GREEN = np.pi * WOUND["semi_axis_a_mm"] * WOUND["semi_axis_b_mm"]  # mm^2


def _tag_bitmap(tag_id: int) -> np.ndarray:
    """Devuelve el bitmap del tag 36h11 (cuadrado negro exterior = borde del tag)."""
    try:
        from moms_apriltag import TagGenerator2

        tg = TagGenerator2("tag36h11")
        img = tg.generate(tag_id)
    except Exception:  # pragma: no cover - API alterna
        from moms_apriltag import TagGenerator

        tg = TagGenerator("tag36h11")
        img = tg.generate(tag_id)
    return np.asarray(img, dtype=np.uint8)


def render_card(spec: CardSpec, render_px_per_mm: float = 20.0) -> np.ndarray:
    """Renderiza la tarjeta cenital (vista perfecta) en escala render_px_per_mm."""
    w_mm, h_mm = spec.card_size_mm
    margin = 6.0
    W = int(round((w_mm + 2 * margin) * render_px_per_mm))
    H = int(round((h_mm + 2 * margin) * render_px_per_mm))
    # fondo gris-papel (235), no blanco puro, para no disparar falsamente la
    # compuerta de sobreexposicion (que busca clipping ~255).
    canvas = np.full((H, W, 3), 235, dtype=np.uint8)

    def mm2px(x, y):
        return (int(round((x + margin) * render_px_per_mm)),
                int(round((y + margin) * render_px_per_mm)))

    # tags
    for t in spec.tags:
        bmp = _tag_bitmap(t.id)
        side_px = int(round(t.size_mm * render_px_per_mm))
        tag_img = cv2.resize(bmp, (side_px, side_px), interpolation=cv2.INTER_NEAREST)
        tag_bgr = cv2.cvtColor(tag_img, cv2.COLOR_GRAY2BGR)
        cx, cy = mm2px(*t.center_mm)
        x0, y0 = cx - side_px // 2, cy - side_px // 2
        canvas[y0:y0 + side_px, x0:x0 + side_px] = tag_bgr

    # circulo/disco de referencia solido negro (representa el objeto de 12.7 mm)
    cc = mm2px(*spec.circle.center_mm)
    r = int(round((spec.circle.diameter_mm / 2.0) * render_px_per_mm))
    cv2.circle(canvas, cc, r, (0, 0, 0), thickness=-1)

    # herida sintetica (elipse verde rellena)
    wc = mm2px(*WOUND["center_mm"])
    axes = (int(round(WOUND["semi_axis_a_mm"] * render_px_per_mm)),
            int(round(WOUND["semi_axis_b_mm"] * render_px_per_mm)))
    cv2.ellipse(canvas, wc, axes, 0, 0, 360, WOUND["color_bgr"], -1)

    return canvas


def apply_perspective(card: np.ndarray, seed: int) -> np.ndarray:
    """Aplica una homografia de perspectiva pseudo-aleatoria (tilt suave)."""
    rng = np.random.RandomState(seed)
    H, W = card.shape[:2]
    src = np.float32([[0, 0], [W, 0], [W, H], [0, H]])
    # perturbacion de esquinas: hasta ~8% del lado -> perspectiva moderada
    jitter = rng.uniform(-0.08, 0.08, size=(4, 2)) * np.float32([W, H])
    dst = src + jitter.astype(np.float32)
    # normaliza a un lienzo positivo
    dst -= dst.min(axis=0)
    out_w = int(np.ceil(dst[:, 0].max()))
    out_h = int(np.ceil(dst[:, 1].max()))
    M = cv2.getPerspectiveTransform(src, dst)
    warped = cv2.warpPerspective(card, M, (out_w, out_h),
                                 flags=cv2.INTER_LINEAR, borderValue=(255, 255, 255))
    return warped


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Generador de tarjetas WoundCalibrate sinteticas")
    ap.add_argument("--spec", default=str(Path(__file__).parent / "card_spec.json"))
    ap.add_argument("--out", default=str(Path(__file__).parent / "samples" / "synthetic"))
    ap.add_argument("--n", type=int, default=3, help="numero de fotos (distintas perspectivas)")
    ap.add_argument("--render-px-per-mm", type=float, default=20.0)
    args = ap.parse_args(argv)

    spec = load_spec(args.spec)
    outdir = Path(args.out)
    outdir.mkdir(parents=True, exist_ok=True)

    card = render_card(spec, args.render_px_per_mm)

    ground_truth = {
        "wound": {
            "shape": "ellipse",
            "center_mm": list(WOUND["center_mm"]),
            "semi_axis_a_mm": WOUND["semi_axis_a_mm"],
            "semi_axis_b_mm": WOUND["semi_axis_b_mm"],
            "color_bgr": list(WOUND["color_bgr"]),
            "area_cm2": round(WOUND_GREEN / 100.0, 4),
            "largo_cm": round(2 * max(WOUND["semi_axis_a_mm"], WOUND["semi_axis_b_mm"]) / 10.0, 4),
            "ancho_cm": round(2 * min(WOUND["semi_axis_a_mm"], WOUND["semi_axis_b_mm"]) / 10.0, 4),
        },
        "reference_circle_diameter_mm": spec.circle.diameter_mm,
        "render_px_per_mm": args.render_px_per_mm,
        "images": [],
    }

    for i in range(args.n):
        photo = apply_perspective(card, seed=1000 + i)
        name = f"synthetic_{i:02d}.png"
        cv2.imwrite(str(outdir / name), photo)
        ground_truth["images"].append(name)
        print(f"[gen] {name}  ({photo.shape[1]}x{photo.shape[0]})")

    (outdir / "ground_truth.json").write_text(
        json.dumps(ground_truth, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(f"[OK] {args.n} fotos + ground_truth.json en {outdir}/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
