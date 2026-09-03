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

  test('en NINGÚN lugar de lib se calcula la inicial a mano', () {
    // Atado al PATRÓN, no al nombre de la variable: dashboard:1843 usaba
    // load.name[0] (alias de s.fullName) y el guard por-archivo lo dejó pasar.
    final crudo = RegExp(
        r"isNotEmpty \? [\w.]*[nN]ame\[0\]|[\w.]*[nN]ame[\w.()]*\.substring\(0, ?1\)");
    final ofensores = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is File &&
          f.path.endsWith('.dart') &&
          crudo.hasMatch(f.readAsStringSync())) {
        ofensores.add(f.path);
      }
    }
    expect(ofensores, isEmpty,
        reason:
            'inicial cruda (daría "D" en "Dra."): usa avatarInitial() de core/name_format.dart');
  });
}
