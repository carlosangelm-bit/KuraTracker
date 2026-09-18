import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// La REGLA DEL MASTER, cableada UNA SOLA VEZ.
///
/// Lanza el flujo "Otorgar" del master, PRESELECCIONADO al módulo que le falta a un
/// centro. Devuelve true si se otorgó. La IMPLEMENTACIÓN vive en la capa de features
/// (platform/derechos, que conoce el diálogo de otorgamiento y el repo) y se INYECTA en
/// la raíz (ProviderScope override en main), para que un widget de `core`
/// ([KuraModuleLock]) pueda ofrecer el otorgamiento SIN que core dependa de features.
///
/// Default null: en pruebas de core sin override (o si algo falla) simplemente no hay
/// atajo de master — nunca un muro de venta en su lugar.
typedef MasterGrantLauncher = Future<bool> Function(
  BuildContext context, {
  required String organizationId,
  required String moduleKey,
  required String moduleName,
});

final masterGrantLauncherProvider =
    Provider<MasterGrantLauncher?>((ref) => null);

/// Época de derechos: se incrementa tras un otorgamiento para que los candados que la
/// observan se reconstruyan y vuelvan a leer `hasModuleEntitlement` (ya refrescado en
/// caché por `masterGrantEntitlement`). Evita invalidar el repo entero (arranque en frío).
final entitlementsEpochProvider = StateProvider<int>((ref) => 0);
