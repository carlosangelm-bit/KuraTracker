"""WoundCalibrate proto (Fase 1a) — motor de medicion calibrada de heridas.

Modulo independiente (NO integrado en la app Flutter). Pipeline:
detectar AprilTags 36h11 -> homografia imagen->metrica -> imagen rectificada
-> verificacion de escala con el circulo de 12.7 mm -> compuertas de calidad
-> medicion de un contorno de herida (manual) en mm.

Ver README.md para como correrlo.
"""

from .spec import CardSpec, load_spec
from .pipeline import run_pipeline, PipelineResult

__all__ = ["CardSpec", "load_spec", "run_pipeline", "PipelineResult"]
