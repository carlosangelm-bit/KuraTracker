// REEMPLAZA a admin_deep_back_button_scan_test (§13.1): las 8 hijas PROFUNDAS de
// /admin ya NO son pantallas completas con flecha de volver propia — decisión de
// Carlos (17-sep): ahora viven DENTRO del shell de Administración (riel visible),
// como CUERPOS. El título y la navegación los pone el shell (el riel), no la pantalla.
//
// Reja de FUENTE, enumerada (como la de KuraColors): lee los .dart, no monta nada
// (dos de las pantallas —Acuity— disparan red en initState y ensucian el widget test).
// Exige que cada una de las 8 esté (a) cableada como case en el switch de
// AdminSectionBody —así se RENDERIZA en el shell— y (b) declarada como ruta hija bajo
// el ShellRoute de /admin. Una novena se añade AQUÍ el día que se declare.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// sufijo de ruta (/admin/<sufijo>) → clase de pantalla-cuerpo que el shell construye.
// productos-protocolo = la Matriz (que en modo tabla-propia delega en
// ProtocolProductRulesScreen, también un cuerpo, pero NO es una entrada del riel).
const _deep = <String, String>{
  'protocolo-kura': 'ProtocolKuraScreen',
  'productos-protocolo': 'ProtocolMatrixScreen',
  'escalas-protocolo': 'ScaleTogglesScreen',
  'fuente-recomendaciones': 'RecommendationsReferenceScreen',
  'tipo-cita-sesiones': 'AcuitySessionTypeScreen',
  'tipos-consulta': 'AcuityVisitTypeMapScreen',
  'divulgaciones': 'DataDisclosuresScreen',
  'depurar-expedientes': 'PatientCleanupScreen',
};

void main() {
  test('las 8 profundas están cableadas en AdminSectionBody (cuerpo en el shell)', () {
    final src =
        File('lib/features/admin/admin_home_screen.dart').readAsStringSync();
    final missing = <String>[];
    _deep.forEach((suffix, cls) {
      if (!src.contains("case '$suffix':") || !src.contains(cls)) {
        missing.add('$suffix→$cls');
      }
    });
    expect(missing, isEmpty,
        reason: 'sin case (o sin la clase) en AdminSectionBody, así que no se '
            'renderiza en el shell:\n${missing.join('\n')}');
  });

  test('las 8 profundas están declaradas como ruta hija bajo el shell de /admin',
      () {
    final router =
        File('lib/core/router/app_router.dart').readAsStringSync();
    // El shell arma las rutas con `for (final s in const [ ... ]) '/admin/$s'`,
    // así que el sufijo aparece como literal en esa lista.
    final missing =
        _deep.keys.where((s) => !router.contains("'$s'")).toList();
    expect(missing, isEmpty,
        reason: 'sin ruta bajo el ShellRoute de /admin: ${missing.join(', ')}');
  });

  // Guarda de enumeración: si el riel de /admin gana una hija profunda nueva
  // (kura_nav_destinations), hay que añadirla a _deep. Se deriva contando las rutas
  // '/admin/<x>' del riel que NO son de las 6 secciones.
  test('no hay una novena profunda en el riel sin cubrir en la reja', () {
    final nav =
        File('lib/core/nav/kura_nav_destinations.dart').readAsStringSync();
    const sections = {
      'usuarios', 'personal', 'sitios', 'configuracion', 'marca', 'licencias'
    };
    final deepInRail = RegExp(r"route:\s*'/admin/([a-z0-9-]+)'")
        .allMatches(nav)
        .map((m) => m.group(1)!)
        .where((s) => !sections.contains(s))
        .toSet();
    expect(deepInRail.length, _deep.length,
        reason: 'el riel declara ${deepInRail.length} profundas '
            '(${deepInRail.toList()..sort()}) pero _deep lista ${_deep.length}. '
            'Añade la nueva a la reja.');
  });
}
