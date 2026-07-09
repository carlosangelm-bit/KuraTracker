import 'package:flutter/material.dart';
import '../../../core/theme/kura_theme.dart';

/// Region anatomica seleccionable, con posicion relativa (0..1) sobre el
/// diagrama corporal frontal o posterior.
class BodyRegion {
  final String code;
  final String label;
  final double dx; // 0..1 relativo al ancho del diagrama
  final double dy; // 0..1 relativo al alto del diagrama
  final bool isBack; // true = vista posterior

  const BodyRegion(this.code, this.label, this.dx, this.dy, {this.isBack = false});
}

/// Catalogo de regiones anatomicas comunes en heridas cronicas.
class BodyRegions {
  static const List<BodyRegion> front = [
    BodyRegion('cabeza', 'Cabeza', 0.5, 0.05),
    BodyRegion('torax_anterior', 'Tórax anterior', 0.5, 0.22),
    BodyRegion('abdomen_superior', 'Abdomen superior', 0.5, 0.32),
    BodyRegion('abdomen_inferior', 'Abdomen inferior', 0.5, 0.40),
    BodyRegion('brazo_derecho', 'Brazo derecho', 0.72, 0.28),
    BodyRegion('brazo_izquierdo', 'Brazo izquierdo', 0.28, 0.28),
    BodyRegion('antebrazo_derecho', 'Antebrazo derecho', 0.78, 0.40),
    BodyRegion('antebrazo_izquierdo', 'Antebrazo izquierdo', 0.22, 0.40),
    BodyRegion('mano_derecha', 'Mano derecha', 0.82, 0.50),
    BodyRegion('mano_izquierda', 'Mano izquierda', 0.18, 0.50),
    BodyRegion('cadera_derecha', 'Cadera derecha', 0.60, 0.48),
    BodyRegion('cadera_izquierda', 'Cadera izquierda', 0.40, 0.48),
    BodyRegion('muslo_derecho', 'Muslo derecho', 0.58, 0.62),
    BodyRegion('muslo_izquierdo', 'Muslo izquierdo', 0.42, 0.62),
    BodyRegion('rodilla_derecha', 'Rodilla derecha', 0.58, 0.73),
    BodyRegion('rodilla_izquierda', 'Rodilla izquierda', 0.42, 0.73),
    BodyRegion('pierna_derecha_maleolo', 'Pierna/tobillo derecho', 0.58, 0.85),
    BodyRegion('pierna_izquierda_maleolo', 'Pierna/tobillo izquierdo', 0.42, 0.85),
    BodyRegion('pie_derecho_planta', 'Pie derecho', 0.58, 0.95),
    BodyRegion('pie_izquierdo_planta', 'Pie izquierdo', 0.42, 0.95),
  ];

  static const List<BodyRegion> back = [
    BodyRegion('cabeza_posterior', 'Cabeza (posterior)', 0.5, 0.05, isBack: true),
    BodyRegion('espalda_alta', 'Espalda alta', 0.5, 0.20, isBack: true),
    BodyRegion('espalda_baja', 'Espalda baja / lumbar', 0.5, 0.34, isBack: true),
    BodyRegion('sacro', 'Sacro', 0.5, 0.42, isBack: true),
    BodyRegion('trocanter_derecho', 'Trocánter derecho', 0.60, 0.44, isBack: true),
    BodyRegion('trocanter_izquierdo', 'Trocánter izquierdo', 0.40, 0.44, isBack: true),
    BodyRegion('gluteo_derecho', 'Glúteo derecho', 0.58, 0.48, isBack: true),
    BodyRegion('gluteo_izquierdo', 'Glúteo izquierdo', 0.42, 0.48, isBack: true),
    BodyRegion('muslo_posterior_derecho', 'Muslo posterior derecho', 0.58, 0.62, isBack: true),
    BodyRegion('muslo_posterior_izquierdo', 'Muslo posterior izquierdo', 0.42, 0.62, isBack: true),
    BodyRegion('pantorrilla_derecha', 'Pantorrilla derecha', 0.58, 0.78, isBack: true),
    BodyRegion('pantorrilla_izquierda', 'Pantorrilla izquierda', 0.42, 0.78, isBack: true),
    BodyRegion('talon_derecho', 'Talón derecho', 0.58, 0.95, isBack: true),
    BodyRegion('talon_izquierdo', 'Talón izquierdo', 0.42, 0.95, isBack: true),
  ];

  static const List<BodyRegion> all = [...front, ...back];

  static String labelFor(String? code) {
    if (code == null) return '-';
    final match = all.where((r) => r.code == code);
    return match.isEmpty ? code : match.first.label;
  }
}

/// Selector de ubicacion corporal: toca sobre un diagrama anatomico
/// (frente/espalda) en lugar de un desplegable de texto (seccion 6.1).
class BodyMapSelector extends StatefulWidget {
  final String? selectedCode;
  final ValueChanged<String> onSelected;

  const BodyMapSelector({super.key, this.selectedCode, required this.onSelected});

  @override
  State<BodyMapSelector> createState() => _BodyMapSelectorState();
}

class _BodyMapSelectorState extends State<BodyMapSelector> {
  bool _showBack = false;

  @override
  Widget build(BuildContext context) {
    final regions = _showBack ? BodyRegions.back : BodyRegions.front;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('Vista frontal'),
              selected: !_showBack,
              onSelected: (_) => setState(() => _showBack = false),
              selectedColor: KuraColors.primary.withOpacity(0.15),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Vista posterior'),
              selected: _showBack,
              onSelected: (_) => setState(() => _showBack = true),
              selectedColor: KuraColors.primary.withOpacity(0.15),
            ),
          ],
        ),
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: 0.55,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _BodySilhouettePainter(isBack: _showBack),
                    ),
                  ),
                  ...regions.map((region) {
                    final selected = widget.selectedCode == region.code;
                    return Positioned(
                      left: region.dx * constraints.maxWidth - 14,
                      top: region.dy * constraints.maxHeight - 14,
                      child: Tooltip(
                        message: region.label,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => widget.onSelected(region.code),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected
                                  ? KuraColors.primary
                                  : KuraColors.primary.withOpacity(0.18),
                              border: Border.all(
                                color: KuraColors.primary,
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: selected
                                ? const Icon(Icons.check, color: Colors.white, size: 16)
                                : null,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            widget.selectedCode == null
                ? 'Toca una región del diagrama'
                : 'Seleccionado: ${BodyRegions.labelFor(widget.selectedCode)}',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: widget.selectedCode == null
                  ? KuraColors.darkText.withOpacity(0.5)
                  : KuraColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Silueta corporal simplificada dibujada con CustomPaint (evita
/// dependencias de assets SVG externos con licencias inciertas).
class _BodySilhouettePainter extends CustomPainter {
  final bool isBack;
  const _BodySilhouettePainter({required this.isBack});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = KuraColors.borderSubtle
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = KuraColors.darkText.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final w = size.width;
    final h = size.height;

    // Cabeza
    final headCenter = Offset(w * 0.5, h * 0.045);
    canvas.drawOval(
      Rect.fromCenter(center: headCenter, width: w * 0.14, height: h * 0.08),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: headCenter, width: w * 0.14, height: h * 0.08),
      strokePaint,
    );

    // Torso
    final torsoPath = Path()
      ..moveTo(w * 0.36, h * 0.10)
      ..lineTo(w * 0.64, h * 0.10)
      ..lineTo(w * 0.62, h * 0.46)
      ..lineTo(w * 0.38, h * 0.46)
      ..close();
    canvas.drawPath(torsoPath, paint);
    canvas.drawPath(torsoPath, strokePaint);

    // Brazos
    final leftArm = Path()
      ..moveTo(w * 0.36, h * 0.12)
      ..lineTo(w * 0.20, h * 0.50)
      ..lineTo(w * 0.14, h * 0.52)
      ..lineTo(w * 0.30, h * 0.13)
      ..close();
    final rightArm = Path()
      ..moveTo(w * 0.64, h * 0.12)
      ..lineTo(w * 0.80, h * 0.50)
      ..lineTo(w * 0.86, h * 0.52)
      ..lineTo(w * 0.70, h * 0.13)
      ..close();
    canvas.drawPath(leftArm, paint);
    canvas.drawPath(leftArm, strokePaint);
    canvas.drawPath(rightArm, paint);
    canvas.drawPath(rightArm, strokePaint);

    // Piernas
    final leftLeg = Path()
      ..moveTo(w * 0.38, h * 0.46)
      ..lineTo(w * 0.34, h * 0.98)
      ..lineTo(w * 0.46, h * 0.98)
      ..lineTo(w * 0.49, h * 0.46)
      ..close();
    final rightLeg = Path()
      ..moveTo(w * 0.62, h * 0.46)
      ..lineTo(w * 0.66, h * 0.98)
      ..lineTo(w * 0.54, h * 0.98)
      ..lineTo(w * 0.51, h * 0.46)
      ..close();
    canvas.drawPath(leftLeg, paint);
    canvas.drawPath(leftLeg, strokePaint);
    canvas.drawPath(rightLeg, paint);
    canvas.drawPath(rightLeg, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _BodySilhouettePainter oldDelegate) =>
      oldDelegate.isBack != isBack;
}
