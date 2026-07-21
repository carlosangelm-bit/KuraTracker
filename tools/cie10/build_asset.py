#!/usr/bin/env python3
"""Convierte el catálogo reducido CIE-10 (CSV) al asset JSON que empaqueta la app.

Contexto: el expediente NOM-004 exige codificación diagnóstica CIE-10. El
catálogo es reference data nacional, estática e igual para todos los centros,
así que NO vive en Supabase: se empaqueta como asset (igual que
assets/engine/*.json) y se carga a memoria una vez (ver lib/engine/cie10_catalog.dart).

Entrada  : tools/cie10/heridas_cronicas_cie10.csv  (UTF-8, columnas del catálogo)
Salida   : assets/data/cie10_heridas.json

Columnas esperadas del CSV:
    CATALOG_KEY, NOMBRE, RELACION, SUBCATEGORIA, CLAVE_CAPITULO, CAPITULO,
    NO. CARACTERES

RELACION describe el rol del diagnóstico frente a la herida crónica:
    CAUSA | COMORBILIDAD | CONSECUENCIA | HERIDA   -> se normaliza a minúsculas.

NO. CARACTERES: 3 = rubro/encabezado de categoría, 4 = código de hoja
(facturable). Se conserva como `chars`.

Codificación: si el CSV llegó con mojibake reparable (UTF-8 leído como
Latin-1 y re-guardado), se intenta el roundtrip latin-1 -> utf-8. Si tras el
intento quedan marcadores de mojibake (p.ej. una vocal acentuada cuyo segundo
byte se perdió, corrupción NO reparable), el script ABORTA con un error claro
en lugar de emitir un catálogo clínico dañado.

Uso:
    python3 tools/cie10/build_asset.py
    python3 tools/cie10/build_asset.py --csv <ruta> --out <ruta>
"""

from __future__ import annotations

import argparse
import csv
import datetime
import json
import os
import sys

# Rutas por defecto, relativas a la raíz del repo (dos niveles arriba de este
# archivo: tools/cie10/ -> repo/).
_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.abspath(os.path.join(_HERE, "..", ".."))
DEFAULT_CSV = os.path.join(_HERE, "heridas_cronicas_cie10.csv")
DEFAULT_OUT = os.path.join(_REPO, "assets", "data", "cie10_heridas.json")

RELATION_MAP = {
    "CAUSA": "causa",
    "COMORBILIDAD": "comorbilidad",
    "CONSECUENCIA": "consecuencia",
    "HERIDA": "herida",
}

# Bigramas típicos de mojibake (UTF-8 malinterpretado como Latin-1/Windows-1252).
_MOJIBAKE_MARKERS = ("Ã", "Â", "â€", "�")


def _looks_like_mojibake(text: str) -> bool:
    return any(m in text for m in _MOJIBAKE_MARKERS)


def _try_repair(text: str) -> str:
    """Intenta reparar mojibake con el roundtrip latin-1 -> utf-8.

    Devuelve el texto reparado si el roundtrip es válido y reduce los
    marcadores; en cualquier otro caso devuelve el texto original (que luego
    será señalado por la verificación final)."""
    if not _looks_like_mojibake(text):
        return text
    try:
        repaired = text.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return text
    return repaired


def build(csv_path: str, out_path: str) -> int:
    if not os.path.exists(csv_path):
        sys.exit(
            f"[cie10] No se encontró el CSV: {csv_path}\n"
            f"        Coloca el catálogo limpio (UTF-8) en esa ruta y reintenta."
        )

    codes: list[dict] = []
    dirty: list[str] = []
    unknown_rel: list[str] = []
    seen: set[str] = set()

    # Lee todo el contenido primero para dar un error claro si el archivo no es
    # UTF-8 válido (corrupción de bytes NO reparable, distinta del mojibake
    # re-guardado como UTF-8 que sí intentamos reparar campo a campo).
    try:
        with open(csv_path, "r", encoding="utf-8", newline="") as fh:
            content = fh.read()
    except UnicodeDecodeError as e:
        sys.exit(
            f"[cie10] El CSV no es UTF-8 válido (byte {e.object[e.start]:#x} en "
            f"posición {e.start}). Debe exportarse/guardarse en UTF-8 limpio.\n"
            f"        En Excel: 'CSV UTF-8 (delimitado por comas)'."
        )

    reader = csv.DictReader(content.splitlines())
    required = {
        "CATALOG_KEY",
        "NOMBRE",
        "RELACION",
        "SUBCATEGORIA",
        "CLAVE_CAPITULO",
        "CAPITULO",
        "NO. CARACTERES",
    }
    missing = required - set(reader.fieldnames or [])
    if missing:
        sys.exit(f"[cie10] Faltan columnas en el CSV: {sorted(missing)}")

    for row in reader:
        code = (row["CATALOG_KEY"] or "").strip()
        if not code:
            continue
        name = _try_repair((row["NOMBRE"] or "").strip())
        subcategory = _try_repair((row["SUBCATEGORIA"] or "").strip())
        chapter = _try_repair((row["CAPITULO"] or "").strip())
        chapter_key = (row["CLAVE_CAPITULO"] or "").strip()
        rel_raw = (row["RELACION"] or "").strip().upper()

        relation = RELATION_MAP.get(rel_raw)
        if relation is None:
            unknown_rel.append(f"{code}: {rel_raw!r}")

        try:
            chars = int((row["NO. CARACTERES"] or "0").strip())
        except ValueError:
            chars = len(code)

        # Verificación de codificación: cualquier campo que siga con
        # marcadores de mojibake tras el intento de reparación se anota.
        for field in (name, subcategory, chapter):
            if _looks_like_mojibake(field):
                dirty.append(f"{code}: {field!r}")

        if code in seen:
            # El catálogo puede repetir un rubro; nos quedamos con el
            # primero y avisamos.
            print(f"[cie10] Aviso: código duplicado, se ignora: {code}",
                  file=sys.stderr)
            continue
        seen.add(code)

        codes.append({
            "code": code,
            "name": name,
            "relation": relation or rel_raw.lower(),
            "subcategory": subcategory,
            "chapterKey": chapter_key,
            "chapter": chapter,
            "chars": chars,
        })

    if unknown_rel:
        sys.exit(
            "[cie10] RELACION desconocida (esperado CAUSA/COMORBILIDAD/"
            "CONSECUENCIA/HERIDA):\n  " + "\n  ".join(unknown_rel)
        )

    if dirty:
        sys.exit(
            "[cie10] Codificación dañada NO reparable en "
            f"{len(dirty)} campo(s). El CSV debe estar en UTF-8 limpio.\n"
            "  Ejemplos:\n    " + "\n    ".join(dirty[:15])
        )

    payload = {
        "version": datetime.date.today().isoformat(),
        "count": len(codes),
        "codes": codes,
    }

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=1)
        fh.write("\n")

    # Resumen para validación manual.
    by_rel: dict[str, int] = {}
    by_chap: dict[str, int] = {}
    for c in codes:
        by_rel[c["relation"]] = by_rel.get(c["relation"], 0) + 1
        by_chap[c["chapterKey"]] = by_chap.get(c["chapterKey"], 0) + 1

    print(f"[cie10] OK -> {out_path}")
    print(f"[cie10] Total: {len(codes)} códigos")
    print("[cie10] Por relación: " +
          ", ".join(f"{k}={v}" for k, v in sorted(by_rel.items())))
    print("[cie10] Capítulos: " +
          ", ".join(f"{k}={v}" for k, v in sorted(by_chap.items())))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="CIE-10 CSV -> asset JSON")
    ap.add_argument("--csv", default=DEFAULT_CSV, help="ruta del CSV de entrada")
    ap.add_argument("--out", default=DEFAULT_OUT, help="ruta del JSON de salida")
    args = ap.parse_args()
    return build(args.csv, args.out)


if __name__ == "__main__":
    raise SystemExit(main())
