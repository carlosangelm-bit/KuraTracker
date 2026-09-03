// La inicial del avatar salta los títulos: "Dra. Ana Martínez" es "A", no "D".
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/core/router/app_shell.dart' show avatarInitial;

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
}
