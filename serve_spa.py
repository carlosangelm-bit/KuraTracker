#!/usr/bin/env python3
"""Servidor estatico simple con fallback SPA para Flutter Web.

Sirve archivos existentes normalmente; si la ruta solicitada no existe como
archivo (p.ej. una ruta de cliente como /patients, /patients/123/wound/...),
devuelve index.html para que go_router la resuelva en el navegador.

Configurable via variables de entorno para poder servir distintos builds
(produccion conectada a Supabase vs. demo local sin credenciales) en
puertos distintos con la misma instancia del script:

  SERVE_DIR  - subdirectorio dentro de build/ a servir (default: "web")
  SERVE_PORT - puerto de escucha (default: 3000)
"""
import http.server
import os
import socketserver

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SERVE_DIR = os.environ.get("SERVE_DIR", "web")
DIRECTORY = os.path.join(BASE_DIR, "build", SERVE_DIR)
PORT = int(os.environ.get("SERVE_PORT", "3000"))


class SpaFallbackHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def translate_path(self, path):
        # Comportamiento normal para rutas que corresponden a un archivo real.
        no_query = path.split("?", 1)[0].split("#", 1)[0]
        candidate = super().translate_path(no_query)
        if os.path.isfile(candidate):
            return candidate
        # Fallback SPA: cualquier otra ruta -> index.html
        return os.path.join(DIRECTORY, "index.html")


class ReusableTCPServer(socketserver.TCPServer):
    allow_reuse_address = True


if __name__ == "__main__":
    with ReusableTCPServer(("0.0.0.0", PORT), SpaFallbackHandler) as httpd:
        print(f"Sirviendo {DIRECTORY} en el puerto {PORT} (con fallback SPA)")
        httpd.serve_forever()
