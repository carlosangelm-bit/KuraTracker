import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'vision_geometry.dart';

/// Imagen RGB de 8 bits, plana (3 bytes por píxel, fila-mayor). Es el formato
/// interno del motor: todo el procesamiento numérico ocurre sobre estas listas
/// tipadas; `package:image` solo se usa para decodificar/codificar.
class RgbRaster {
  final int width;
  final int height;
  final Uint8List data; // width*height*3

  RgbRaster(this.width, this.height, [Uint8List? data])
      : data = data ?? Uint8List(width * height * 3);

  factory RgbRaster.fromImage(img.Image image) {
    final w = image.width, h = image.height;
    final out = Uint8List(w * h * 3);
    var k = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        out[k++] = p.r.toInt();
        out[k++] = p.g.toInt();
        out[k++] = p.b.toInt();
      }
    }
    return RgbRaster(w, h, out);
  }

  img.Image toImage() {
    final image = img.Image(width: width, height: height, numChannels: 3);
    var k = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgb(x, y, data[k], data[k + 1], data[k + 2]);
        k += 3;
      }
    }
    return image;
  }

  int r(int x, int y) => data[(y * width + x) * 3];
  int g(int x, int y) => data[(y * width + x) * 3 + 1];
  int b(int x, int y) => data[(y * width + x) * 3 + 2];

  void set(int x, int y, int rr, int gg, int bb) {
    final k = (y * width + x) * 3;
    data[k] = rr;
    data[k + 1] = gg;
    data[k + 2] = bb;
  }

  /// Luminancia (Rec. 601) como raster gris.
  GrayRaster toGray() {
    final out = Uint8List(width * height);
    var k = 0;
    for (var i = 0; i < out.length; i++) {
      out[i] = (0.299 * data[k] + 0.587 * data[k + 1] + 0.114 * data[k + 2]).round().clamp(0, 255);
      k += 3;
    }
    return GrayRaster(width, height, out);
  }

  /// Reducción entera por promedio de bloques f×f (descarta el resto).
  RgbRaster downscale(int f) {
    if (f <= 1) return this;
    final w = width ~/ f, h = height ~/ f;
    final out = RgbRaster(w, h);
    final n = f * f;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var sr = 0, sg = 0, sb = 0;
        for (var dy = 0; dy < f; dy++) {
          var k = ((y * f + dy) * width + x * f) * 3;
          for (var dx = 0; dx < f; dx++) {
            sr += data[k];
            sg += data[k + 1];
            sb += data[k + 2];
            k += 3;
          }
        }
        out.set(x, y, sr ~/ n, sg ~/ n, sb ~/ n);
      }
    }
    return out;
  }

  RgbRaster crop(int x0, int y0, int w, int h) {
    final out = RgbRaster(w, h);
    for (var y = 0; y < h; y++) {
      final src = ((y0 + y) * width + x0) * 3;
      out.data.setRange(y * w * 3, (y + 1) * w * 3, data, src);
    }
    return out;
  }

  /// Muestreo bilineal (coordenadas de píxel con origen en el centro del píxel
  /// (0,0); fuera de rango devuelve null).
  bool sampleBilinear(double x, double y, List<double> outRgb) {
    if (x < 0 || y < 0 || x > width - 1 || y > height - 1) return false;
    final x0 = math.min(x.floor(), width - 2).clamp(0, math.max(0, width - 2));
    final y0 = math.min(y.floor(), height - 2).clamp(0, math.max(0, height - 2));
    final fx = (x - x0).clamp(0.0, 1.0), fy = (y - y0).clamp(0.0, 1.0);
    final x1 = math.min(x0 + 1, width - 1), y1 = math.min(y0 + 1, height - 1);
    final k00 = (y0 * width + x0) * 3, k10 = (y0 * width + x1) * 3;
    final k01 = (y1 * width + x0) * 3, k11 = (y1 * width + x1) * 3;
    for (var c = 0; c < 3; c++) {
      outRgb[c] = data[k00 + c] * (1 - fx) * (1 - fy) +
          data[k10 + c] * fx * (1 - fy) +
          data[k01 + c] * (1 - fx) * fy +
          data[k11 + c] * fx * fy;
    }
    return true;
  }
}

/// Imagen de un canal (8 bits).
class GrayRaster {
  final int width;
  final int height;
  final Uint8List data;

  GrayRaster(this.width, this.height, [Uint8List? data])
      : data = data ?? Uint8List(width * height);

  int at(int x, int y) => data[y * width + x];

  GrayRaster downscale(int f) {
    if (f <= 1) return this;
    final w = width ~/ f, h = height ~/ f;
    final out = GrayRaster(w, h);
    final n = f * f;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var s = 0;
        for (var dy = 0; dy < f; dy++) {
          var k = (y * f + dy) * width + x * f;
          for (var dx = 0; dx < f; dx++) {
            s += data[k++];
          }
        }
        out.data[y * w + x] = s ~/ n;
      }
    }
    return out;
  }

  /// Bilineal con origen en el centro del píxel (0,0); recorta al borde.
  double bilinear(double x, double y) {
    final cx = x.clamp(0.0, width - 1.001);
    final cy = y.clamp(0.0, height - 1.001);
    final x0 = cx.floor(), y0 = cy.floor();
    final fx = cx - x0, fy = cy - y0;
    final x1 = math.min(x0 + 1, width - 1), y1 = math.min(y0 + 1, height - 1);
    return data[y0 * width + x0] * (1 - fx) * (1 - fy) +
        data[y0 * width + x1] * fx * (1 - fy) +
        data[y1 * width + x0] * (1 - fx) * fy +
        data[y1 * width + x1] * fx * fy;
  }
}

/// Máscara binaria (0/1 por píxel) con operaciones morfológicas básicas y
/// etiquetado de componentes conexas. Todo en listas tipadas, sin recursión.
class BitMask {
  final int width;
  final int height;
  final Uint8List data;

  BitMask(this.width, this.height, [Uint8List? data]) : data = data ?? Uint8List(width * height);

  BitMask.filled(this.width, this.height, bool v)
      : data = Uint8List(width * height)..fillRange(0, width * height, v ? 1 : 0);

  bool get(int x, int y) => data[y * width + x] != 0;
  void set(int x, int y, bool v) => data[y * width + x] = v ? 1 : 0;
  bool inBounds(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  int get count {
    var c = 0;
    for (final v in data) {
      c += v;
    }
    return c;
  }

  BitMask clone() => BitMask(width, height, Uint8List.fromList(data));

  BitMask and(BitMask o) {
    final out = BitMask(width, height);
    for (var i = 0; i < data.length; i++) {
      out.data[i] = (data[i] & o.data[i]);
    }
    return out;
  }

  BitMask andNot(BitMask o) {
    final out = BitMask(width, height);
    for (var i = 0; i < data.length; i++) {
      out.data[i] = (data[i] != 0 && o.data[i] == 0) ? 1 : 0;
    }
    return out;
  }

  BitMask or(BitMask o) {
    final out = BitMask(width, height);
    for (var i = 0; i < data.length; i++) {
      out.data[i] = (data[i] | o.data[i]);
    }
    return out;
  }

  BitMask not() {
    final out = BitMask(width, height);
    for (var i = 0; i < data.length; i++) {
      out.data[i] = data[i] == 0 ? 1 : 0;
    }
    return out;
  }

  /// Caja envolvente [x0,y0,x1,y1) de los píxeles activos o null si está vacía.
  RectD? boundingBox() {
    var x0 = width, y0 = height, x1 = -1, y1 = -1;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (data[row + x] != 0) {
          if (x < x0) x0 = x;
          if (x > x1) x1 = x;
          if (y < y0) y0 = y;
          if (y > y1) y1 = y;
        }
      }
    }
    if (x1 < 0) return null;
    return RectD(x0.toDouble(), y0.toDouble(), (x1 + 1).toDouble(), (y1 + 1).toDouble());
  }

  void fillRect(int x0, int y0, int x1, int y1, bool v) {
    final ax = x0.clamp(0, width), bx = x1.clamp(0, width);
    final ay = y0.clamp(0, height), by = y1.clamp(0, height);
    for (var y = ay; y < by; y++) {
      data.fillRange(y * width + ax, y * width + bx, v ? 1 : 0);
    }
  }

  /// Dilatación con disco de radio r (fuerza bruta; r pequeño).
  BitMask dilate(int r) => _morph(r, true);

  /// Erosión con disco de radio r.
  BitMask erode(int r) => _morph(r, false);

  BitMask close(int r) => r <= 0 ? clone() : dilate(r).erode(r);
  BitMask open(int r) => r <= 0 ? clone() : erode(r).dilate(r);

  BitMask _morph(int r, bool dil) {
    if (r <= 0) return clone();
    final offs = <int>[];
    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        if (dx * dx + dy * dy <= r * r) {
          offs.add(dx);
          offs.add(dy);
        }
      }
    }
    final out = BitMask(width, height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var hit = !dil; // dilatación: false hasta encontrar un 1; erosión: true hasta encontrar un 0
        for (var k = 0; k < offs.length; k += 2) {
          final xx = x + offs[k], yy = y + offs[k + 1];
          final v = inBounds(xx, yy) ? data[yy * width + xx] != 0 : false;
          if (dil && v) {
            hit = true;
            break;
          }
          if (!dil && !v) {
            hit = false;
            break;
          }
        }
        out.data[y * width + x] = hit ? 1 : 0;
      }
    }
    return out;
  }

  /// Etiquetado de componentes conexas (4-vecindad). Devuelve etiquetas 1..n
  /// (0 = fondo) y el número de componentes.
  (Int32List, int) label() {
    final labels = Int32List(width * height);
    final stack = Int32List(width * height);
    var n = 0;
    for (var start = 0; start < data.length; start++) {
      if (data[start] == 0 || labels[start] != 0) continue;
      n++;
      var sp = 0;
      stack[sp++] = start;
      labels[start] = n;
      while (sp > 0) {
        final i = stack[--sp];
        final x = i % width, y = i ~/ width;
        if (x > 0) {
          final j = i - 1;
          if (data[j] != 0 && labels[j] == 0) {
            labels[j] = n;
            stack[sp++] = j;
          }
        }
        if (x < width - 1) {
          final j = i + 1;
          if (data[j] != 0 && labels[j] == 0) {
            labels[j] = n;
            stack[sp++] = j;
          }
        }
        if (y > 0) {
          final j = i - width;
          if (data[j] != 0 && labels[j] == 0) {
            labels[j] = n;
            stack[sp++] = j;
          }
        }
        if (y < height - 1) {
          final j = i + width;
          if (data[j] != 0 && labels[j] == 0) {
            labels[j] = n;
            stack[sp++] = j;
          }
        }
      }
    }
    return (labels, n);
  }

  /// Conserva solo las componentes que contienen alguna de las semillas.
  BitMask keepComponentsContaining(List<Pt> seeds) {
    final (labels, _) = label();
    final keep = <int>{};
    for (final s in seeds) {
      final x = s.x.floor(), y = s.y.floor();
      if (inBounds(x, y)) {
        final l = labels[y * width + x];
        if (l != 0) keep.add(l);
      }
    }
    final out = BitMask(width, height);
    if (keep.isEmpty) return out;
    for (var i = 0; i < data.length; i++) {
      if (labels[i] != 0 && keep.contains(labels[i])) out.data[i] = 1;
    }
    return out;
  }

  /// Conserva solo la componente conexa (4-vecindad) con más píxeles.
  BitMask largestComponent() {
    final (labels, n) = label();
    if (n <= 1) return clone();
    final counts = Int32List(n + 1);
    for (final l in labels) {
      if (l != 0) counts[l]++;
    }
    var best = 1;
    for (var l = 2; l <= n; l++) {
      if (counts[l] > counts[best]) best = l;
    }
    final out = BitMask(width, height);
    for (var i = 0; i < data.length; i++) {
      if (labels[i] == best) out.data[i] = 1;
    }
    return out;
  }

  /// Rellena huecos: fondo no conectado al borde de la imagen pasa a 1.
  BitMask fillHoles() {
    final bg = not();
    final (labels, n) = bg.label();
    final touches = List<bool>.filled(n + 1, false);
    for (var x = 0; x < width; x++) {
      final a = labels[x], b = labels[(height - 1) * width + x];
      if (a != 0) touches[a] = true;
      if (b != 0) touches[b] = true;
    }
    for (var y = 0; y < height; y++) {
      final a = labels[y * width], b = labels[y * width + width - 1];
      if (a != 0) touches[a] = true;
      if (b != 0) touches[b] = true;
    }
    final out = clone();
    for (var i = 0; i < data.length; i++) {
      final l = labels[i];
      if (l != 0 && !touches[l]) out.data[i] = 1;
    }
    return out;
  }

  /// Píxeles activos con algún 4-vecino inactivo (o en el borde de la imagen).
  List<Pt> boundaryPixels() {
    final out = <Pt>[];
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (data[y * width + x] == 0) continue;
        final edge = x == 0 ||
            y == 0 ||
            x == width - 1 ||
            y == height - 1 ||
            data[y * width + x - 1] == 0 ||
            data[y * width + x + 1] == 0 ||
            data[(y - 1) * width + x] == 0 ||
            data[(y + 1) * width + x] == 0;
        if (edge) out.add(Pt(x.toDouble(), y.toDouble()));
      }
    }
    return out;
  }

  /// Contorno exterior (trazado de Moore, 8-vecindad) de la componente que
  /// contiene el píxel activo más arriba-izquierda. Coordenadas en centros de
  /// píxel (+0.5). Devuelve lista vacía si la máscara está vacía.
  List<Pt> traceOuterContour() {
    var start = -1;
    for (var i = 0; i < data.length; i++) {
      if (data[i] != 0) {
        start = i;
        break;
      }
    }
    if (start < 0) return const [];
    // Vecinos en sentido HORARIO (coordenadas de imagen, y hacia abajo).
    const dx = [1, 1, 0, -1, -1, -1, 0, 1]; // E, SE, S, SW, W, NW, N, NE
    const dy = [0, 1, 1, 1, 0, -1, -1, -1];
    int dirIndex(int ddx, int ddy) {
      for (var i = 0; i < 8; i++) {
        if (dx[i] == ddx && dy[i] == ddy) return i;
      }
      return 4;
    }

    final sx = start % width, sy = start ~/ width;
    final contour = <Pt>[Pt(sx + 0.5, sy + 0.5)];
    var cx = sx, cy = sy;
    // El píxel de retroceso (backtrack) inicial es el vecino OESTE del inicio,
    // que es fondo por construcción (primer píxel en orden de barrido).
    var back = 4;
    const initialBack = 4;
    final maxSteps = data.length * 2;
    var steps = 0;
    while (steps++ < maxSteps) {
      var found = false;
      var nextBack = back;
      for (var t = 1; t <= 8; t++) {
        final d = (back + t) % 8;
        final nx = cx + dx[d], ny = cy + dy[d];
        if (inBounds(nx, ny) && data[ny * width + nx] != 0) {
          // El píxel examinado justo antes (d-1) es fondo y pasa a ser el retroceso.
          final pd = (back + t - 1) % 8;
          final px = cx + dx[pd], py = cy + dy[pd];
          cx = nx;
          cy = ny;
          nextBack = dirIndex(px - cx, py - cy);
          found = true;
          break;
        }
      }
      if (!found) break; // píxel aislado
      back = nextBack;
      // Criterio de paro de Jacob: volver al inicio con el mismo retroceso.
      if (cx == sx && cy == sy && back == initialBack) break;
      if (cx == sx && cy == sy && contour.length > 2 && steps > 2) {
        // Regreso al inicio por otra vía: cerrar igualmente (contornos finos).
        break;
      }
      contour.add(Pt(cx + 0.5, cy + 0.5));
    }
    return contour;
  }
}
