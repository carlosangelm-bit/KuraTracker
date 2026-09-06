#!/usr/bin/env python3
"""Genera los archivos IMPRIMIBLES de la tarjeta WoundCalibrate a partir de
assets/engine/vision/card_spec.json, a tamaño físico exacto.

Como el impreso sale del mismo spec que lee el motor, la geometría es conocida
por construcción; lo único que hay que verificar tras imprimir es que la
impresora no reescaló (la escala impresa debe medir exactamente su longitud).

Salida (en tools/wound_calibrate_proto/print/):
  woundcalibrate_card.pdf         tarjeta sola, página = tamaño de la tarjeta
  woundcalibrate_card_600dpi.png  la misma tarjeta en PNG (600 dpi)
  woundcalibrate_hoja_carta.pdf   hoja carta con 4 tarjetas + 4 discos verdes de
                                  respaldo (Ø según fallback_disc) + regla de control

Uso:  python3 make_print_card.py [--spec ruta] [--params ruta] [--out dir]
Requiere: pillow, numpy, moms_apriltag (tabla de códigos tag36h11).
"""
import argparse
import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont

try:
    from moms_apriltag.tags import tag36h11 as T
    CODES = T.codes
except ImportError:  # pragma: no cover
    CODES = None

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
DPI = 600


def _font(bold, size_px):
    base = '/usr/share/fonts/truetype/dejavu/'
    name = 'DejaVuSans-Bold.ttf' if bold else 'DejaVuSans.ttf'
    try:
        return ImageFont.truetype(base + name, size_px)
    except Exception:
        return ImageFont.load_default()


def tag_bitmap(tag_id):
    if CODES is None:
        raise SystemExit('Falta moms_apriltag: pip install moms_apriltag')
    code = CODES[tag_id]
    bits = [(code >> (35 - k)) & 1 for k in range(36)]
    return np.pad(np.array(bits).reshape(6, 6), 1, constant_values=0)  # 1 = blanco


def render_card(spec, dpi=DPI):
    mm = dpi / 25.4
    px = lambda v: int(round(v * mm))
    W, H = spec['card_size_mm']['width'], spec['card_size_mm']['height']
    img = Image.new('L', (px(W), px(H)), 255)
    d = ImageDraw.Draw(img)
    for t in spec['tags']:
        b = tag_bitmap(t['id'])
        s = t['size_mm']
        cx, cy = t['center_mm']
        cell = s / 8
        for r in range(8):
            for c in range(8):
                x0, y0 = px(cx - s / 2 + c * cell), px(cy - s / 2 + r * cell)
                x1, y1 = px(cx - s / 2 + (c + 1) * cell), px(cy - s / 2 + (r + 1) * cell)
                d.rectangle([x0, y0, x1 - 1, y1 - 1], fill=255 if b[r, c] else 0)
    rc = spec['reference_circle']
    ccx, ccy = rc['center_mm']
    R = rc['diameter_mm'] / 2
    d.ellipse([px(ccx - R), px(ccy - R), px(ccx + R), px(ccy + R)], fill=0)
    # Escala impresa (cross-check de la impresora)
    ru = spec['ruler']
    ox, oy = ru['origin_mm']
    L = ru['length_mm']
    if L > 0:
        esc = min(1.0, min(W, H) / 54.0)          # marcas proporcionales al tamaño
        f_tiny = _font(False, max(6, px(1.1 * esc)))
        d.line([px(ox), px(oy), px(ox + L), px(oy)], fill=0, width=max(2, px(0.3 * esc)))
        paso = 10 if L >= 30 else 5
        for i in range(int(L) + 1):
            h = (1.8 if i % paso == 0 else (1.2 if i % 5 == 0 else 0.7)) * esc
            d.line([px(ox + i), px(oy), px(ox + i), px(oy - h)], fill=0, width=max(1, px(0.18 * esc)))
        for i in range(0, int(L) + 1, paso):
            d.text((px(ox + i) - px(0.7 * esc), px(oy - 3.5 * esc)), str(i), fill=0, font=f_tiny)
    # Textos: solo si la tarjeta es lo bastante grande. En una tarjeta pequeña
    # las instrucciones no caben y estorbarían a los marcadores — van en el
    # instructivo, no impresas.
    libre_mm = min(W, H) - 2 * (max(t['size_mm'] for t in spec['tags']) + 2)
    if W >= 70 and libre_mm > 14:
        x_text = px((W - min(W, H) * 0.0) / 2 - 25)
        d.text((px(17.5), px(5.0)), 'KuraTracker · WoundCalibrate', fill=0, font=_font(True, px(2.4)))
        d.text((px(17.5), px(8.6)), 'Tarjeta de calibración · tag36h11 #%s · círculo %.1f mm'
               % ('-'.join(str(t['id']) for t in spec['tags']), rc['diameter_mm']), fill=0, font=_font(False, px(1.4)))
        f_note = _font(False, px(1.15))
        d.text((px(17.5), px(H - 17.0)), 'Colocar PLANA junto a la herida, en el mismo plano.', fill=0, font=f_note)
        d.text((px(17.5), px(H - 15.0)), 'No recortar los marcadores. Imprimir al 100 %.', fill=0, font=f_note)
        d.text((px(17.5), px(H - 13.0)), 'Verificar: la escala debe medir %d mm exactos.' % int(L), fill=0, font=f_note)
    else:
        # Identificación mínima, en el margen inferior.
        d.text((px(2.0), px(1.6)), 'KuraTracker %.0f×%.0f' % (W, H), fill=0, font=_font(False, px(1.8)))
    d.rectangle([0, 0, img.width - 1, img.height - 1], outline=0, width=max(1, px(0.15)))
    return img


def render_sheet(card, params, dpi=DPI):
    mm = dpi / 25.4
    px = lambda v: int(round(v * mm))
    sheet = Image.new('RGB', (px(215.9), px(279.4)), 'white')  # carta
    sd = ImageDraw.Draw(sheet)
    card_rgb = card.convert('RGB')
    cw, ch = card.width / mm, card.height / mm
    for (x, y) in [(20, 20), (20 + cw + 8, 20), (20, 20 + ch + 8), (20 + cw + 8, 20 + ch + 8)]:
        sheet.paste(card_rgb, (px(x), px(y)))
    y_disc = 20 + 2 * ch + 8 + 30
    disc = params['fallback_disc']
    dd = disc['diameter_mm']
    f = _font(False, px(2.0))
    sd.text((px(20), px(y_disc - 16)),
            'Discos de referencia de respaldo · Ø %.0f mm · recortar por el borde · usar solo con foto cenital' % dd,
            fill=(0, 0, 0), font=f)
    for k in range(4):
        x = 30 + k * (dd + 12)
        sd.ellipse([px(x - dd / 2), px(y_disc - dd / 2), px(x + dd / 2), px(y_disc + dd / 2)], fill=(40, 190, 70))
    y_ctrl = y_disc + 30
    sd.text((px(20), px(y_ctrl - 14)),
            'Imprimir al 100 % (sin "ajustar a la página"). Control: esta regla debe medir 100 mm; '
            'la escala de cada tarjeta, su longitud impresa.', fill=(0, 0, 0), font=f)
    sd.line([px(20), px(y_ctrl), px(120), px(y_ctrl)], fill=(0, 0, 0), width=px(0.3))
    for i in range(0, 101, 10):
        sd.line([px(20 + i), px(y_ctrl), px(20 + i), px(y_ctrl - 3)], fill=(0, 0, 0), width=px(0.2))
        sd.text((px(20 + i) - px(1), px(y_ctrl - 7)), str(i), fill=(0, 0, 0), font=_font(False, px(1.6)))
    return sheet


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--spec', default=os.path.join(REPO, 'assets', 'engine', 'vision', 'card_spec.json'))
    ap.add_argument('--params', default=os.path.join(REPO, 'assets', 'engine', 'vision', 'vision_params.json'))
    ap.add_argument('--out', default=os.path.join(HERE, 'print'))
    a = ap.parse_args()
    spec = json.load(open(a.spec))
    params = json.load(open(a.params))
    os.makedirs(a.out, exist_ok=True)
    card = render_card(spec)
    card.save(os.path.join(a.out, 'woundcalibrate_card_600dpi.png'), dpi=(DPI, DPI))
    card.convert('RGB').save(os.path.join(a.out, 'woundcalibrate_card.pdf'), 'PDF', resolution=DPI)
    render_sheet(card, params).save(os.path.join(a.out, 'woundcalibrate_hoja_carta.pdf'), 'PDF', resolution=DPI)
    print('OK →', a.out)


if __name__ == '__main__':
    main()
