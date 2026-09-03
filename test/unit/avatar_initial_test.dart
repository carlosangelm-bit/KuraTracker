// La inicial del avatar salta los títulos: "Dra. Ana Martínez" es "A", no "D".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/core/name_format.dart';

void main() {
  test('salta el título y toma la inicial del nombre', () {
    expect(avatarInitial('Dra. Ana Martínez'), 'A');
    expect(avatarInitial('Lic. Carlos Ramírez'), 'C');
    expect(avatarInitial('Dr. Roberto'), 'R');
    expect(avatarInitial('Mtra. Sofía'), 'S');
  });

  test('sin título, la primera palabra', () {
    expect(avatarInitial('Administrador Procomsa'), 'A');
    expect(avatarInitial('Enfermería Demo'), 'E'); // "Enfermería" no es "enf"
    expect(avatarInitial('ana'), 'A');
  });

  test('vacío o solo título → "?"', () {
    expect(avatarInitial(''), '?');
    expect(avatarInitial('   '), '?');
    expect(avatarInitial('Dr.'), '?');
  });

  // Un helper probado no basta: hay que probar que está CONECTADO en todos los
  // avatares. Este guard cierra el hueco de "la etiqueta que ves arreglada y dos
  // más escondidas": si un sitio vuelve a la inicial cruda, se pone rojo.
  test('conectado: los avatares usan avatarInitial, no la inicial cruda', () {
    const sitios = [
      'lib/core/router/app_shell.dart', // barra + drawer
      'lib/features/admin/admin_home_screen.dart', // personal
      'lib/features/patients/patient_grid_card.dart',
      'lib/features/patients/patient_list_tile.dart',
      'lib/features/dashboard/dashboard_screen.dart',
    ];
    for (final f in sitios) {
      final src = File(f).readAsStringSync();
      expect(src.contains('avatarInitial('), isTrue,
          reason: '$f no usa avatarInitial');
      expect(RegExp(r'fullName\[0\]').hasMatch(src), isFalse,
          reason: '$f: queda un fullName[0] crudo (daría "D" en "Dra.")');
      expect(src.contains('fullName.trim().substring(0, 1)'), isFalse,
          reason: '$f: queda un substring(0,1) crudo');
    }
  });
}
