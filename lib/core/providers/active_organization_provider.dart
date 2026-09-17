import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_provider.dart';

/// Centro ACTIVO de la sesión (decisión Carlos 17-sep-2026).
///
/// La regla que cierra cinco criterios distintos: la CAPACIDAD (qué módulos pagó un
/// centro) se pregunta SIEMPRE sobre el centro ACTIVO, no sobre el centro de ORIGEN
/// del usuario (`sessionUser.organizationId`). Para todo usuario que no sea master,
/// activo == origen, byte por byte (propiedad de seguridad, con prueba). El master
/// puede INSPECCIONAR un centro ajeno; esa selección es una anulación de SESIÓN, no
/// muta su `profiles.organization_id` (no cambia su centro de origen como efecto
/// secundario), y PERSISTE entre recargas (si no, el master recarga, cae en silencio
/// a su origen, y el candado "vuelve" sin explicación).
///
/// Escritores de la anulación: SOLO el selector de /platform (y cualquier selector
/// futuro). El switcher de apósitos NO usa esto: sigue escribiendo profiles.

/// Anulación del centro activo (master). Persistida en SharedPreferences (sobrevive
/// la recarga web). null = sin anulación → se usa el centro de origen.
class ActiveOrgOverride extends StateNotifier<String?> {
  ActiveOrgOverride() : super(null) {
    _load();
  }

  /// Sin cargar de SharedPreferences: para pruebas deterministas (evita la carrera
  /// del _load async). Solo tests.
  @visibleForTesting
  ActiveOrgOverride.withValue(String? initial) : super(initial);

  static const _key = 'active_org_override';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_key);
  }

  /// Fija (o limpia, con null) la anulación y la persiste. La llama SOLO el selector
  /// de /platform.
  Future<void> set(String? organizationId) async {
    state = organizationId;
    final prefs = await SharedPreferences.getInstance();
    if (organizationId == null) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, organizationId);
    }
  }
}

final activeOrgOverrideProvider =
    StateNotifierProvider<ActiveOrgOverride, String?>((ref) => ActiveOrgOverride());

/// El centro ACTIVO: sobre este se pregunta la CAPACIDAD (premium*For / entitlements)
/// en todo el Grupo A (/admin y pantallas clínicas de primer nivel).
///
/// NO-MASTER: devuelve EXACTAMENTE `sessionUser.organizationId` — nunca mira la
/// anulación, así el comportamiento queda idéntico al de hoy (garantizado por prueba).
/// MASTER: la anulación de /platform si existe; si no, su centro de origen.
final activeOrganizationIdProvider = Provider<String?>((ref) {
  final user = ref.watch(sessionProvider).user;
  final home = user?.organizationId;
  if (user == null || !user.isMaster) return home;
  return ref.watch(activeOrgOverrideProvider) ?? home;
});
