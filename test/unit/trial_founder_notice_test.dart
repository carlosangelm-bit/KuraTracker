// Alta del centro de prueba: al crear el fundador se le ENVÍA el correo para que ponga
// su propia contraseña (como Usuarios: resetPasswordForEmail), en vez de mostrar una
// temporal y afirmar —falsamente— que no hay correo configurado. La temporal queda como
// respaldo SOLO si el envío falla, con el motivo real.
//
// Local: trial_founder_notice.dart no arrastra google_fonts.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/features/platform/trial_founder_notice.dart';
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/services/data_repository.dart' show CreatedUser;

const _founder = CreatedUser(
  uid: 'u1',
  email: 'admin@prospecto.test',
  tempPassword: 'TMP-abc123',
  role: AppRole.admin,
);

void main() {
  test('al crear el fundador se INVOCA el envío del correo', () async {
    String? sentTo;
    final notice = await notifyTrialFounder(
      _founder,
      send: (email) async => sentTo = email,
    );
    expect(sentTo, 'admin@prospecto.test',
        reason: 'debe enviar el correo de establecer-contraseña al fundador');
    expect(notice.emailSent, isTrue);
    expect(notice.tempPassword, isNull,
        reason: 'la temporal NO se muestra cuando el correo se envió');
  });

  test('si el envío falla, la temporal queda de respaldo con el motivo REAL', () async {
    final notice = await notifyTrialFounder(
      _founder,
      send: (email) async => throw Exception('SMTP rate limit'),
    );
    expect(notice.emailSent, isFalse);
    expect(notice.error, 'SMTP rate limit',
        reason: 'el motivo real del fallo, no una afirmación fija');
    expect(notice.tempPassword, 'TMP-abc123',
        reason: 'respaldo visible solo al fallar el envío');
  });

  test('el alta de prueba invoca notifyTrialFounder y no afirma falta de correo', () {
    final src = File('lib/features/platform/platform_home_screen.dart')
        .readAsStringSync();
    expect(src.contains('notifyTrialFounder(founder'), isTrue,
        reason: 'al crear el fundador debe enviarse el correo (notifyTrialFounder)');
    expect(src.contains('no hay correo de invitación configurado'), isFalse,
        reason: 'la afirmación fija y falsa de que no hay correo no debe existir');
  });
}
