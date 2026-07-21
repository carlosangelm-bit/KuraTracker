import 'package:flutter/material.dart';

import '../theme/kura_theme.dart';
import 'signature_model.dart';

export 'signature_model.dart' show SignatureController, SignatureData;

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Size? sourceSize; // si se indica, se re-escala desde ese tamaño
  final Color color;
  _SignaturePainter(this.strokes, {this.sourceSize, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    double sx = 1, sy = 1;
    if (sourceSize != null &&
        sourceSize!.width > 0 &&
        sourceSize!.height > 0) {
      sx = size.width / sourceSize!.width;
      sy = size.height / sourceSize!.height;
    }
    Offset scale(Offset p) => Offset(p.dx * sx, p.dy * sy);

    for (final stroke in strokes) {
      if (stroke.length < 2) {
        if (stroke.length == 1) {
          canvas.drawCircle(scale(stroke.first), 1.2, paint..style = PaintingStyle.fill);
          paint.style = PaintingStyle.stroke;
        }
        continue;
      }
      final path = Path()..moveTo(scale(stroke.first).dx, scale(stroke.first).dy);
      for (final p in stroke.skip(1)) {
        final sp = scale(p);
        path.lineTo(sp.dx, sp.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter old) => true;
}

/// Pad de firma editable. El profesional traza su firma con el dedo/lápiz/ratón.
class SignaturePad extends StatelessWidget {
  final SignatureController controller;
  final double height;
  const SignaturePad({super.key, required this.controller, this.height = 160});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, height);
        controller.setCanvasSize(size);
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: KuraColors.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            onPanStart: (d) => controller.startStroke(d.localPosition),
            onPanUpdate: (d) => controller.appendPoint(d.localPosition),
            onPanEnd: (_) => controller.endStroke(),
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => CustomPaint(
                size: size,
                painter: _SignaturePainter(controller.strokes,
                    color: KuraColors.darkText),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Render de solo lectura de una firma persistida (JSON) — para notas ya
/// firmadas (detalle de consulta / reportes).
class SignatureView extends StatelessWidget {
  final String? signatureJson;
  final double height;
  const SignatureView({super.key, required this.signatureJson, this.height = 120});

  @override
  Widget build(BuildContext context) {
    final data = SignatureData.tryParse(signatureJson);
    if (data == null) {
      return const SizedBox.shrink();
    }
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KuraColors.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        painter: _SignaturePainter(data.strokes,
            sourceSize: data.size, color: KuraColors.darkText),
      ),
    );
  }
}
