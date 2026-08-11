import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/config/app_config.dart';
import '../models/adverse_event.dart';
import '../models/antecedentes.dart';
import '../models/app_user.dart';
import '../models/caregiver_patient_assignment.dart';
import '../models/center_type.dart';
import '../models/clinical_amendment.dart';
import '../models/module_key.dart';
import '../models/module_setting.dart';
import '../models/preventive_task.dart';
import '../models/consent.dart';
import '../models/consultation.dart';
import '../models/manual_appointment.dart';
import '../models/organization.dart';
import '../models/supply_product_mapping.dart';
import '../models/vac_therapy.dart';
import '../models/product_catalog_item.dart';
import '../models/patient_lab.dart';
import '../models/inventory.dart';
import '../models/consultation_supply_usage.dart';
import '../models/commercial.dart';
import '../models/user_center_membership.dart';
import '../models/patient.dart';
import '../models/patient_admission.dart';
import '../models/patient_diagnosis.dart';
import '../models/preventive_action_log.dart';
import '../models/risk_assessment.dart';
import '../models/scale_assessment.dart';
import '../models/referral.dart';
import '../models/note_option_catalog.dart';
import '../models/site.dart';
import '../models/staff.dart';
import '../models/treatment_plan.dart';
import '../models/treatment_program.dart';
import '../models/protocol_product_rule.dart';
import '../models/wound.dart';
import '../engine/models/kura_engine_output.dart';
import '../engine/models/kura_engine_enums.dart';
import '../engine/cie10_catalog.dart';
import '../engine/params/clinical_params.dart';
import '../engine/risk/prevention_risk_engine.dart';
import '../engine/risk/scale_applicability.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'dart:typed_data';

import 'local_db/demo_seed.dart';
import 'local_db/local_store.dart';
import 'offline/offline_outbox.dart';
import 'offline/photo_outbox.dart';
import 'offline/read_cache_store.dart';
import 'photo_upload_service.dart';
import 'remote/data_store.dart';
import 'remote/supabase_data_store.dart';

const _uuid = Uuid();

/// "Método" sintético bajo el cual el mapeo de insumos agrupa los materiales
/// del catálogo del centro (Configuración → Material utilizado). Fuente única
/// de verdad para que el mapeo y la nota de seguimiento apunten a lo mismo.
const kCenterMaterialsMethod = 'Material del centro';

/// Repositorio unico de datos para toda la app.
///
/// Encapsula el almacen de datos (via la interfaz [DataStore]) exponiendo
/// una API tipada por entidad. La estructura de esta clase refleja 1:1 el
/// esquema SQL de Supabase (supabase/migrations).
///
/// BACKEND: segun [AppConfig.isSupabaseConfigured], `instance()` construye
/// un [SupabaseDataStore] (produccion, Postgrest + RLS en vivo) o un
/// [LocalStoreDataStore] (demo offline-first con datos sinteticos
/// precargados). En ambos casos, [DataRepository] usa exactamente la misma
/// API publica sincrona-en-lectura / asincrona-en-escritura, por lo que
/// ninguna pantalla necesita saber cual backend esta activo.
class DataRepository {
  final DataStore _store;

  /// Cola de fotos offline (Fase 2). Solo en prod; null en demo/local.
  PhotoOutbox? _photoOutbox;

  // Reintento con backoff exponencial (Fase 4) mientras queden pendientes.
  Timer? _backoffTimer;
  int _backoffSeconds = 0;

  DataRepository._(this._store);

  static DataRepository? _instance;

  static Future<DataRepository> instance() async {
    if (_instance != null) return _instance!;

    if (AppConfig.isSupabaseConfigured) {
      // Offline-first (Fase 1): la cola persistente de escrituras se pasa al
      // store para que una falla por red encole en vez de perder la captura.
      final outbox = await OfflineOutbox.load();
      // Fase 3: caché de lectura persistente (IndexedDB) para ver expedientes
      // sin señal.
      final readCache = await ReadCacheStore.open();
      final store = SupabaseDataStore(Supabase.instance.client,
          outbox: outbox, readCache: readCache);
      // Precarga lo persistido ANTES de hidratar: si estamos offline (o mientras
      // hidrata), las lecturas ya funcionan; si hay red, hydrate lo refresca.
      store.primeCache(await readCache.loadAll());
      // Si hay sesion activa (usuario ya logueado en un run anterior de la
      // app / refresh de pagina), hidrata la cache de una vez. Si no hay
      // sesion aun, hydrate() se llama explicitamente desde el login
      // (ver SessionController) una vez autenticado, para que las policies
      // de RLS ya tengan auth.uid() disponible.
      if (Supabase.instance.client.auth.currentSession != null) {
        await store.hydrate();
      }
      _instance = DataRepository._(store);
      _instance!._photoOutbox = await PhotoOutbox.open();
      await _instance!.loadClinicalParams();
      _instance!._startOfflineSync();
      return _instance!;
    }

    final localStore = await LocalStore.instance();
    await DemoSeed.ensureSeeded(localStore);
    _instance = DataRepository._(LocalStoreDataStore(localStore));
    await _instance!.loadClinicalParams();
    return _instance!;
  }

  /// Fuerza la re-hidratacion de la cache (backend Supabase) tras login.
  /// No-op en modo local.
  Future<void> hydrateAfterLogin() async {
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.hydrate();
      // Con la cache ya poblada, registra en el motor los parámetros clínicos
      // guardados (o el asset si no hay ninguno).
      await loadClinicalParams();
      // Drena cualquier escritura/foto offline de una sesión anterior.
      unawaited(_syncAllOffline());
    }
  }

  // ---------------- Offline-first (Fase 1) ----------------

  /// Número de escrituras pendientes de sincronizar (para el indicador de UI).
  /// Null en modo demo/local (todo es local, no hay cola).
  ValueNotifier<int>? get pendingSyncCount {
    final store = _store;
    return store is SupabaseDataStore ? store.outbox?.pendingCount : null;
  }

  /// Aplica a Supabase las escrituras encoladas offline. Devuelve cuántas se
  /// sincronizaron. No-op (0) en modo local o sin cola.
  Future<int> syncOfflineOutbox() async {
    final store = _store;
    if (store is! SupabaseDataStore) return 0;
    return store.syncOutbox();
  }

  /// Fotos pendientes de subir (Fase 2), para el indicador de UI.
  ValueNotifier<int>? get photoPendingCount => _photoOutbox?.pendingCount;

  // ---- Fase 4: robustez (parking visible + reintentar/descartar) ----

  /// Escrituras parkeadas (fallo persistente / conflicto) que requieren atención.
  ValueNotifier<int>? get writeFailedCount {
    final store = _store;
    return store is SupabaseDataStore ? store.outbox?.failedCount : null;
  }

  /// Fotos parkeadas (fallo persistente) que requieren atención.
  ValueNotifier<int>? get photoFailedCount => _photoOutbox?.failedCount;

  List<OutboxOp> failedWriteOps() {
    final store = _store;
    return store is SupabaseDataStore
        ? (store.outbox?.failed() ?? const [])
        : const [];
  }

  Future<List<PendingPhoto>> failedPhotoOps() async =>
      (await _photoOutbox?.failed()) ?? const [];

  /// Descripciones legibles de lo parkeado, para la hoja de sincronización.
  List<String> failedDescriptions() {
    final out = failedWriteOps()
        .map((o) => '${o.status == 'conflict' ? 'Conflicto' : 'Rechazado'} · '
            '${o.type} en ${o.collection}'
            '${o.lastError != null ? ' — ${o.lastError}' : ''}')
        .toList();
    return out;
  }

  Future<List<String>> failedPhotoDescriptions() async =>
      (await failedPhotoOps()).map((p) => 'Foto pendiente: ${p.fileName}').toList();

  /// Reintenta las parkeadas (vuelven a pendientes) y sincroniza.
  Future<void> retryFailedOffline() async {
    final store = _store;
    if (store is SupabaseDataStore) await store.outbox?.retryFailed();
    await _photoOutbox?.retryFailed();
    await _syncAllOffline();
  }

  /// Descarta definitivamente las parkeadas.
  Future<void> discardFailedOffline() async {
    final store = _store;
    if (store is SupabaseDataStore) await store.outbox?.discardFailed();
    await _photoOutbox?.discardFailed();
  }

  /// Encola una foto capturada sin red: guarda los bytes localmente (IndexedDB)
  /// + los metadatos para crear la fila `wound_photos` al subirla. `meta` debe
  /// traer wound_id, consultation_id, measurement_id, is_baseline, photo_stage,
  /// taken_at.
  Future<void> enqueuePhoto({
    required Uint8List bytes,
    required String fileName,
    required Map<String, dynamic> meta,
    String contentType = 'image/jpeg',
  }) async {
    final box = _photoOutbox;
    if (box == null) return;
    await box.enqueue(
      PendingPhoto(
        localId: _uuid.v4(),
        fileName: fileName,
        contentType: contentType,
        bytes: bytes,
        meta: meta,
      ),
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  /// Tras fallar la subida de una foto durante la captura: si el error parece
  /// de RED, la encola (queda pendiente) y devuelve true; si no (rechazo real o
  /// cuota del modo demo), devuelve false para que el llamador avise.
  Future<bool> enqueuePhotoIfOffline({
    required Uint8List bytes,
    required String fileName,
    required Map<String, dynamic> meta,
    required Object error,
  }) async {
    if (_photoOutbox == null || !_looksNetworkError(error)) return false;
    await enqueuePhoto(bytes: bytes, fileName: fileName, meta: meta);
    return true;
  }

  /// Sube las fotos encoladas (cuando vuelve la red) y crea su fila
  /// `wound_photos`. En orden; se detiene si vuelve a fallar la red. Devuelve
  /// cuántas se subieron.
  Future<int> syncPhotoOutbox() async {
    final box = _photoOutbox;
    if (box == null) return 0;
    var applied = 0;
    for (final p in await box.pending()) {
      try {
        final path = await PhotoUploadService.uploadWoundPhoto(
          woundId: p.meta['wound_id'] as String,
          consultationId: p.meta['consultation_id'] as String,
          bytes: p.bytes,
          fileName: p.fileName,
        );
        await createPhoto({
          'wound_id': p.meta['wound_id'],
          'consultation_id': p.meta['consultation_id'],
          'measurement_id': p.meta['measurement_id'],
          'storage_path': path,
          'taken_at': p.meta['taken_at'],
          'is_baseline': p.meta['is_baseline'] ?? false,
          'photo_stage': p.meta['photo_stage'],
        });
        await box.remove(p.localId);
        applied++;
      } catch (e) {
        if (_looksNetworkError(e)) break; // sigue sin red: reintentar luego
        await box.markFailed(p.localId, '$e'); // rechazo real: parkear
      }
    }
    return applied;
  }

  bool _looksNetworkError(Object e) => !(e is StorageException ||
      e is PostgrestException ||
      e is AuthException ||
      e is FunctionException);

  /// Drena ambas colas en orden (primero escrituras, luego fotos que dependen
  /// de esas filas). Público para el botón "Sincronizar" del indicador.
  Future<void> syncOfflineNow() => _syncAllOffline();

  Future<void> _syncAllOffline() async {
    await syncOfflineOutbox();
    await syncPhotoOutbox();
    _scheduleBackoffIfPending();
  }

  /// Si quedan operaciones PENDIENTES (típicamente porque sigue sin red),
  /// reintenta con backoff exponencial (5s → … → máx 5 min). Si ya se drenó
  /// todo, resetea el backoff. Las parkeadas (failed/conflict) no cuentan.
  void _scheduleBackoffIfPending() {
    final store = _store;
    final writesPending =
        store is SupabaseDataStore ? (store.outbox?.pendingCount.value ?? 0) : 0;
    final photosPending = _photoOutbox?.pendingCount.value ?? 0;
    _backoffTimer?.cancel();
    if (writesPending + photosPending > 0) {
      _backoffSeconds =
          _backoffSeconds == 0 ? 5 : (_backoffSeconds * 2).clamp(5, 300);
      _backoffTimer = Timer(
          Duration(seconds: _backoffSeconds), () => unawaited(_syncAllOffline()));
    } else {
      _backoffSeconds = 0;
    }
  }

  /// Escucha la conectividad y drena las colas al recuperar la red. Se llama una
  /// vez al construir el repositorio (prod). El singleton vive toda la app, así
  /// que la suscripción no necesita cancelarse.
  void _startOfflineSync() {
    Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        _backoffSeconds = 0; // reconectó: reintenta ya, sin esperar backoff
        unawaited(_syncAllOffline());
      }
    });
  }

  /// Limpia la cache en memoria (backend Supabase) tras logout, para que
  /// un siguiente login (posiblemente de otro usuario) no vea datos
  /// residuales antes de re-hidratar. No-op en modo local.
  void clearCacheOnLogout() {
    final store = _store;
    if (store is SupabaseDataStore) {
      store.clearCache();
      // Fase 3: borra también la caché de lectura persistida (IndexedDB) para
      // que otro usuario en el mismo dispositivo no vea el expediente anterior.
      unawaited(store.readCache?.clear() ?? Future.value());
    }
  }

  /// Solo disponible en modo demo local (SharedPreferences). En produccion
  /// (Supabase) esto no aplica: los datos de prueba se cargan una sola vez
  /// via el script de seed SQL (ver supabase/seed/), no desde la app.
  Future<void> resetDemoData() async {
    if (_store is LocalStoreDataStore) {
      final localStore = await LocalStore.instance();
      await DemoSeed.resetAndReseed(localStore);
    }
  }

  // ---------------- Auth / usuarios ----------------
  // NOTA: en modo Supabase, el login/logout real (email+password via
  // Supabase Auth) vive en SessionController (core/providers/session_provider.dart).
  // Estos metodos siguen sirviendo para leer/administrar la tabla `profiles`
  // (p.ej. pantalla de administracion de usuarios) en ambos backends.

  List<AppUser> listUsers() {
    final profiles = _store.getAll(Collections.profiles);
    final staffList = _store.getAll(Collections.staff);
    return profiles.map((p) {
      final staffMatch = staffList.firstWhere(
        (s) => s['profile_id'] == p['id'],
        orElse: () => const {},
      );
      return AppUser.fromJson({
        ...p,
        'staff_id': staffMatch.isEmpty ? null : staffMatch['id'],
      });
    }).toList();
  }

  AppUser? findUserByEmail(String email) {
    final match = listUsers().where(
      (u) => u.email.toLowerCase() == email.toLowerCase(),
    );
    return match.isEmpty ? null : match.first;
  }

  Future<void> setUserActive(String userId, bool active) async {
    await _store.updateRow(Collections.profiles, userId, {'is_active': active});
  }

  Future<void> setUserPremium(String userId, bool premium) async {
    await _store.updateRow(Collections.profiles, userId, {'premium_enabled': premium});
  }

  /// Cambia el rol de un usuario (admin <-> clinico) desde el panel de
  /// Administracion / Plataforma. En Supabase, la RLS de profiles
  /// (profiles_update_own_or_admin) + el trigger anti-escalada
  /// (prevent_profile_privilege_escalation) permiten esto SOLO a admin/master;
  /// un clinico no puede auto-promoverse (0006/0012/0017).
  Future<void> setUserRole(String userId, AppRole role) async {
    await _store.updateRow(Collections.profiles, userId, {'role': role.dbValue});
  }

  /// Da de alta un usuario CON cuenta de acceso (login).
  ///
  /// En Supabase esto NO puede hacerse solo con la anon key: crear la cuenta
  /// en Auth requiere service role, asi que se delega en la Edge Function
  /// `admin-create-user` (que valida que el llamador sea admin/master, crea la
  /// cuenta, el profile y -para clinicos- el staff, y devuelve una contrasena
  /// temporal cuando no hay SMTP configurado). Ver supabase/functions/README.md.
  ///
  /// En modo demo local (sin Supabase) no hay Auth real: se crea directamente
  /// el profile (+ staff si es clinico) para que la pantalla sea funcional en
  /// la demo; [CreatedUser.tempPassword] queda null en ese caso.
  Future<CreatedUser> createUserWithLogin({
    required String email,
    required String fullName,
    required AppRole role,
    required String organizationId,
    String? phone,
    String? cedulaProfesional,
    String? primarySiteId,
    String roleTitle = 'Kurador',
    String? password,
  }) async {
    final store = _store;
    if (store is SupabaseDataStore) {
      Map<String, dynamic> data;
      try {
        data = await store.invokeFunction('admin-create-user', {
          'email': email,
          'fullName': fullName,
          'role': role.dbValue,
          'organizationId': organizationId,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (cedulaProfesional != null && cedulaProfesional.isNotEmpty)
            'cedulaProfesional': cedulaProfesional,
          if (primarySiteId != null) 'primarySiteId': primarySiteId,
          'roleTitle': roleTitle,
          if (password != null && password.isNotEmpty) 'password': password,
        });
      } on FunctionException catch (e) {
        throw Exception(_edgeErrorMessage(e));
      }
      if (data['error'] != null) throw Exception(data['error'].toString());
      // Refresca profiles y staff para que la lista refleje el alta sin
      // re-login (la Edge Function escribio con service role, fuera de la cache).
      await store.refreshCollection(Collections.profiles);
      await store.refreshCollection(Collections.staff);
      return CreatedUser(
        uid: data['uid'] as String,
        email: (data['email'] ?? email) as String,
        tempPassword: data['tempPassword'] as String?,
        role: role,
      );
    }

    // Modo demo local: sin Auth real.
    final uid = _uuid.v4();
    await _store.insertRow(Collections.profiles, {
      'id': uid,
      'role': role.dbValue,
      'full_name': fullName,
      'email': email,
      'is_active': true,
      'premium_enabled': false,
      'organization_id': organizationId,
    });
    if (role == AppRole.clinico || role == AppRole.enfermeria) {
      await createStaff(
        fullName: fullName,
        roleTitle: role == AppRole.enfermeria ? 'Enfermería' : roleTitle,
        organizationId: organizationId,
        primarySiteId: primarySiteId,
        profileId: uid,
        cedulaProfesional: cedulaProfesional,
      );
    }
    return CreatedUser(uid: uid, email: email, tempPassword: null, role: role);
  }

  String _edgeErrorMessage(FunctionException e) {
    final details = e.details;
    if (details is Map && details['error'] != null) return details['error'].toString();
    if (details is String && details.isNotEmpty) return details;
    return 'No se pudo crear el usuario (código ${e.status}).';
  }

  // ---------------- Organizaciones (centros) ----------------
  // (organizations, ver 0011_organizations.sql + 0012_master_role.sql).
  // Solo un usuario `master` puede listar TODAS las organizaciones y
  // crear/editar/eliminar directamente via REST (RLS de 0012); un admin
  // normal solo ve la suya (organizations_select_own), consistente con
  // el resto del panel de administracion.

  List<Organization> listOrganizations() =>
      _store.getAll(Collections.organizations).map(Organization.fromJson).toList();

  /// Organización (centro) por id, o null si no está en la cache.
  Organization? organizationById(String? organizationId) {
    if (organizationId == null) return null;
    for (final o in listOrganizations()) {
      if (o.id == organizationId) return o;
    }
    return null;
  }

  /// Tipo del centro dado (default clinica_heridas si no se resuelve). Alimenta
  /// la paleta reactiva (ver activeCenterTypeProvider) y los módulos por defecto.
  CenterType centerTypeFor(String? organizationId) =>
      organizationById(organizationId)?.centerType ?? CenterType.clinicaHeridas;

  // -------------------- Multi-centro: membresías + switch --------------------
  // (0040_center_types_memberships.sql). Un usuario puede pertenecer a varios
  // centros; el centro ACTIVO vive en profiles.organization_id. El switch lo
  // hace el RPC set_active_center validando membresía.

  /// Membresías (centros a los que puede entrar) del perfil dado.
  List<UserCenterMembership> listMembershipsFor(String profileId) => _store
      .getAll(Collections.userCenterMemberships)
      .map(UserCenterMembership.fromJson)
      .where((m) => m.profileId == profileId && m.isActive)
      .toList();

  /// Cambia el centro ACTIVO del usuario autenticado a [organizationId] (debe
  /// tener membresía activa). En Supabase usa el RPC set_active_center (que
  /// también fija el rol de esa membresía) y re-hidrata la cache; en demo
  /// actualiza el perfil directamente.
  Future<void> setActiveCenter(String profileId, String organizationId) async {
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.callRpc('set_active_center', {'target_org': organizationId});
      await hydrateAfterLogin();
    } else {
      // Demo: aplicar el rol de la membresía al perfil, igual que el RPC.
      final membership = listMembershipsFor(profileId)
          .where((m) => m.organizationId == organizationId);
      final role = membership.isEmpty ? null : membership.first.role.dbValue;
      await _store.updateRow(Collections.profiles, profileId, {
        'organization_id': organizationId,
        if (role != null) 'role': role,
      });
    }
  }

  /// Fija el tipo de un centro (solo master; la RLS de organizations permite
  /// UPDATE al master, ver 0012). Cambia paleta y módulos por defecto.
  Future<void> setCenterType(String organizationId, CenterType type) async {
    await _store.updateRow(
        Collections.organizations, organizationId, {'center_type': type.dbValue});
  }

  /// Membresías de un centro (para gestionarlas desde Plataforma).
  List<UserCenterMembership> listMembershipsForOrg(String organizationId) => _store
      .getAll(Collections.userCenterMemberships)
      .map(UserCenterMembership.fromJson)
      .where((m) => m.organizationId == organizationId)
      .toList();

  /// Otorga a un usuario acceso (membresía) a un centro con un rol. Solo
  /// admin/master (RLS de user_center_memberships). Habilita que el usuario
  /// aparezca en el switcher de ese centro.
  Future<void> addMembership(String profileId, String organizationId, AppRole role) async {
    await _store.insertRow(Collections.userCenterMemberships, {
      'id': _uuid.v4(),
      'profile_id': profileId,
      'organization_id': organizationId,
      'role': role.dbValue,
      'is_active': true,
    });
  }

  /// Revoca una membresía (por id).
  Future<void> removeMembership(String membershipId) async {
    await _store.deleteRow(Collections.userCenterMemberships, membershipId);
  }

  // -------------------- Módulos configurables (Fase 2) --------------------
  // (0041_module_settings.sql). Overrides de habilitación por centro/sitio/
  // usuario; sin fila => default por tipo de centro (ModuleKey.defaultFor).

  List<ModuleSetting> listModuleSettings({String? organizationId}) => _store
      .getAll(Collections.moduleSettings)
      .map(ModuleSetting.fromJson)
      .where((m) => organizationId == null || m.organizationId == organizationId)
      .toList();

  /// Crea o actualiza el override de un módulo para un alcance
  /// (centro / sitio / usuario). Pasar [enabled] null borra el override
  /// (vuelve a heredar el nivel superior / default por tipo). Solo admin/master.
  Future<void> setModuleSetting({
    required String organizationId,
    String? siteId,
    String? profileId,
    required ModuleKey module,
    required bool? enabled,
    String? updatedBy,
  }) async {
    final existing = _store.getAll(Collections.moduleSettings).map(ModuleSetting.fromJson).where(
          (m) =>
              m.organizationId == organizationId &&
              m.siteId == siteId &&
              m.profileId == profileId &&
              m.moduleKey == module.dbValue,
        );
    if (enabled == null) {
      if (existing.isNotEmpty) {
        await _store.deleteRow(Collections.moduleSettings, existing.first.id);
      }
      return;
    }
    if (existing.isNotEmpty) {
      await _store.updateRow(Collections.moduleSettings, existing.first.id, {
        'enabled': enabled,
        'updated_by': updatedBy,
      });
    } else {
      await _store.insertRow(Collections.moduleSettings, {
        'id': _uuid.v4(),
        'organization_id': organizationId,
        'site_id': siteId,
        'profile_id': profileId,
        'module_key': module.dbValue,
        'enabled': enabled,
        'updated_by': updatedBy,
      });
    }
  }

  /// Estado EFECTIVO de un módulo para (centro, sitio, usuario), resolviendo
  /// usuario > sitio > centro > default-por-tipo.
  bool isModuleEnabled(
    ModuleKey module, {
    required String? organizationId,
    String? siteId,
    String? profileId,
  }) {
    if (organizationId == null) {
      return module.defaultFor(CenterType.clinicaHeridas);
    }
    final centerType = centerTypeFor(organizationId);
    // Módulo no disponible para este tipo de centro: apagado siempre, sin
    // importar ajustes previos (p.ej. eKare en hospital).
    if (!module.availableFor(centerType)) return false;
    final settings = listModuleSettings(organizationId: organizationId)
        .where((m) => m.moduleKey == module.dbValue)
        .toList();
    ModuleSetting? matchWhere(bool Function(ModuleSetting) test) {
      for (final m in settings) {
        if (test(m)) return m;
      }
      return null;
    }

    // usuario > sitio > centro
    final userOverride =
        profileId == null ? null : matchWhere((m) => m.profileId == profileId);
    if (userOverride != null) return userOverride.enabled;
    final siteOverride = siteId == null ? null : matchWhere((m) => m.siteId == siteId);
    if (siteOverride != null) return siteOverride.enabled;
    final centerOverride =
        matchWhere((m) => m.siteId == null && m.profileId == null);
    if (centerOverride != null) return centerOverride.enabled;

    return module.defaultFor(centerType);
  }

  /// Sitio primario del usuario (vía su fila de staff), para resolver overrides
  /// de módulo a nivel sitio. null si no tiene staff/sitio.
  String? primarySiteIdForProfile(String? profileId) {
    if (profileId == null) return null;
    for (final s in _store.getAll(Collections.staff)) {
      if (s['profile_id'] == profileId) return s['primary_site_id'] as String?;
    }
    return null;
  }

  /// Conjunto de módulos habilitados para el contexto dado (para el nav).
  Set<ModuleKey> enabledModules({
    required String? organizationId,
    String? siteId,
    String? profileId,
  }) {
    return ModuleKey.values
        .where((m) => isModuleEnabled(m,
            organizationId: organizationId, siteId: siteId, profileId: profileId))
        .toSet();
  }

  /// Crea una organizacion (centro) nueva. Uso exclusivo del area
  /// "Plataforma" (solo master, ver PlatformHomeScreen): a diferencia del
  /// RPC create_organization_with_admin (que ademas promueve al llamador
  /// a admin de la organizacion nueva), esto es un INSERT directo -- el
  /// master sigue siendo master, no se vincula automaticamente como admin
  /// de la organizacion creada.
  Future<Organization> createOrganization(String name) async {
    final data = {
      'id': _uuid.v4(),
      'name': name,
      'is_active': true,
    };
    final saved = await _store.insertRow(Collections.organizations, data);
    return Organization.fromJson(saved);
  }

  Future<void> setOrganizationActive(String organizationId, bool active) async {
    await _store.updateRow(Collections.organizations, organizationId, {'is_active': active});
  }

  // ---------------- Agenda: modo por centro + citas manuales ----------------
  // (0020_manual_scheduling.sql). scheduling_mode: none | manual | acuity.

  /// Modo de agenda del centro (none | manual | acuity). 'none' si no se
  /// resuelve la organización.
  String schedulingModeFor(String? organizationId) {
    if (organizationId == null) return 'none';
    final org = listOrganizations().where((o) => o.id == organizationId);
    return org.isEmpty ? 'none' : org.first.schedulingMode;
  }

  /// Fija el branding del centro (color principal + logo) para los reportes.
  /// En Supabase usa el RPC set_org_branding (RLS de organizations es
  /// master-only); en demo actualiza la fila directo.
  Future<void> setOrgBranding(
    String organizationId, {
    String? primaryColor,
    String? logoPath,
  }) async {
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.callRpc('set_org_branding', {
        'p_org': organizationId,
        'p_primary_color': primaryColor,
        'p_logo_path': logoPath,
      });
      await store.refreshCollection(Collections.organizations);
    } else {
      await _store.updateRow(Collections.organizations, organizationId, {
        'brand_primary_color': primaryColor,
        'brand_logo_path': logoPath,
      });
    }
  }

  Future<void> setSchedulingMode(String organizationId, String mode) async {
    final store = _store;
    if (store is SupabaseDataStore) {
      // La RLS de organizations solo permite UPDATE al master; para que el admin
      // del centro pueda activar su modo de agenda se usa un RPC acotado
      // (set_scheduling_mode, 0021) y luego se refresca la cache.
      await store.callRpc('set_scheduling_mode', {
        'p_org': organizationId,
        'p_mode': mode,
      });
      await store.refreshCollection(Collections.organizations);
    } else {
      await _store.updateRow(
          Collections.organizations, organizationId, {'scheduling_mode': mode});
    }
  }

  /// Turnos configurados del centro (para la ventana de cumplimiento del módulo
  /// de prevención hospitalaria). Lista de {name, startHour, endHour}; vacía =
  /// sin turnos (ventana de 24 h por defecto).
  List<Map<String, dynamic>> shiftConfigFor(String? organizationId) {
    final org = _store
        .getAll(Collections.organizations)
        .where((o) => o['id'] == organizationId);
    final cfg = org.isEmpty ? null : org.first['shift_config'];
    if (cfg is! List) return const [];
    return cfg
        .whereType<Map>()
        .map((s) => {
              'name': s['name'],
              'startHour': (s['startHour'] as num?)?.toInt(),
              'endHour': (s['endHour'] as num?)?.toInt(),
            })
        .where((s) => s['startHour'] != null && s['endHour'] != null)
        .toList();
  }

  /// Fija los turnos del centro. En Supabase usa el RPC set_shift_config (0046,
  /// admin del centro o master); en demo actualiza la fila directo. Lista vacía
  /// = null (vuelve a la ventana de 24 h).
  Future<void> setShiftConfig(
      String organizationId, List<Map<String, dynamic>> shifts) async {
    final value = shifts.isEmpty ? null : shifts;
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.callRpc('set_shift_config', {
        'p_org': organizationId,
        'p_shifts': value,
      });
      await store.refreshCollection(Collections.organizations);
    } else {
      await _store.updateRow(
          Collections.organizations, organizationId, {'shift_config': value});
    }
  }

  // ---- Parámetros clínicos del motor (data-driven, 0071) ----

  /// Parámetros clínicos guardados (la fila más reciente) como strings JSON,
  /// o null si no hay ninguno (se usa el asset horneado por defecto).
  ({String thresholds, String archetypes, String version})?
      getStoredClinicalParams() {
    final rows = _store.getAll(Collections.clinicalParams);
    if (rows.isEmpty) return null;
    final latest = rows.reduce((a, b) =>
        (a['uploaded_at'] ?? '').toString().compareTo(
                    (b['uploaded_at'] ?? '').toString()) >=
                0
            ? a
            : b);
    return (
      thresholds: jsonEncode(latest['thresholds']),
      archetypes: jsonEncode(latest['archetypes']),
      version: (latest['version'] ?? '').toString(),
    );
  }

  /// Guarda parámetros clínicos nuevos (solo master). Supabase: RPC
  /// set_clinical_params (SECURITY DEFINER, 0071); demo: inserta fila local.
  /// El llamador YA debe haber validado el contenido (ver ClinicalParams).
  Future<void> setClinicalParams({
    required Map<String, dynamic> thresholds,
    required Map<String, dynamic> archetypes,
    required String version,
  }) async {
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.callRpc('set_clinical_params', {
        'p_thresholds': thresholds,
        'p_archetypes': archetypes,
        'p_version': version,
      });
      await store.refreshCollection(Collections.clinicalParams);
    } else {
      await _store.insertRow(Collections.clinicalParams, {
        'id': _uuid.v4(),
        'thresholds': thresholds,
        'archetypes': archetypes,
        'version': version,
        'uploaded_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  /// Registra en el motor los parámetros clínicos: usa los guardados
  /// (Supabase/local) si existen; si no, cae al asset horneado. Idempotente y
  /// seguro: si el guardado está corrupto, cae al asset. Se llama tras cada
  /// hidratación y al aplicar una carga nueva.
  Future<void> loadClinicalParams() async {
    try {
      final stored = getStoredClinicalParams();
      if (stored != null) {
        ClinicalParams.register(ClinicalParams.fromJsonStrings(
          thresholdsJson: stored.thresholds,
          archetypesJson: stored.archetypes,
        ));
        return;
      }
    } catch (e) {
      debugPrint('ClinicalParams guardados inválidos, uso el asset: $e');
    }
    if (!ClinicalParams.isLoaded) {
      await ClinicalParams.loadFromAssets();
    }
  }

  /// ¿El centro tiene la licencia premium del módulo de Insumos? (0047)
  bool premiumInsumosFor(String? organizationId) =>
      organizationById(organizationId)?.premiumInsumos ?? false;

  /// ¿El centro tiene el add-on premium "Protocolo Kura+"? (0049)
  bool premiumProtocoloKuraFor(String? organizationId) =>
      organizationById(organizationId)?.premiumProtocoloKura ?? false;

  /// Activa/desactiva el add-on premium "Protocolo Kura+" del centro (RPC
  /// set_org_premium_protocolo_kura, 0049, solo master).
  Future<void> setOrgPremiumProtocoloKura(
      String organizationId, bool enabled) async {
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.callRpc('set_org_premium_protocolo_kura', {
        'p_org': organizationId,
        'p_enabled': enabled,
      });
      await store.refreshCollection(Collections.organizations);
    } else {
      await _store.updateRow(Collections.organizations, organizationId,
          {'premium_protocolo_kura': enabled});
    }
  }

  /// Activa/desactiva la licencia premium de Insumos de un centro. En Supabase
  /// usa el RPC set_org_premium_insumos (0047, solo master); en demo actualiza
  /// la fila directo.
  Future<void> setOrgPremiumInsumos(String organizationId, bool enabled) async {
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.callRpc('set_org_premium_insumos', {
        'p_org': organizationId,
        'p_enabled': enabled,
      });
      await store.refreshCollection(Collections.organizations);
    } else {
      await _store.updateRow(Collections.organizations, organizationId,
          {'premium_insumos': enabled});
    }
  }

  // ---------------- Mapeo insumo↔producto (Insumos Fase 2, 0048) ----------------

  /// Mapeos insumo↔producto del centro.
  List<SupplyProductMapping> listSupplyMappings(String? organizationId) => _store
      .getAll(Collections.supplyProductMappings)
      .map(SupplyProductMapping.fromJson)
      .where((m) => organizationId == null || m.organizationId == organizationId)
      .toList();

  /// Mapa clave(`método::producto`) → LISTA de productos ligados. Un insumo
  /// genérico puede tener varios productos (distintas medidas/marcas/SKU); el
  /// especialista elige el específico al usarlo.
  Map<String, List<SupplyProductMapping>> supplyMappingGroups(
      String? organizationId) {
    final groups = <String, List<SupplyProductMapping>>{};
    for (final m in listSupplyMappings(organizationId)) {
      (groups[m.key] ??= []).add(m);
    }
    return groups;
  }

  /// Productos ligados a un insumo genérico concreto (método + genérico).
  List<SupplyProductMapping> supplyMappingsFor(
          String? organizationId, String method, String genericProduct) =>
      listSupplyMappings(organizationId)
          .where((m) => m.method == method && m.genericProduct == genericProduct)
          .toList();

  /// Nombres comerciales (producto de la tienda) que el centro mapeó a un
  /// material de su catálogo ([materialLabel], de Configuración → Material
  /// utilizado). Se usa en la nota de seguimiento para que el profesional vea
  /// qué producto CONCRETO corresponde al material sugerido/seleccionado, con
  /// terminología consistente en todo el flujo. Vacío si no hay mapeo.
  List<String> commercialNamesForCenterMaterial(
      String? organizationId, String materialLabel) {
    return supplyMappingsFor(organizationId, kCenterMaterialsMethod, materialLabel)
        .map((m) => m.shopifyVariantTitle == null || m.shopifyVariantTitle!.isEmpty
            ? m.shopifyTitle
            : '${m.shopifyTitle} · ${m.shopifyVariantTitle}')
        .toList();
  }

  // ---------------- Catálogo global de productos (0067) --------------------

  /// Catálogo global de productos (sembrado desde Shopify). Compartido entre
  /// centros: cualquiera lo lee para la carga masiva de inventario.
  List<ProductCatalogItem> listProductCatalog({bool activeOnly = true}) =>
      _store
          .getAll(Collections.productCatalog)
          .map(ProductCatalogItem.fromJson)
          .where((p) => !activeOnly || p.isActive)
          .toList()
        ..sort((a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));

  /// Dispara la sincronización del catálogo global desde Shopify (Admin API).
  /// Solo master, solo producción. Devuelve cuántos productos quedaron.
  Future<int> syncShopifyCatalog() async {
    final store = _store;
    if (store is! SupabaseDataStore) {
      throw Exception('La sincronización requiere el entorno de producción.');
    }
    Map<String, dynamic> data;
    try {
      data = await store.invokeFunction('shopify-sync-catalog', {});
    } on FunctionException catch (e) {
      throw Exception(_edgeErrorMessage(e));
    }
    if (data['error'] != null) {
      final hint = data['hint'];
      throw Exception(
          '${data['error']}${hint != null ? '\n$hint' : ''}');
    }
    await store.refreshCollection(Collections.productCatalog);
    return (data['distinct'] as num?)?.toInt() ??
        (data['upserted'] as num?)?.toInt() ??
        0;
  }

  /// Crea o actualiza el mapeo de un insumo genérico a un producto CONCRETO de
  /// la tienda. El upsert es por (centro, método, genérico, producto, variante):
  /// re-ligar el mismo producto/presentación actualiza su foto/precio; ligar uno
  /// distinto AGREGA otro producto al mismo insumo genérico (1→varios).
  Future<void> setSupplyMapping({
    required String organizationId,
    required String method,
    required String genericProduct,
    required String shopifyProductId,
    required String shopifyTitle,
    String? shopifyVariantId,
    String? shopifyVariantTitle,
    String? shopifyHandle,
    String? imageUrl,
    double? priceAmount,
    String? priceCurrency,
    String? updatedBy,
  }) async {
    final existing = listSupplyMappings(organizationId).where((m) =>
        m.method == method &&
        m.genericProduct == genericProduct &&
        m.shopifyProductId == shopifyProductId &&
        m.shopifyVariantId == shopifyVariantId);
    final now = DateTime.now().toIso8601String();
    final data = {
      'organization_id': organizationId,
      'method': method,
      'generic_product': genericProduct,
      'shopify_product_id': shopifyProductId,
      'shopify_variant_id': shopifyVariantId,
      'shopify_title': shopifyTitle,
      'shopify_variant_title': shopifyVariantTitle,
      'shopify_handle': shopifyHandle,
      'image_url': imageUrl,
      'price_amount': priceAmount,
      'price_currency': priceCurrency,
      'updated_by': updatedBy,
      'updated_at': now,
    };
    if (existing.isNotEmpty) {
      await _store.updateRow(
          Collections.supplyProductMappings, existing.first.id, data);
    } else {
      await _store.insertRow(Collections.supplyProductMappings, {
        'id': _uuid.v4(),
        'created_at': now,
        ...data,
      });
    }
  }

  /// Elimina UN producto ligado (por id de mapeo). Los demás productos del mismo
  /// insumo genérico se conservan.
  Future<void> deleteSupplyMappingById(String mappingId) async {
    await _store.deleteRow(Collections.supplyProductMappings, mappingId);
  }

  /// Elimina TODOS los productos ligados a un insumo genérico (deja el insumo
  /// sin producto).
  Future<void> deleteSupplyMapping({
    required String organizationId,
    required String method,
    required String genericProduct,
  }) async {
    final existing = listSupplyMappings(organizationId).where(
        (m) => m.method == method && m.genericProduct == genericProduct);
    for (final m in existing) {
      await _store.deleteRow(Collections.supplyProductMappings, m.id);
    }
  }

  // ---------------- Inventario (Insumos Fase 3, 0050) ----------------

  List<InventoryItem> listInventoryItems({
    String? organizationId,
    String? siteId,
    bool activeOnly = true,
  }) =>
      _store
          .getAll(Collections.inventoryItems)
          .map(InventoryItem.fromJson)
          .where((it) =>
              (organizationId == null || it.organizationId == organizationId) &&
              (siteId == null || it.siteId == siteId) &&
              (!activeOnly || it.isActive))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  List<InventoryMovement> listInventoryMovements({
    String? inventoryItemId,
    String? siteId,
    String? organizationId,
  }) =>
      _store
          .getAll(Collections.inventoryMovements)
          .map(InventoryMovement.fromJson)
          .where((m) =>
              (inventoryItemId == null || m.inventoryItemId == inventoryItemId) &&
              (siteId == null || m.siteId == siteId) &&
              (organizationId == null || m.organizationId == organizationId))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Alcance del inventario del centro: 'site' | 'center' (0053).
  String inventoryScopeFor(String? organizationId) =>
      organizationById(organizationId)?.inventoryScope ?? 'site';

  Future<void> setInventoryScope(String organizationId, String scope) async {
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.callRpc('set_org_inventory_scope', {
        'p_org': organizationId,
        'p_scope': scope,
      });
      await store.refreshCollection(Collections.organizations);
    } else {
      await _store.updateRow(
          Collections.organizations, organizationId, {'inventory_scope': scope});
    }
  }

  /// Compras (entradas reason=compra) recientes de un sitio, más nuevas primero.
  List<InventoryMovement> listRecentPurchases(String siteId, {int limit = 20}) {
    final all = _store
        .getAll(Collections.inventoryMovements)
        .map(InventoryMovement.fromJson)
        .where((m) => m.siteId == siteId && m.reason == InventoryReason.compra)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all.take(limit).toList();
  }

  /// Existencia actual de un artículo = suma de sus movimientos.
  int onHandFor(String inventoryItemId) => _store
      .getAll(Collections.inventoryMovements)
      .map(InventoryMovement.fromJson)
      .where((m) => m.inventoryItemId == inventoryItemId)
      .fold<int>(0, (a, m) => a + m.delta);

  /// Existencias por artículo (itemId → cantidad) de un sitio.
  Map<String, int> inventoryOnHand(String siteId) {
    final byItem = <String, int>{};
    for (final m in _store
        .getAll(Collections.inventoryMovements)
        .map(InventoryMovement.fromJson)
        .where((m) => m.siteId == siteId)) {
      byItem[m.inventoryItemId] = (byItem[m.inventoryItemId] ?? 0) + m.delta;
    }
    return byItem;
  }

  /// Crea un artículo de inventario (de la tienda Kura+ o externo).
  Future<InventoryItem> addInventoryItem({
    required String organizationId,
    required String siteId,
    required String name,
    bool isExternal = false,
    String? shopifyProductId,
    String? shopifyVariantId,
    String? shopifyInventoryItemId,
    String? imageUrl,
    double? unitCost,
    double? unitPrice,
    String? currency,
    String? supplier,
    int? reorderThreshold,
    String? notes,
    String? createdBy,
  }) async {
    final now = DateTime.now().toIso8601String();
    // Precio de venta por default = costo + 30% (editable después).
    final price = unitPrice ??
        (unitCost != null ? double.parse((unitCost * 1.3).toStringAsFixed(2)) : null);
    final data = {
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'site_id': siteId,
      'name': name,
      'is_external': isExternal,
      'shopify_product_id': shopifyProductId,
      'shopify_variant_id': shopifyVariantId,
      'shopify_inventory_item_id': shopifyInventoryItemId,
      'image_url': imageUrl,
      'unit_cost': unitCost,
      'unit_price': price,
      'currency': currency ?? 'MXN',
      'supplier': supplier,
      'reorder_threshold': reorderThreshold,
      'notes': notes,
      'is_active': true,
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    };
    final saved = await _store.insertRow(Collections.inventoryItems, data);
    return InventoryItem.fromJson(saved);
  }

  Future<void> updateInventoryItem(
    String id, {
    String? name,
    double? unitCost,
    double? unitPrice,
    String? supplier,
    int? reorderThreshold,
    String? notes,
    bool? isActive,
  }) async {
    final patch = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (name != null) patch['name'] = name;
    if (unitCost != null) patch['unit_cost'] = unitCost;
    if (unitPrice != null) patch['unit_price'] = unitPrice;
    if (supplier != null) patch['supplier'] = supplier;
    if (reorderThreshold != null) patch['reorder_threshold'] = reorderThreshold;
    if (notes != null) patch['notes'] = notes;
    if (isActive != null) patch['is_active'] = isActive;
    await _store.updateRow(Collections.inventoryItems, id, patch);
  }

  /// Registra un movimiento (entrada +, salida −) y actualiza la existencia.
  Future<InventoryMovement> addInventoryMovement({
    required InventoryItem item,
    required int delta,
    required InventoryReason reason,
    double? unitCost,
    String? patientId,
    String? consultationId,
    String? note,
    String? createdBy,
  }) async {
    final data = {
      'id': _uuid.v4(),
      'organization_id': item.organizationId,
      'site_id': item.siteId,
      'inventory_item_id': item.id,
      'delta': delta,
      'reason': reason.dbValue,
      'unit_cost': unitCost,
      'patient_id': patientId,
      'consultation_id': consultationId,
      'note': note,
      'created_by': createdBy,
      'created_at': DateTime.now().toIso8601String(),
    };
    final saved = await _store.insertRow(Collections.inventoryMovements, data);
    // Espejo Shopify (Kura+): cualquier movimiento local (salvo 'ajuste', que es
    // la propia bajada desde Shopify) se refleja en la tienda. Best-effort: si
    // falla, la próxima sincronización reconcilia.
    if (reason != InventoryReason.ajuste) {
      await _maybePushShopifyAdjust(item, delta);
    }
    return InventoryMovement.fromJson(saved);
  }

  /// Ajusta la existencia en Shopify (espejo Kura+) si el artículo está ligado
  /// y el centro es espejo. Solo producción; nunca rompe el flujo local.
  Future<void> _maybePushShopifyAdjust(InventoryItem item, int delta) async {
    final store = _store;
    if (store is! SupabaseDataStore) return;
    if (item.shopifyInventoryItemId == null) return;
    if (!shopifyMirrorFor(item.organizationId)) return;
    try {
      await store.invokeFunction('shopify-inventory', {
        'action': 'adjust',
        'inventoryItemId': item.shopifyInventoryItemId,
        'delta': delta,
      });
    } catch (e) {
      debugPrint('Ajuste a Shopify falló (se reconciliará en la próxima sync): $e');
    }
  }

  /// ¿El centro mantiene su inventario como espejo de Shopify? (Kura+.)
  bool shopifyMirrorFor(String? organizationId) =>
      organizationById(organizationId)?.shopifyMirror ?? false;

  /// Marca/desmarca un centro como espejo de Shopify (solo master).
  Future<void> setOrgShopifyMirror(String organizationId, bool value) async {
    final store = _store;
    await store.updateRow(
        Collections.organizations, organizationId, {'shopify_mirror': value});
    if (store is SupabaseDataStore) {
      await store.refreshCollection(Collections.organizations);
    }
  }

  /// Bajada del espejo: trae las existencias de Shopify y ajusta el inventario
  /// del sitio del centro Kura+ para que coincidan. Crea los artículos ligados
  /// que falten (con su inventory_item_id de Shopify para el push posterior).
  /// Devuelve cuántos artículos se ajustaron.
  Future<int> syncShopifyInventory(String? organizationId, String siteId) async {
    final store = _store;
    if (store is! SupabaseDataStore) {
      throw Exception('El espejo requiere el entorno de producción.');
    }
    if (organizationId == null) throw Exception('Centro no resuelto.');
    Map<String, dynamic> data;
    try {
      data = await store.invokeFunction('shopify-inventory', {'action': 'levels'});
    } on FunctionException catch (e) {
      throw Exception(_edgeErrorMessage(e));
    }
    if (data['error'] != null) throw Exception(data['error'].toString());
    final levels = (data['levels'] as List?) ?? const [];

    final catalog = <String, ProductCatalogItem>{
      for (final c in listProductCatalog())
        '${c.shopifyProductId}|${c.shopifyVariantId ?? ''}': c,
    };
    final existing = listInventoryItems(
        organizationId: organizationId, siteId: siteId, activeOnly: false);
    final onHand = inventoryOnHand(siteId);

    var adjusted = 0;
    for (final lv in levels) {
      final m = lv as Map;
      final pid = m['productId']?.toString();
      final vid = m['variantId']?.toString() ?? '';
      final invItemId = m['inventoryItemId']?.toString();
      final available = (m['available'] as num?)?.toInt() ?? 0;
      if (pid == null || pid.isEmpty) continue;

      InventoryItem? item;
      for (final it in existing) {
        if (it.shopifyProductId == pid && (it.shopifyVariantId ?? '') == vid) {
          item = it;
          break;
        }
      }
      if (item == null) {
        final cat = catalog['$pid|$vid'] ?? catalog['$pid|'];
        item = await addInventoryItem(
          organizationId: organizationId,
          siteId: siteId,
          name: cat?.displayName ?? 'Producto',
          isExternal: false,
          shopifyProductId: pid,
          shopifyVariantId: vid.isEmpty ? null : vid,
          shopifyInventoryItemId: invItemId,
          unitPrice: cat?.price,
          currency: cat?.currency,
        );
      } else if (item.shopifyInventoryItemId == null && invItemId != null) {
        // Backfill del inventory_item_id de Shopify (para el push posterior).
        await store.updateRow(Collections.inventoryItems, item.id,
            {'shopify_inventory_item_id': invItemId});
      }

      final current = onHand[item.id] ?? 0;
      final delta = available - current;
      if (delta != 0) {
        // reason 'ajuste' NO hace push (evita el bucle con Shopify).
        await addInventoryMovement(
          item: item,
          delta: delta,
          reason: InventoryReason.ajuste,
          note: 'Sincronización Shopify',
        );
        adjusted++;
      }
    }
    await store.refreshCollection(Collections.inventoryItems);
    await store.refreshCollection(Collections.inventoryMovements);
    return adjusted;
  }

  // ------------- Consumo por paciente + costeo (Insumos Fase 4) -------------

  /// Movimientos de CONSUMO de un paciente (salidas ligadas a él).
  List<InventoryMovement> listConsumptionForPatient(String patientId) => _store
      .getAll(Collections.inventoryMovements)
      .map(InventoryMovement.fromJson)
      .where((m) => m.patientId == patientId && m.reason == InventoryReason.consumo)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Costo total de insumos consumidos por un paciente (Σ |delta| × costo).
  double consumptionCostForPatient(String patientId) {
    final itemsById = {for (final it in listInventoryItems(activeOnly: false)) it.id: it};
    var total = 0.0;
    for (final m in listConsumptionForPatient(patientId)) {
      final cost = m.unitCost ?? itemsById[m.inventoryItemId]?.unitCost ?? 0;
      total += cost * m.delta.abs();
    }
    return total;
  }

  // -------- Insumos utilizados en la consulta (Fase B) --------

  List<ConsultationSupplyUsage> listSupplyUsageForConsultation(String consultationId) =>
      _store
          .getAll(Collections.consultationSupplyUsage)
          .map(ConsultationSupplyUsage.fromJson)
          .where((u) => u.consultationId == consultationId)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Total a COBRAR por insumos de una consulta (solo las líneas con charge).
  double consultationSuppliesChargeTotal(String consultationId) =>
      listSupplyUsageForConsultation(consultationId)
          .where((u) => u.charge)
          .fold<double>(0, (a, u) => a + u.lineTotal);

  /// Componentes (método/producto) de TODOS los planes de una consulta.
  List<TreatmentComponentRecord> treatmentComponentsForConsultation(
      String consultationId) {
    final planIds = _store
        .getAll(Collections.treatmentPlans)
        .where((p) => p['consultation_id'] == consultationId)
        .map((p) => p['id'])
        .toSet();
    return _store
        .getAll(Collections.treatmentComponents)
        .where((c) => planIds.contains(c['treatment_plan_id']))
        .map(TreatmentComponentRecord.fromJson)
        .toList();
  }

  Future<ConsultationSupplyUsage> addSupplyUsage({
    required String organizationId,
    required String consultationId,
    required String? patientId,
    required String name,
    String? inventoryItemId,
    int quantity = 1,
    bool charge = true,
    bool discount = true,
    double? unitCost,
    double? unitPrice,
    String? currency,
    String? createdBy,
  }) async {
    final now = DateTime.now().toIso8601String();
    final saved = await _store.insertRow(Collections.consultationSupplyUsage, {
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'consultation_id': consultationId,
      'patient_id': patientId,
      'inventory_item_id': inventoryItemId,
      'name': name,
      'quantity': quantity,
      'charge': charge,
      'discount': discount,
      'unit_cost': unitCost,
      'unit_price': unitPrice,
      'currency': currency ?? 'MXN',
      'discounted': false,
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    });
    return ConsultationSupplyUsage.fromJson(saved);
  }

  Future<void> updateSupplyUsage(
    String id, {
    int? quantity,
    bool? charge,
    bool? discount,
  }) async {
    final patch = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (quantity != null) patch['quantity'] = quantity;
    if (charge != null) patch['charge'] = charge;
    if (discount != null) patch['discount'] = discount;
    await _store.updateRow(Collections.consultationSupplyUsage, id, patch);
  }

  Future<void> deleteSupplyUsage(String id) async =>
      _store.deleteRow(Collections.consultationSupplyUsage, id);

  // ---------------- Módulo comercial (Fase C, 0052) ----------------

  List<ServiceCatalogItem> listServices(String? organizationId,
          {bool activeOnly = true}) =>
      _store
          .getAll(Collections.serviceCatalog)
          .map(ServiceCatalogItem.fromJson)
          .where((s) =>
              (organizationId == null || s.organizationId == organizationId) &&
              (!activeOnly || s.isActive))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Future<ServiceCatalogItem> addService({
    required String organizationId,
    required String name,
    required double price,
    String? createdBy,
  }) async {
    final now = DateTime.now().toIso8601String();
    final saved = await _store.insertRow(Collections.serviceCatalog, {
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'name': name,
      'price': price,
      'currency': 'MXN',
      'is_active': true,
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    });
    return ServiceCatalogItem.fromJson(saved);
  }

  Future<void> updateService(String id,
      {String? name, double? price, bool? isActive}) async {
    final patch = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (name != null) patch['name'] = name;
    if (price != null) patch['price'] = price;
    if (isActive != null) patch['is_active'] = isActive;
    await _store.updateRow(Collections.serviceCatalog, id, patch);
  }

  List<Charge> listCharges({String? organizationId, String? patientId, ChargeStatus? status}) =>
      _store
          .getAll(Collections.charges)
          .map(Charge.fromJson)
          .where((c) =>
              (organizationId == null || c.organizationId == organizationId) &&
              (patientId == null || c.patientId == patientId) &&
              (status == null || c.status == status))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Charge? chargeForConsultation(String consultationId) {
    final list = _store
        .getAll(Collections.charges)
        .map(Charge.fromJson)
        .where((c) => c.consultationId == consultationId && c.status != ChargeStatus.cancelado)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.isEmpty ? null : list.first;
  }

  List<ChargeItem> listChargeItems(String chargeId) => _store
      .getAll(Collections.chargeItems)
      .map(ChargeItem.fromJson)
      .where((i) => i.chargeId == chargeId)
      .toList();

  /// Totales de cobros de un paciente: {pagado, pendiente}.
  ({double paid, double pending}) patientChargeTotals(String patientId) {
    var paid = 0.0, pending = 0.0;
    for (final c in listCharges(patientId: patientId)) {
      if (c.status == ChargeStatus.pagado) paid += c.total;
      if (c.status == ChargeStatus.pendiente) pending += c.total;
    }
    return (paid: paid, pending: pending);
  }

  /// Crea el cobro de una consulta: honorario del servicio + insumos marcados
  /// "cobrar" (0051). Genera el desglose (charge_items). Estado inicial pendiente.
  Future<Charge> createChargeForConsultation({
    required String organizationId,
    required String consultationId,
    required String? patientId,
    required String? siteId,
    required String serviceName,
    required double servicePrice,
    String? createdBy,
  }) async {
    final usage = listSupplyUsageForConsultation(consultationId).where((u) => u.charge);
    final suppliesTotal = usage.fold<double>(0, (a, u) => a + u.lineTotal);
    final total = servicePrice + suppliesTotal;
    final now = DateTime.now().toIso8601String();
    final chargeId = _uuid.v4();
    final saved = await _store.insertRow(Collections.charges, {
      'id': chargeId,
      'organization_id': organizationId,
      'patient_id': patientId,
      'consultation_id': consultationId,
      'site_id': siteId,
      'subtotal_service': servicePrice,
      'subtotal_supplies': suppliesTotal,
      'total': total,
      'currency': 'MXN',
      'status': 'pendiente',
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    });
    // Desglose: servicio + un renglón por insumo cobrado.
    await _store.insertRow(Collections.chargeItems, {
      'id': _uuid.v4(),
      'charge_id': chargeId,
      'organization_id': organizationId,
      'kind': 'servicio',
      'name': serviceName,
      'quantity': 1,
      'unit_price': servicePrice,
      'line_total': servicePrice,
      'created_at': now,
    });
    for (final u in usage) {
      await _store.insertRow(Collections.chargeItems, {
        'id': _uuid.v4(),
        'charge_id': chargeId,
        'organization_id': organizationId,
        'kind': 'insumo',
        'name': u.name,
        'quantity': u.quantity,
        'unit_price': u.unitPrice ?? u.unitCost ?? 0,
        'line_total': u.lineTotal,
        'usage_id': u.id,
        'inventory_item_id': u.inventoryItemId,
        'created_at': now,
      });
    }
    return Charge.fromJson(saved);
  }

  /// Crea un cobro DIRECTO (sin consulta) desde la pestaña Cobros: renglones
  /// libres de servicios (tipos de consulta) y/o productos (inventario). El
  /// paciente es opcional (venta de mostrador). Estado inicial pendiente; al
  /// pagarse, los renglones con inventory_item_id descuentan stock (markChargePaid).
  Future<Charge> createManualCharge({
    required String organizationId,
    String? patientId,
    String? siteId,
    required List<
            ({
              String kind,
              String name,
              int quantity,
              double unitPrice,
              String? inventoryItemId
            })>
        lines,
    String? createdBy,
  }) async {
    if (lines.isEmpty) {
      throw Exception('Agrega al menos un concepto al cobro.');
    }
    final now = DateTime.now().toIso8601String();
    final chargeId = _uuid.v4();
    double svc = 0, sup = 0;
    for (final l in lines) {
      final lt = l.unitPrice * l.quantity;
      if (l.kind == 'servicio') {
        svc += lt;
      } else {
        sup += lt;
      }
    }
    final saved = await _store.insertRow(Collections.charges, {
      'id': chargeId,
      'organization_id': organizationId,
      'patient_id': patientId,
      'consultation_id': null,
      'site_id': siteId,
      'subtotal_service': svc,
      'subtotal_supplies': sup,
      'total': svc + sup,
      'currency': 'MXN',
      'status': 'pendiente',
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    });
    for (final l in lines) {
      await _store.insertRow(Collections.chargeItems, {
        'id': _uuid.v4(),
        'charge_id': chargeId,
        'organization_id': organizationId,
        'kind': l.kind,
        'name': l.name,
        'quantity': l.quantity,
        'unit_price': l.unitPrice,
        'line_total': l.unitPrice * l.quantity,
        if (l.inventoryItemId != null) 'inventory_item_id': l.inventoryItemId,
        'created_at': now,
      });
    }
    return Charge.fromJson(saved);
  }

  /// Marca un cobro como pagado y materializa el DESCUENTO de inventario de los
  /// insumos de la consulta marcados "descontar" (que aún no se hayan descontado).
  Future<void> markChargePaid(
    String chargeId,
    String method, {
    String? createdBy,
    String? provider,
    String? mpPaymentId,
    String? externalReference,
    String? mpStatus,
  }) async {
    final charge = _store
        .getAll(Collections.charges)
        .map(Charge.fromJson)
        .firstWhere((c) => c.id == chargeId);
    final wasPaid = charge.status == ChargeStatus.pagado;
    await _store.updateRow(Collections.charges, chargeId, {
      'status': 'pagado',
      'payment_method': method,
      'paid_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
      if (provider != null) 'payment_provider': provider,
      if (mpPaymentId != null) 'mp_payment_id': mpPaymentId,
      if (externalReference != null) 'external_reference': externalReference,
      if (mpStatus != null) 'mp_status': mpStatus,
    });
    // Descontar del inventario los insumos "descontar" no descontados.
    final consultId = charge.consultationId;
    if (consultId == null) {
      // Cobro DIRECTO (sin consulta): descuenta los productos del desglose que
      // tengan inventory_item_id. Solo en la primera vez que se marca pagado.
      if (!wasPaid) {
        await _discountManualChargeInventory(charge, createdBy: createdBy);
      }
      return;
    }
    final items = {for (final it in listInventoryItems(activeOnly: false)) it.id: it};
    for (final u in listSupplyUsageForConsultation(consultId)) {
      if (!u.discount || u.discounted || u.inventoryItemId == null) continue;
      final item = items[u.inventoryItemId];
      if (item == null) continue;
      await addInventoryMovement(
        item: item,
        delta: -u.quantity,
        reason: InventoryReason.consumo,
        unitCost: u.unitCost ?? item.unitCost,
        patientId: u.patientId,
        consultationId: consultId,
        note: 'Consumo cobrado (consulta)',
        createdBy: createdBy,
      );
      await _store.updateRow(Collections.consultationSupplyUsage, u.id,
          {'discounted': true, 'updated_at': DateTime.now().toIso8601String()});
    }
  }

  /// Descuenta del inventario los productos de un cobro DIRECTO (sin consulta)
  /// al marcarse pagado: un movimiento de consumo por cada renglón con
  /// inventory_item_id. En Kura+ el consumo dispara el espejo con Shopify.
  Future<void> _discountManualChargeInventory(Charge charge,
      {String? createdBy}) async {
    final items = {
      for (final it in listInventoryItems(activeOnly: false)) it.id: it
    };
    for (final ci in listChargeItems(charge.id)) {
      final invId = ci.inventoryItemId;
      if (invId == null) continue;
      final item = items[invId];
      if (item == null) continue;
      await addInventoryMovement(
        item: item,
        delta: -ci.quantity,
        reason: InventoryReason.consumo,
        unitCost: item.unitCost,
        patientId: charge.patientId,
        note: 'Venta cobrada (cobro directo)',
        createdBy: createdBy,
      );
    }
  }

  Future<void> cancelCharge(String chargeId) async => _store.updateRow(
      Collections.charges, chargeId,
      {'status': 'cancelado', 'updated_at': DateTime.now().toIso8601String()});

  // ---------------- Conciliación Mercado Pago Point (0055) ----------------

  /// Pagos de terminal en la bandeja de conciliación. [linked]: true = ya
  /// ligados a un cobro, false = pendientes de ligar, null = todos.
  List<PointPayment> listPointPayments({String? organizationId, bool? linked}) =>
      _store
          .getAll(Collections.pointPayments)
          .map(PointPayment.fromJson)
          .where((p) =>
              (organizationId == null || p.organizationId == organizationId) &&
              (linked == null || p.isLinked == linked))
          .toList()
        ..sort((a, b) => (b.capturedAt ?? b.createdAt)
            .compareTo(a.capturedAt ?? a.createdAt));

  /// Registra un pago entrante de la terminal en la bandeja. En Fase 1 lo crea
  /// el staff a mano; en Fase 2 lo inserta la Edge Function del webhook de MP.
  Future<PointPayment> addPointPayment({
    required String organizationId,
    required double amount,
    String provider = 'mercadopago_point',
    String? method,
    String? externalReference,
    String? mpPaymentId,
    String? deviceId,
    String? description,
    DateTime? capturedAt,
    String status = 'approved',
    String source = 'manual',
    String? createdBy,
  }) async {
    final now = DateTime.now();
    final saved = await _store.insertRow(Collections.pointPayments, {
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'provider': provider,
      'mp_payment_id': mpPaymentId,
      'amount': amount,
      'currency': 'MXN',
      'status': status,
      'method': method,
      'external_reference': externalReference,
      'device_id': deviceId,
      'description': description,
      'captured_at': (capturedAt ?? now).toIso8601String(),
      'source': source,
      'created_by': createdBy,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    return PointPayment.fromJson(saved);
  }

  /// Liga un pago de terminal a un cobro y marca el cobro como pagado por MP
  /// (incluye el descuento de inventario, vía [markChargePaid]).
  Future<void> linkPointPaymentToCharge({
    required String paymentId,
    required String chargeId,
    String? linkedBy,
  }) async {
    final payment = _store
        .getAll(Collections.pointPayments)
        .map(PointPayment.fromJson)
        .firstWhere((p) => p.id == paymentId);
    await _store.updateRow(Collections.pointPayments, paymentId, {
      'charge_id': chargeId,
      'linked_by': linkedBy,
      'linked_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    await markChargePaid(
      chargeId,
      'tarjeta',
      createdBy: linkedBy,
      provider: 'mercadopago',
      mpPaymentId: payment.mpPaymentId,
      externalReference: payment.externalReference,
      mpStatus: payment.status,
    );
  }

  /// Consulta (PULL) a Mercado Pago el estado del pago de un cobro (por
  /// external_reference) y concilia si está aprobado. Devuelve el estado
  /// ('pagado' | 'approved' | 'pending' | 'sin_pago' | ...). Solo en producción.
  Future<String> syncMercadoPagoCharge(String chargeId) async {
    final store = _store;
    if (store is! SupabaseDataStore) {
      throw Exception('Verificar el pago requiere el entorno de producción.');
    }
    Map<String, dynamic> data;
    try {
      data = await store.invokeFunction('mercadopago-sync-charge', {
        'chargeId': chargeId,
      });
    } on FunctionException catch (e) {
      throw Exception(_edgeErrorMessage(e));
    }
    if (data['error'] != null) throw Exception(data['error'].toString());
    // El cobro pudo haber cambiado a 'pagado'; refresca la cache local.
    await store.refreshCollection(Collections.charges);
    await store.refreshCollection(Collections.pointPayments);
    return (data['status'] ?? 'desconocido').toString();
  }

  /// Crea un link de pago (Stripe Checkout) para un cobro vía Edge Function y
  /// devuelve la URL para ENVIAR al paciente. El pago se concilia por webhook.
  /// Solo en producción (Supabase).
  Future<String> createStripeCheckout(String chargeId, {String? title}) async {
    final store = _store;
    if (store is! SupabaseDataStore) {
      throw Exception('El link de pago requiere el entorno de producción.');
    }
    Map<String, dynamic> data;
    try {
      data = await store.invokeFunction('stripe-create-checkout', {
        'chargeId': chargeId,
        if (title != null) 'title': title,
      });
    } on FunctionException catch (e) {
      throw Exception(_edgeErrorMessage(e));
    }
    if (data['error'] != null) throw Exception(data['error'].toString());
    final url = data['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('Stripe no devolvió el link de pago.');
    }
    return url;
  }

  // ---- Terminal Mercado Pago Point (push a la terminal física, 0074) ----

  /// Lista las terminales Point de la cuenta (para que el master/admin elija
  /// cuál asignar al centro). Devuelve los dispositivos crudos de MP (cada uno
  /// con `id`, `operating_mode`, …) y el `mode` con que corrió la función
  /// ('test'|'prod') — útil para diagnosticar por qué la lista viene vacía.
  /// Solo en producción.
  Future<({List<Map<String, dynamic>> devices, String mode})>
      listPointDevices() async {
    final store = _store;
    if (store is! SupabaseDataStore) {
      throw Exception('La terminal requiere el entorno de producción.');
    }
    Map<String, dynamic> data;
    try {
      data = await store.invokeFunction('mercadopago-point-intent', {
        'action': 'list_devices',
      });
    } on FunctionException catch (e) {
      throw Exception(_edgeErrorMessage(e));
    }
    if (data['error'] != null) throw Exception(data['error'].toString());
    final devices = (data['devices'] as List?) ?? const [];
    return (
      devices: devices.cast<Map<String, dynamic>>(),
      mode: (data['mode'] as String?) ?? 'test',
    );
  }

  /// Fija la terminal Point del centro (RPC set_mp_point_device, 0074: master o
  /// admin del propio centro). `deviceId` vacío/null la desasigna.
  Future<void> setOrgPointDevice(String organizationId, String? deviceId) async {
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.callRpc('set_mp_point_device', {
        'p_org': organizationId,
        'p_device_id': deviceId,
      });
      await store.refreshCollection(Collections.organizations);
    } else {
      await _store.updateRow(Collections.organizations, organizationId,
          {'mp_point_device_id': (deviceId?.trim().isEmpty ?? true) ? null : deviceId});
    }
  }

  /// Fija el tipo de cita de Acuity para las sesiones del plan (RPC 0080:
  /// master o admin del centro). null lo desasigna.
  Future<void> setAcuitySessionType(String organizationId, int? typeId) async {
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.callRpc('set_acuity_session_type', {
        'p_org': organizationId,
        'p_type_id': typeId,
      });
      await store.refreshCollection(Collections.organizations);
    } else {
      await _store.updateRow(Collections.organizations, organizationId,
          {'acuity_session_type_id': typeId});
    }
  }

  /// Guarda el mapeo tipo de cita de Acuity (por nombre) → tipo de visita Kura
  /// (0083: master o admin del centro). [map] = {"<nombre>": "valoracion"|"seguimiento"}.
  Future<void> setAcuityTypeVisitMap(
      String organizationId, Map<String, String> map) async {
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.callRpc('set_acuity_type_visit_map', {
        'p_org': organizationId,
        'p_map': map,
      });
      await store.refreshCollection(Collections.organizations);
    } else {
      await _store.updateRow(Collections.organizations, organizationId,
          {'acuity_type_visit_map': map});
    }
  }

  /// Tipo de visita Kura mapeado para el nombre de un tipo de cita de Acuity, o
  /// null si ese tipo no está mapeado en el centro.
  VisitType? visitTypeForAcuityTypeName(String? organizationId, String? typeName) {
    if (organizationId == null || typeName == null || typeName.isEmpty) {
      return null;
    }
    final v = organizationById(organizationId)?.acuityTypeVisitMap[typeName];
    if (v == 'valoracion') return VisitType.valoracion;
    if (v == 'seguimiento') return VisitType.seguimiento;
    return null;
  }

  Site? siteById(String? siteId) {
    if (siteId == null) return null;
    final m = _store
        .getAll(Collections.sites)
        .where((s) => s['id'] == siteId);
    return m.isEmpty ? null : Site.fromJson(m.first);
  }

  /// Fija el tipo de cita de Acuity de un SITIO (RPC 0081: master o admin del
  /// centro dueño). null lo desasigna (hereda el del centro).
  Future<void> setSiteAcuitySessionType(String siteId, int? typeId) async {
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.callRpc('set_site_acuity_session_type', {
        'p_site': siteId,
        'p_type_id': typeId,
      });
      await store.refreshCollection(Collections.sites);
    } else {
      await _store.updateRow(
          Collections.sites, siteId, {'acuity_session_type_id': typeId});
    }
  }

  /// Pone una terminal en modo integrado (PDV) para que pueda recibir órdenes.
  Future<void> setPointDevicePdv(String deviceId) async {
    final store = _store;
    if (store is! SupabaseDataStore) {
      throw Exception('La terminal requiere el entorno de producción.');
    }
    Map<String, dynamic> data;
    try {
      data = await store.invokeFunction('mercadopago-point-intent', {
        'action': 'set_pdv',
        'deviceId': deviceId,
      });
    } on FunctionException catch (e) {
      throw Exception(_edgeErrorMessage(e));
    }
    if (data['error'] != null) throw Exception(data['error'].toString());
  }

  /// Envía la orden de cobro a la terminal Point (payment intent). La terminal
  /// pide la tarjeta; al aprobar, el webhook/pull concilia el cobro (0055).
  /// Devuelve el `intentId`. `deviceId` opcional (si no, usa la del centro).
  Future<String> createPointIntent(String chargeId,
      {String? deviceId, String? title}) async {
    final store = _store;
    if (store is! SupabaseDataStore) {
      throw Exception('La terminal requiere el entorno de producción.');
    }
    Map<String, dynamic> data;
    try {
      data = await store.invokeFunction('mercadopago-point-intent', {
        'action': 'create',
        'chargeId': chargeId,
        if (deviceId != null) 'deviceId': deviceId,
        if (title != null) 'title': title,
      });
    } on FunctionException catch (e) {
      throw Exception(_edgeErrorMessage(e));
    }
    if (data['error'] != null) throw Exception(data['error'].toString());
    await store.refreshCollection(Collections.charges);
    await store.refreshCollection(Collections.pointPayments);
    final intentId = data['intent_id'] as String?;
    if (intentId == null || intentId.isEmpty) {
      throw Exception('La terminal no devolvió una orden.');
    }
    return intentId;
  }

  /// Cancela la orden abierta en la terminal para un cobro (si aún no se pagó).
  Future<void> cancelPointIntent(String chargeId,
      {String? deviceId, String? intentId}) async {
    final store = _store;
    if (store is! SupabaseDataStore) {
      throw Exception('La terminal requiere el entorno de producción.');
    }
    Map<String, dynamic> data;
    try {
      data = await store.invokeFunction('mercadopago-point-intent', {
        'action': 'cancel',
        'chargeId': chargeId,
        if (deviceId != null) 'deviceId': deviceId,
        if (intentId != null) 'intentId': intentId,
      });
    } on FunctionException catch (e) {
      throw Exception(_edgeErrorMessage(e));
    }
    if (data['error'] != null) throw Exception(data['error'].toString());
    await store.refreshCollection(Collections.charges);
    await store.refreshCollection(Collections.pointPayments);
  }

  /// Inicia una conversación con el asistente VAC (CustomGPT vía Edge Function)
  /// y devuelve el sessionId. Solo en producción.
  Future<String> vacBotStart() async {
    final store = _store;
    if (store is! SupabaseDataStore) {
      throw Exception('El asistente requiere el entorno de producción.');
    }
    Map<String, dynamic> data;
    try {
      data = await store.invokeFunction('vac-bot', {'action': 'create'});
    } on FunctionException catch (e) {
      throw Exception(_edgeErrorMessage(e));
    }
    if (data['error'] != null) throw Exception(data['error'].toString());
    final id = data['sessionId'] as String?;
    if (id == null || id.isEmpty) {
      throw Exception('El asistente no devolvió una sesión.');
    }
    return id;
  }

  /// Envía un mensaje al asistente VAC y devuelve la respuesta.
  Future<String> vacBotSend(String sessionId, String prompt) async {
    final store = _store;
    if (store is! SupabaseDataStore) {
      throw Exception('El asistente requiere el entorno de producción.');
    }
    Map<String, dynamic> data;
    try {
      data = await store.invokeFunction('vac-bot', {
        'action': 'message',
        'sessionId': sessionId,
        'prompt': prompt,
      });
    } on FunctionException catch (e) {
      throw Exception(_edgeErrorMessage(e));
    }
    if (data['error'] != null) throw Exception(data['error'].toString());
    return (data['reply'] as String?) ?? '';
  }

  /// Inicia una conversación con el asistente de SOPORTE de la plataforma
  /// (CustomGPT vía Edge Function support-bot) y devuelve el sessionId. Solo en
  /// producción.
  Future<String> supportBotStart() async {
    final store = _store;
    if (store is! SupabaseDataStore) {
      throw Exception('El asistente requiere el entorno de producción.');
    }
    Map<String, dynamic> data;
    try {
      data = await store.invokeFunction('support-bot', {'action': 'create'});
    } on FunctionException catch (e) {
      throw Exception(_edgeErrorMessage(e));
    }
    if (data['error'] != null) throw Exception(data['error'].toString());
    final id = data['sessionId'] as String?;
    if (id == null || id.isEmpty) {
      throw Exception('El asistente no devolvió una sesión.');
    }
    return id;
  }

  /// Envía un mensaje al asistente de soporte y devuelve la respuesta. [context]
  /// es el contexto NO SENSIBLE del usuario ({rol, centro, ruta, pantalla}) para
  /// que el agente detecte el perfil y el proceso; nunca incluye datos del
  /// paciente (la Edge Function además borra ids de la ruta).
  Future<String> supportBotSend(
    String sessionId,
    String prompt, {
    Map<String, String>? context,
  }) async {
    final store = _store;
    if (store is! SupabaseDataStore) {
      throw Exception('El asistente requiere el entorno de producción.');
    }
    Map<String, dynamic> data;
    try {
      data = await store.invokeFunction('support-bot', {
        'action': 'message',
        'sessionId': sessionId,
        'prompt': prompt,
        if (context != null && context.isNotEmpty) 'context': context,
      });
    } on FunctionException catch (e) {
      throw Exception(_edgeErrorMessage(e));
    }
    if (data['error'] != null) throw Exception(data['error'].toString());
    return (data['reply'] as String?) ?? '';
  }

  /// Realtime: se suscribe a cambios en una tabla ([collection]) y, cada vez que
  /// llega un evento (INSERT/UPDATE/DELETE), refresca la caché de esa tabla y
  /// llama [onChange]. Sirve para que Cobros/Conciliación reflejen un pago en
  /// cuanto el webhook lo registra, sin refrescar la página a mano.
  ///
  /// Solo aplica en producción (Supabase); en demo devuelve `null` (sin
  /// realtime). Devuelve el canal como [Object] opaco para que la UI no dependa
  /// del tipo de Supabase; se cancela con [unwatch] en `dispose()`.
  Object? watchCollection(String collection, void Function() onChange) {
    final store = _store;
    if (store is! SupabaseDataStore) return null;
    final channel = store.client.channel('rt-$collection-${_uuid.v4()}');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: collection,
          callback: (_) async {
            await store.refreshCollection(collection);
            onChange();
          },
        )
        .subscribe();
    return channel;
  }

  /// Cancela una suscripción Realtime abierta con [watchCollection].
  Future<void> unwatch(Object? channel) async {
    final store = _store;
    if (store is SupabaseDataStore && channel is RealtimeChannel) {
      await store.client.removeChannel(channel);
    }
  }

  /// Deshace el vínculo de un pago con su cobro (el cobro vuelve a pendiente).
  /// No revierte movimientos de inventario ya materializados.
  Future<void> unlinkPointPayment(String paymentId) async {
    final payment = _store
        .getAll(Collections.pointPayments)
        .map(PointPayment.fromJson)
        .firstWhere((p) => p.id == paymentId);
    await _store.updateRow(Collections.pointPayments, paymentId, {
      'charge_id': null,
      'linked_by': null,
      'linked_at': null,
      'updated_at': DateTime.now().toIso8601String(),
    });
    if (payment.chargeId != null) {
      await _store.updateRow(Collections.charges, payment.chargeId!, {
        'status': 'pendiente',
        'payment_method': null,
        'paid_at': null,
        'payment_provider': null,
        'mp_payment_id': null,
        'mp_status': null,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }

  /// Componentes (método/producto) del plan de tratamiento MÁS RECIENTE del
  /// paciente. Sirve para sugerir qué insumos descontar (vía los mapeos Fase 2).
  List<TreatmentComponentRecord> latestTreatmentComponentsForPatient(String patientId) {
    final consultIds =
        listConsultationsForPatient(patientId).map((c) => c.id).toSet();
    if (consultIds.isEmpty) return const [];
    final plans = _store
        .getAll(Collections.treatmentPlans)
        .where((p) => consultIds.contains(p['consultation_id']))
        .toList()
      ..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    if (plans.isEmpty) return const [];
    final planId = plans.first['id'];
    return _store
        .getAll(Collections.treatmentComponents)
        .where((c) => c['treatment_plan_id'] == planId)
        .map(TreatmentComponentRecord.fromJson)
        .toList();
  }

  /// Citas manuales del centro (admin) o de un Kurador (clínico). El aislamiento
  /// real lo aplica la RLS; el filtro aquí acota la vista.
  List<ManualAppointment> listManualAppointments({String? organizationId, String? staffId}) =>
      _store
          .getAll(Collections.manualAppointments)
          .map(ManualAppointment.fromJson)
          .where((a) =>
              (organizationId == null || a.organizationId == organizationId) &&
              (staffId == null || a.staffId == staffId))
          .toList();

  Future<ManualAppointment> createManualAppointment({
    required String organizationId,
    required DateTime datetime,
    String? staffId,
    String? patientId,
    String? title,
    DateTime? endTime,
    String? notes,
    String? address,
    String? contactName,
    String? contactPhone,
    String? photoPath,
    String? createdByProfileId,
  }) async {
    final now = DateTime.now().toIso8601String();
    final data = {
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'staff_id': staffId,
      'patient_id': patientId,
      'title': title,
      'datetime': datetime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'notes': notes,
      'address': address,
      'contact_name': contactName,
      'contact_phone': contactPhone,
      'photo_path': photoPath,
      'status': 'scheduled',
      'created_by': createdByProfileId,
      'created_at': now,
      'updated_at': now,
    };
    final saved = await _store.insertRow(Collections.manualAppointments, data);
    return ManualAppointment.fromJson(saved);
  }

  Future<ManualAppointment> updateManualAppointment(
    String id, {
    String? staffId,
    bool clearStaff = false,
    String? patientId,
    bool clearPatient = false,
    String? title,
    DateTime? datetime,
    DateTime? endTime,
    bool clearEndTime = false,
    String? notes,
    String? status,
    String? address,
    String? contactName,
    String? contactPhone,
    String? photoPath,
  }) async {
    final patch = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (clearStaff) {
      patch['staff_id'] = null;
    } else if (staffId != null) {
      patch['staff_id'] = staffId;
    }
    if (clearPatient) {
      patch['patient_id'] = null;
    } else if (patientId != null) {
      patch['patient_id'] = patientId;
    }
    if (title != null) patch['title'] = title;
    if (datetime != null) patch['datetime'] = datetime.toIso8601String();
    if (clearEndTime) {
      patch['end_time'] = null;
    } else if (endTime != null) {
      patch['end_time'] = endTime.toIso8601String();
    }
    if (notes != null) patch['notes'] = notes;
    if (status != null) patch['status'] = status;
    if (address != null) patch['address'] = address;
    if (contactName != null) patch['contact_name'] = contactName;
    if (contactPhone != null) patch['contact_phone'] = contactPhone;
    if (photoPath != null) patch['photo_path'] = photoPath;
    final saved = await _store.updateRow(Collections.manualAppointments, id, patch);
    return ManualAppointment.fromJson(saved);
  }

  /// Refleja el contacto de una cita manual en el expediente del paciente
  /// (cuidador), SOLO si esos campos están vacíos (no pisa datos del clínico).
  /// Opcionalmente agrega una nota (p.ej. domicilio de tratamiento) a
  /// background_notes. Usado por el alta manual cuando el paciente ya existía.
  Future<void> updatePatientContactIfEmpty(
    String patientId, {
    String? caregiverName,
    String? caregiverPhone,
    String? appendBackgroundNote,
  }) async {
    final rows =
        _store.getAll(Collections.patients).where((r) => r['id'] == patientId).toList();
    if (rows.isEmpty) return;
    final r = rows.first;
    final patch = <String, dynamic>{};
    if (((r['caregiver_name'] as String?) ?? '').isEmpty &&
        (caregiverName ?? '').isNotEmpty) {
      patch['caregiver_name'] = caregiverName;
      patch['has_identified_caregiver'] = true;
    }
    if (((r['caregiver_phone'] as String?) ?? '').isEmpty &&
        (caregiverPhone ?? '').isNotEmpty) {
      patch['caregiver_phone'] = caregiverPhone;
      patch['has_identified_caregiver'] = true;
    }
    if ((appendBackgroundNote ?? '').isNotEmpty) {
      final existing = ((r['background_notes'] as String?) ?? '').trim();
      patch['background_notes'] =
          existing.isEmpty ? appendBackgroundNote : '$existing\n$appendBackgroundNote';
    }
    if (patch.isNotEmpty) {
      await _store.updateRow(Collections.patients, patientId, patch);
    }
  }

  Future<void> cancelManualAppointment(String id) async {
    await _store.updateRow(Collections.manualAppointments, id,
        {'status': 'canceled', 'updated_at': DateTime.now().toIso8601String()});
  }

  // ---------------- Acuity por centro (Fase 2, 0022) ----------------
  // Solo en modo Supabase; las credenciales se guardan/consultan por RPC
  // (nunca se lee la API key completa desde el cliente).

  Future<void> setOrgAcuityCredentials(String orgId, String userId, String apiKey) async {
    final store = _store;
    if (store is! SupabaseDataStore) {
      throw Exception('La configuración de Acuity solo está disponible con Supabase.');
    }
    await store.callRpc('set_org_acuity_credentials', {
      'p_org': orgId,
      'p_user_id': userId,
      'p_api_key': apiKey,
    });
  }

  Future<AcuityConfigStatus?> getOrgAcuityStatus(String orgId) async {
    final store = _store;
    if (store is! SupabaseDataStore) return null;
    final rows = await store.callRpcResult('get_org_acuity_status', {'p_org': orgId});
    if (rows is List && rows.isNotEmpty) {
      final r = (rows.first as Map).cast<String, dynamic>();
      return AcuityConfigStatus(
        userId: r['user_id']?.toString() ?? '',
        keyLast4: r['key_last4']?.toString() ?? '',
        webhooksRegistered: r['webhooks_registered'] == true,
      );
    }
    return null;
  }

  Future<void> markAcuityWebhooks(String orgId, bool registered) async {
    final store = _store;
    if (store is! SupabaseDataStore) return;
    await store.callRpc('mark_org_acuity_webhooks', {
      'p_org': orgId,
      'p_registered': registered,
    });
  }

  // ---------------- Sitios ----------------

  /// Lista los sitios. [organizationId] es un filtro OPCIONAL usado
  /// exclusivamente por el area de Plataforma (master): para un admin
  /// normal, se omite (null) y la lista completa ya viene acotada a su
  /// propia organizacion por RLS (Supabase) o porque hoy solo existe 1
  /// organizacion en el seed local de demo. Un master, en cambio, ve en
  /// cache TODAS las organizaciones (RLS de 0012_master_role.sql) y
  /// necesita este filtro para acotar la vista al centro que eligio en
  /// el selector.
  List<Site> listSites({String? organizationId}) => _store
      .getAll(Collections.sites)
      .map(Site.fromJson)
      .where((s) => organizationId == null || s.organizationId == organizationId)
      .toList();

  /// Crea un sitio nuevo del centro. `site.organizationId` es obligatorio en
  /// la practica (columna not null en Supabase, ver 0011_organizations.sql):
  /// el llamador (pantalla de Administracion) debe construir el [Site] con
  /// `organizationId: session.user!.organizationId`.
  Future<Site> createSite(Site site) async {
    final data = site.toJson();
    if ((data['id'] as String?)?.isEmpty ?? true) data['id'] = _uuid.v4();
    final saved = await _store.insertRow(Collections.sites, data);
    return Site.fromJson(saved);
  }

  /// Edita un sitio existente (nombre, tipo, direccion). Solo se envian al
  /// backend los campos que el llamador especifica explicitamente.
  Future<Site> updateSite(
    String id, {
    String? name,
    String? kind,
    String? address,
    bool clearAddress = false,
  }) async {
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name;
    if (kind != null) patch['kind'] = kind;
    if (clearAddress) {
      patch['address'] = null;
    } else if (address != null) {
      patch['address'] = address;
    }
    final saved = await _store.updateRow(Collections.sites, id, patch);
    return Site.fromJson(saved);
  }

  Future<void> setSiteActive(String siteId, bool active) async {
    await _store.updateRow(Collections.sites, siteId, {'is_active': active});
  }

  // ---------------- Personal sanitario ----------------

  /// [organizationId] es un filtro OPCIONAL, mismo proposito que en
  /// [listSites]: solo se pasa desde el area de Plataforma (master).
  List<StaffMember> listStaff({String? organizationId}) => _store
      .getAll(Collections.staff)
      .map(StaffMember.fromJson)
      .where((s) => organizationId == null || s.organizationId == organizationId)
      .toList();

  /// Busca un miembro del personal por id. Devuelve `null` si no existe.
  /// Util para prefills (p.ej. cedula profesional en la nota de
  /// seguimiento) sin tener que exponer una consulta directa a la tabla.
  StaffMember? getStaff(String staffId) {
    for (final json in _store.getAll(Collections.staff)) {
      if (json['id'] == staffId) return StaffMember.fromJson(json);
    }
    return null;
  }

  /// Crea un registro de personal sanitario. [organizationId] es requerido
  /// (staff.organization_id not null, ver 0011_organizations.sql): el
  /// llamador siempre debe pasar `session.user!.organizationId` (el centro
  /// del admin que da de alta al personal), nunca el del profile vinculado
  /// (que puede ser null si es alta administrativa sin cuenta).
  Future<StaffMember> createStaff({
    required String fullName,
    required String roleTitle,
    required String? organizationId,
    String? primarySiteId,
    String? profileId,
    String? cedulaProfesional,
    String? especialidad,
  }) async {
    final existing = _store.getAll(Collections.staff);
    final year = DateTime.now().year;
    final countThisYear = existing
        .where((s) => (s['folio'] as String).startsWith('K$year'))
        .length;
    final folio = 'K$year-${(countThisYear + 1).toString().padLeft(4, '0')}';

    final data = {
      'id': _uuid.v4(),
      'profile_id': profileId,
      'folio': folio,
      'full_name': fullName,
      'role_title': roleTitle,
      'primary_site_id': primarySiteId,
      'is_active': true,
      'created_at': DateTime.now().toIso8601String(),
      'cedula_profesional': cedulaProfesional,
      'especialidad': especialidad,
      'organization_id': organizationId,
    };
    final saved = await _store.insertRow(Collections.staff, data);
    return StaffMember.fromJson(saved);
  }

  Future<void> setStaffActive(String staffId, bool active) async {
    await _store.updateRow(Collections.staff, staffId, {'is_active': active});
  }

  /// Edita un registro de personal existente (nombre, cargo, sitio
  /// principal y/o vinculo a un profile_id). Solo se envian al backend los
  /// campos que el llamador especifica explicitamente; para desvincular un
  /// profile_id ya asignado, usar [clearProfileId].
  Future<StaffMember> updateStaff(
    String staffId, {
    String? fullName,
    String? roleTitle,
    String? primarySiteId,
    bool clearPrimarySiteId = false,
    String? profileId,
    bool clearProfileId = false,
    String? cedulaProfesional,
    bool clearCedulaProfesional = false,
    String? especialidad,
    bool clearEspecialidad = false,
  }) async {
    final patch = <String, dynamic>{};
    if (fullName != null) patch['full_name'] = fullName;
    if (roleTitle != null) patch['role_title'] = roleTitle;
    if (clearEspecialidad) {
      patch['especialidad'] = null;
    } else if (especialidad != null) {
      patch['especialidad'] = especialidad;
    }
    if (clearPrimarySiteId) {
      patch['primary_site_id'] = null;
    } else if (primarySiteId != null) {
      patch['primary_site_id'] = primarySiteId;
    }
    if (clearProfileId) {
      patch['profile_id'] = null;
    } else if (profileId != null) {
      patch['profile_id'] = profileId;
    }
    if (clearCedulaProfesional) {
      patch['cedula_profesional'] = null;
    } else if (cedulaProfesional != null) {
      patch['cedula_profesional'] = cedulaProfesional;
    }
    final saved = await _store.updateRow(Collections.staff, staffId, patch);
    return StaffMember.fromJson(saved);
  }

  /// Perfiles (`profiles`) que aun NO tienen una fila en `staff` vinculada
  /// via profile_id — candidatos para dar de alta como personal sanitario
  /// operativo desde el panel de Administración, sin tocar SQL a mano.
  /// Incluye perfiles admin (un admin puede necesitar staff_id propio para
  /// poder crear consultas, ver aclaración del modelo de datos).
  List<AppUser> listProfilesWithoutStaffLink() {
    final linkedProfileIds = _store
        .getAll(Collections.staff)
        .map((s) => s['profile_id'] as String?)
        .whereType<String>()
        .toSet();
    return listUsers().where((u) => !linkedProfileIds.contains(u.id)).toList();
  }

  /// Fix admin-clinico (licencia individual, ajuste obligatorio #3): un
  /// admin que NUNCA recibio una fila de `staff` (p.ej. el admin del seed
  /// de demo, o un admin creado antes de esta funcion / sin pasar por
  /// create_organization_with_admin en Supabase) no puede crear una
  /// consulta porque consultations.staff_id es NOT NULL. En vez de
  /// bloquear el flujo clinico (como hacian antes ConsultationHubScreen y
  /// FollowUpCaptureScreen con `if (staffId == null) return`), se
  /// aprovisiona SU staff de forma perezosa (lazy) la primera vez que se
  /// necesita: si ya existe una fila de staff vinculada a este profile_id,
  /// se devuelve su id; si no, se crea una (folio '' -- igual que hace el
  /// RPC create_organization_with_admin en Postgres, ver
  /// 0011_organizations.sql secc. 5) y se devuelve el id nuevo.
  ///
  /// Se usa desde SessionController (refreshUser/login/restore) para que
  /// `session.user.staffId` quede resuelto ANTES de que la UI lo lea, sin
  /// que cada pantalla clinica tenga que conocer este detalle.
  Future<String> ensureAdminStaffId(AppUser adminUser) async {
    final existing = _store
        .getAll(Collections.staff)
        .where((s) => s['profile_id'] == adminUser.id);
    if (existing.isNotEmpty) return existing.first['id'] as String;

    final created = await createStaff(
      fullName: adminUser.fullName,
      roleTitle: 'Administrador',
      organizationId: adminUser.organizationId,
      profileId: adminUser.id,
    );
    return created.id;
  }

  // ---------------- Catalogo de conceptos de nota de seguimiento ----------------
  // (note_option_catalog, ver 0010_note_option_catalog.sql). Configurable
  // por el centro (admin) desde el panel de Configuracion; el personal
  // clinico solo lee/selecciona (RLS: SELECT para autenticados, INSERT/
  // UPDATE/DELETE solo admin via is_admin()). No es tabla auditada por el
  // trigger (catalogo administrativo, no dato clinico de paciente).

  /// Conceptos activos para un campo dado, en el orden en que fueron
  /// creados (los precargados por la migracion 0010 primero).
  ///
  /// Usa `fromJsonOrNull` (no `fromJson`) y descarta silenciosamente
  /// cualquier fila malformada (id/label nulo o de tipo inesperado): este
  /// metodo se invoca sin try/catch desde codigo de build() en varias
  /// pantallas, y una unica fila corrupta NO debe tumbar toda la lista ni
  /// la pantalla que la muestra (ver bug "pantalla en blanco al crear
  /// concepto de catalogo", 2026-07-15).
  /// [organizationId] es un filtro OPCIONAL, mismo proposito que en
  /// [listSites]: solo se pasa desde el area de Plataforma (master).
  List<NoteOptionCatalogItem> listNoteOptions(NoteOptionField field, {String? organizationId}) {
    return _store
        .getAll(Collections.noteOptionCatalog)
        .map(NoteOptionCatalogItem.fromJsonOrNull)
        .whereType<NoteOptionCatalogItem>()
        .where((o) =>
            o.field == field &&
            o.isActive &&
            (organizationId == null || o.organizationId == organizationId))
        .toList();
  }

  /// Todos los conceptos (activos e inactivos) de un campo, para la
  /// pantalla de Configuracion del admin, donde tambien se pueden
  /// reactivar conceptos previamente desactivados.
  ///
  /// Ver nota de `listNoteOptions()` sobre `fromJsonOrNull`: este metodo en
  /// particular es el que `_NoteCatalogTabState.build()` llama sin
  /// try/catch en cada rebuild (incluido el rebuild disparado por
  /// `setState()` tras un alta exitosa en `_addOption()`), por lo que es
  /// el punto exacto donde una fila cacheada malformada causaba la
  /// pantalla en blanco reportada.
  /// [organizationId] es un filtro OPCIONAL, mismo proposito que en
  /// [listSites]: solo se pasa desde el area de Plataforma (master).
  List<NoteOptionCatalogItem> listAllNoteOptions(NoteOptionField field, {String? organizationId}) {
    return _store
        .getAll(Collections.noteOptionCatalog)
        .map(NoteOptionCatalogItem.fromJsonOrNull)
        .whereType<NoteOptionCatalogItem>()
        .where((o) =>
            o.field == field &&
            (organizationId == null || o.organizationId == organizationId))
        .toList();
  }

  /// Agrega un concepto nuevo al catalogo. Uso previsto: (a) pantalla de
  /// Configuracion del admin, y (b) alta "sobre la marcha" cuando quien
  /// captura la nota de seguimiento es admin y escribe algo nuevo en
  /// "Otro" (se le ofrece guardarlo; si es personal clinico, "Otro" se
  /// usa solo como texto de esa nota y este metodo NO se invoca).
  Future<NoteOptionCatalogItem> createNoteOption({
    required NoteOptionField field,
    required String label,
    required String? organizationId,
    String? createdByProfileId,
    KuraTag? kuraTag,
  }) async {
    final data = {
      'id': _uuid.v4(),
      'field': field.dbValue,
      'label': label,
      'is_active': true,
      'created_by': createdByProfileId,
      'organization_id': organizationId,
      'kura_tag': kuraTag?.dbValue,
    };
    final saved = await _store.insertRow(Collections.noteOptionCatalog, data);
    return NoteOptionCatalogItem.fromJson(saved);
  }

  Future<void> setNoteOptionActive(String id, bool active) async {
    await _store.updateRow(Collections.noteOptionCatalog, id, {'is_active': active});
  }

  /// Actualiza SOLO la etiqueta kura_tag de un concepto existente (dropdown
  /// de NoteCatalogTab en Administracion). `null` limpia la etiqueta
  /// ("Sin etiqueta"). No toca ningun otro campo del concepto.
  Future<void> setNoteOptionKuraTag(String id, KuraTag? kuraTag) async {
    await _store.updateRow(Collections.noteOptionCatalog, id, {'kura_tag': kuraTag?.dbValue});
  }

  /// Borra un concepto del catalogo (pantalla de Configuracion). La
  /// politica RLS `note_option_catalog_admin_delete` (migracion 0011)
  /// ya restringe esto a admins de la misma organizacion; aqui solo se
  /// delega el DELETE. No afecta el historial: las notas de seguimiento
  /// ya guardadas persisten el texto del concepto, no una referencia a
  /// esta fila, asi que borrar solo lo quita de las opciones futuras.
  Future<void> deleteNoteOption(String id) async {
    await _store.deleteRow(Collections.noteOptionCatalog, id);
  }

  /// Resultado de una importacion masiva del catalogo desde CSV (pantalla
  /// de Configuracion): cuantos conceptos se agregaron (no existian),
  /// cuantos se actualizaron (existian con `activo` distinto al de la
  /// fila del CSV) y cuantos se omitieron (fila invalida: seccion
  /// desconocida o concepto vacio).
  Future<NoteOptionImportSummary> bulkImportNoteOptions(
    List<NoteOptionImportRow> rows, {
    required String organizationId,
    String? createdByProfileId,
  }) async {
    var added = 0;
    var updated = 0;
    var skipped = 0;
    final errors = <String>[];

    // Todos los conceptos actuales del centro (activos e inactivos), para
    // poder decidir merge (agregar vs actualizar) sin duplicar por
    // (field, label) dentro de esta misma organizacion.
    final existingByFieldLabel = <String, NoteOptionCatalogItem>{};
    for (final field in NoteOptionField.values) {
      for (final o in listAllNoteOptions(field, organizationId: organizationId)) {
        existingByFieldLabel['${field.dbValue}::${o.label.trim().toLowerCase()}'] = o;
      }
    }

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowNum = i + 2; // +1 encabezado, +1 base-1 para el usuario
      final field = NoteOptionFieldDb.fromCsvSeccion(row.seccion);
      final label = row.concepto.trim();
      if (field == null) {
        skipped++;
        errors.add('Fila $rowNum: sección "${row.seccion}" no reconocida (omitida).');
        continue;
      }
      if (label.isEmpty) {
        skipped++;
        errors.add('Fila $rowNum: concepto vacío (omitida).');
        continue;
      }

      final key = '${field.dbValue}::${label.toLowerCase()}';
      final existing = existingByFieldLabel[key];
      if (existing == null) {
        final created = await createNoteOption(
          field: field,
          label: label,
          organizationId: organizationId,
          createdByProfileId: createdByProfileId,
        );
        existingByFieldLabel[key] = created;
        added++;
      } else if (existing.isActive != row.activo) {
        await setNoteOptionActive(existing.id, row.activo);
        existingByFieldLabel[key] = NoteOptionCatalogItem(
          id: existing.id,
          field: existing.field,
          label: existing.label,
          isActive: row.activo,
          createdBy: existing.createdBy,
          organizationId: existing.organizationId,
          kuraTag: existing.kuraTag,
        );
        updated++;
      }
      // Si existe y `activo` ya coincide: no-op (no cuenta como agregado
      // ni actualizado; se refleja en skipped=false pero tampoco se
      // reporta como error, simplemente no incrementa ningun contador
      // "de cambio" -- el resumen final solo informa added/updated/skipped
      // donde skipped es exclusivamente filas invalidas).
    }

    return NoteOptionImportSummary(
      added: added,
      updated: updated,
      skipped: skipped,
      errors: errors,
    );
  }

  /// Catalogo base curado (misma precarga que la migracion
  /// 0010_note_option_catalog.sql y el espejo de DemoSeed) para las 4
  /// secciones de la nota de seguimiento. Se usa como "punto de partida"
  /// para un centro nuevo que aun no configuro nada (pantalla vacia, ver
  /// captura reportada: un centro creado desde Plataforma por el master
  /// no arrastra ningun concepto -- por diseno, para no imponerle
  /// contenido sin pedirselo -- pero de ahi la necesidad de este boton).
  /// Tercer elemento (kuraTag): etiqueta de mapeo al motor Protocolo Kura+
  /// (ver 0013_note_option_catalog_kura_tag.sql) sembrada por defecto para
  /// los conceptos base curados cuya correspondencia con un metodo del
  /// motor es clara y no ambigua. Los conceptos sin correspondencia clara
  /// (p.ej. "Interconsulta", evolucion, la mayoria de materiales sueltos)
  /// quedan en null ("Sin etiqueta") a proposito -- etiquetar de mas seria
  /// forzar auto-selecciones que no reflejan realmente ese metodo.
  static const List<(NoteOptionField, String, KuraTag?)> defaultNoteOptionCatalog = [
    (NoteOptionField.careType, 'Curación ambulatoria', null),
    (NoteOptionField.careType, 'Visita domiciliaria', null),
    (NoteOptionField.careType, 'Curación en hospitalización', null),
    (NoteOptionField.careType, 'Interconsulta', null),
    (NoteOptionField.careType, 'Desbridamiento programado', KuraTag.desbridamiento),
    (NoteOptionField.procedureDesc, 'Higiene de manos', null),
    (NoteOptionField.procedureDesc, 'Colocación de guantes', null),
    (NoteOptionField.procedureDesc, 'Limpieza con solución salina y cambio de apósito', KuraTag.limpieza),
    (NoteOptionField.procedureDesc, 'Desbridamiento cortante parcial', KuraTag.desbridamiento),
    (NoteOptionField.procedureDesc, 'Desbridamiento autolítico/enzimático', KuraTag.desbridamiento),
    (NoteOptionField.procedureDesc, 'Toma de medidas y fotografía de control', null),
    (NoteOptionField.procedureDesc, 'Aplicación de terapia compresiva', KuraTag.compresion),
    (NoteOptionField.procedureDesc, 'Educación al paciente/cuidador', KuraTag.educacion),
    (NoteOptionField.materialsUsed, 'Solución salina 0.9%', KuraTag.limpieza),
    (NoteOptionField.materialsUsed, 'Yodopovidona 10%', KuraTag.antimicrobiano),
    (NoteOptionField.materialsUsed, 'Apósito de espuma (foam)', KuraTag.aposito),
    (NoteOptionField.materialsUsed, 'Apósito de alginato', KuraTag.aposito),
    (NoteOptionField.materialsUsed, 'Apósito hidrocoloide', KuraTag.aposito),
    (NoteOptionField.materialsUsed, 'Gasa estéril', KuraTag.aposito),
    (NoteOptionField.materialsUsed, 'Vendaje de compresión', KuraTag.compresion),
    (NoteOptionField.evolution, 'Favorable, con reducción de área', null),
    (NoteOptionField.evolution, 'Estable, sin cambios significativos', null),
    (NoteOptionField.evolution, 'Sin avance esperado para la semana de tratamiento', null),
    (NoteOptionField.evolution, 'Signos de infección local', null),
    (NoteOptionField.evolution, 'Mejoría del tejido de granulación', null),
  ];

  /// Carga el catalogo base curado para el centro [organizationId]:
  /// solo AGREGA los conceptos que aun no existan en ese centro (mismo
  /// (field, label), comparado sin importar mayusculas/espacios). A
  /// diferencia de [bulkImportNoteOptions] (pensado para CSV, donde el
  /// admin edita explicitamente la columna `activo` y por eso SI
  /// sincroniza el estado activo/inactivo de las filas existentes), este
  /// metodo NUNCA toca una fila que ya exista -- ni la reactiva ni cambia
  /// su texto -- para no deshacer una desactivacion deliberada del admin
  /// solo porque el texto coincide con el catalogo base. Pensado para el
  /// boton "Cargar catálogo base" de [NoteCatalogTab], util sobre todo
  /// para un centro nuevo (todo vacio, ver createOrganization() que a
  /// proposito no siembra catalogo) que quiere arrancar rapido sin
  /// configurar todo desde cero.
  Future<NoteOptionImportSummary> seedDefaultNoteOptions({
    required String organizationId,
    String? createdByProfileId,
  }) async {
    var added = 0;

    final existingLabelsByField = <NoteOptionField, Set<String>>{};
    for (final field in NoteOptionField.values) {
      existingLabelsByField[field] = listAllNoteOptions(field, organizationId: organizationId)
          .map((o) => o.label.trim().toLowerCase())
          .toSet();
    }

    for (final entry in defaultNoteOptionCatalog) {
      final field = entry.$1;
      final label = entry.$2;
      final kuraTag = entry.$3;
      final existingLabels = existingLabelsByField[field]!;
      if (existingLabels.contains(label.trim().toLowerCase())) continue;

      await createNoteOption(
        field: field,
        label: label,
        organizationId: organizationId,
        createdByProfileId: createdByProfileId,
        kuraTag: kuraTag,
      );
      existingLabels.add(label.trim().toLowerCase());
      added++;
    }

    return NoteOptionImportSummary(added: added, updated: 0, skipped: 0, errors: const []);
  }

  List<Patient> listPatientsForStaff(String staffId) {
    final assignments = _store
        .getAll(Collections.staffPatientAssignments)
        .where((a) => a['staff_id'] == staffId)
        .map((a) => a['patient_id'] as String)
        .toSet();
    return listAllPatients().where((p) => assignments.contains(p.id)).toList();
  }

  // ---------------- Pacientes ----------------

  List<Patient> listAllPatients() =>
      _store.getAll(Collections.patients).map(Patient.fromJson).toList();

  Patient? getPatient(String id) {
    final match = _store.getAll(Collections.patients).where((p) => p['id'] == id);
    return match.isEmpty ? null : Patient.fromJson(match.first);
  }

  /// Crea un expediente de paciente. [organizationId] es requerido
  /// (patients.organization_id not null, ver 0011_organizations.sql --
  /// aislamiento critico de pacientes entre centros): el llamador siempre
  /// debe pasar `session.user!.organizationId`.
  Future<Patient> createPatient({
    required String fullName,
    required String? organizationId,
    DateTime? birthDate,
    String? sex,
    String? primarySiteId,
    String? mobility,
    bool hasIdentifiedCaregiver = false,
    String? caregiverName,
    String? caregiverPhone,
    bool fragilePatient = false,
    String? backgroundNotes,
    String? activeMedications,
    String? allergies,
    String? email,
    String? mobilePhone,
    String? surgicalHistory,
    String? curp,
    String? address,
    String? occupation,
    String? responsibleName,
    String? responsibleRelationship,
    String? responsiblePhone,
    double? weightKg,
    double? heightCm,
    Set<AntecedenteHeredoFamiliar> familyHistory = const {},
    String? familyHistoryNotes,
    TabaquismoEstado? smoking,
    ConsumoAlcohol? alcohol,
    ActividadFisica? physicalActivity,
    String? apnpNotes,
    String folioPrefix = 'EXP',
  }) async {
    final year = DateTime.now().year;
    final id = _uuid.v4();

    // Siguiente número de folio del año a partir de la cache. En Supabase la
    // cache está acotada por RLS y `folio` es ÚNICO GLOBAL, así que este número
    // puede quedar corto y colisionar (KT-2) → se reintenta con el siguiente.
    int nextFolioNumber() =>
        _store
            .getAll(Collections.patients)
            .where((p) => (p['folio'] as String? ?? '').contains('$year'))
            .length +
        1;

    Map<String, dynamic> buildData(String folio) => {
          'id': id,
          'folio': folio,
          'full_name': fullName,
          'birth_date': birthDate?.toIso8601String().substring(0, 10),
          'sex': sex,
          'primary_site_id': primarySiteId,
          'mobility': mobility,
          'has_identified_caregiver': hasIdentifiedCaregiver,
          'caregiver_name': caregiverName,
          'caregiver_phone': caregiverPhone,
          'fragile_patient': fragilePatient,
          'background_notes': backgroundNotes,
          'active_medications': activeMedications,
          'allergies': allergies,
          'ekare_external_id': null,
          'email': email,
          'mobile_phone': mobilePhone,
          'surgical_history': surgicalHistory,
          'curp': curp,
          'address': address,
          'occupation': occupation,
          'responsible_name': responsibleName,
          'responsible_relationship': responsibleRelationship,
          'responsible_phone': responsiblePhone,
          'weight_kg': weightKg,
          'height_cm': heightCm,
          'family_history': familyHistory.map((e) => e.dbValue).toList(),
          'family_history_notes': familyHistoryNotes,
          'smoking': smoking?.dbValue,
          'alcohol': alcohol?.dbValue,
          'physical_activity': physicalActivity?.dbValue,
          'apnp_notes': apnpNotes,
          'is_active': true,
          'created_at': DateTime.now().toIso8601String(),
          'organization_id': organizationId,
        };

    String folioFor(int n) =>
        '$folioPrefix$year-${n.toString().padLeft(4, '0')}';

    // Demo (LocalStore): sin índice único → un solo intento.
    final store = _store;
    if (store is! SupabaseDataStore) {
      final saved = await _store
          .insertRow(Collections.patients, buildData(folioFor(nextFolioNumber())));
      return Patient.fromJson(saved);
    }

    // Prod: reintento ante choque de folio único (23505) hasta hallar uno libre.
    var n = nextFolioNumber();
    Object? lastErr;
    for (var attempt = 0; attempt < 30; attempt++) {
      try {
        final saved =
            await store.insertRow(Collections.patients, buildData(folioFor(n)));
        return Patient.fromJson(saved);
      } catch (e) {
        lastErr = e;
        final s = e.toString().toLowerCase();
        if (s.contains('23505') ||
            s.contains('duplicate') ||
            s.contains('unique')) {
          n++; // folio ocupado (fuera del alcance de la cache): prueba el siguiente
          continue;
        }
        rethrow;
      }
    }
    throw Exception(
        'No se pudo generar un folio único para el paciente. $lastErr');
  }

  /// Actualiza los datos del expediente de un paciente EXISTENTE (edición /
  /// completar expediente). Pensado sobre todo para los pacientes creados
  /// automáticamente desde Acuity, que llegan solo con el nombre (y a veces el
  /// email): el personal clínico los abre y completa identificación,
  /// antecedentes, cuidador, etc.
  ///
  /// NO toca folio, organización, acuity_email ni created_at (identidad/origen
  /// del registro). Cada cambio queda auditado por el trigger AFTER UPDATE de
  /// Postgres (audit_trigger_fn, 0002) — la bitácora no se escribe desde el
  /// cliente. La RLS (patients_update, 0011) exige ser admin de la organización
  /// o el clínico asignado al paciente.
  Future<Patient> updatePatient({
    required String patientId,
    required String fullName,
    DateTime? birthDate,
    String? sex,
    String? primarySiteId,
    String? mobility,
    bool hasIdentifiedCaregiver = false,
    String? caregiverName,
    String? caregiverPhone,
    bool fragilePatient = false,
    String? backgroundNotes,
    String? activeMedications,
    String? allergies,
    String? email,
    String? mobilePhone,
    String? surgicalHistory,
    String? curp,
    String? address,
    String? occupation,
    String? responsibleName,
    String? responsibleRelationship,
    String? responsiblePhone,
    double? weightKg,
    double? heightCm,
    Set<AntecedenteHeredoFamiliar> familyHistory = const {},
    String? familyHistoryNotes,
    TabaquismoEstado? smoking,
    ConsumoAlcohol? alcohol,
    ActividadFisica? physicalActivity,
    String? apnpNotes,
  }) async {
    final patch = {
      'full_name': fullName,
      'birth_date': birthDate?.toIso8601String().substring(0, 10),
      'sex': sex,
      'primary_site_id': primarySiteId,
      'mobility': mobility,
      'has_identified_caregiver': hasIdentifiedCaregiver,
      'caregiver_name': caregiverName,
      'caregiver_phone': caregiverPhone,
      'fragile_patient': fragilePatient,
      'background_notes': backgroundNotes,
      'active_medications': activeMedications,
      'allergies': allergies,
      'email': email,
      'mobile_phone': mobilePhone,
      'surgical_history': surgicalHistory,
      'curp': curp,
      'address': address,
      'occupation': occupation,
      'responsible_name': responsibleName,
      'responsible_relationship': responsibleRelationship,
      'responsible_phone': responsiblePhone,
      'weight_kg': weightKg,
      'height_cm': heightCm,
      'family_history': familyHistory.map((e) => e.dbValue).toList(),
      'family_history_notes': familyHistoryNotes,
      'smoking': smoking?.dbValue,
      'alcohol': alcohol?.dbValue,
      'physical_activity': physicalActivity?.dbValue,
      'apnp_notes': apnpNotes,
    };
    final saved =
        await _store.updateRow(Collections.patients, patientId, patch);
    return Patient.fromJson(saved);
  }

  Future<void> assignPatientToStaff(String patientId, String staffId) async {
    final all = _store.getAll(Collections.staffPatientAssignments);
    final exists = all.any((a) => a['patient_id'] == patientId && a['staff_id'] == staffId);
    if (!exists) {
      await _store.insertRow(Collections.staffPatientAssignments, {
        'staff_id': staffId,
        'patient_id': patientId,
      });
    }
  }

  List<PatientComorbidity> listComorbidities(String patientId) {
    // Dedup por código (KT-5): si hay duplicados previos, muestra solo el más
    // reciente por código (red de seguridad además del fix en setComorbidity).
    final byCode = <Comorbilidad, PatientComorbidity>{};
    for (final c in _store
        .getAll(Collections.patientComorbidities)
        .where((c) => c['patient_id'] == patientId)
        .map(PatientComorbidity.fromJson)) {
      final prev = byCode[c.code];
      final cAt = c.notedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final pAt = prev?.notedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (prev == null || cAt.isAfter(pAt)) byCode[c.code] = c;
    }
    return byCode.values.toList();
  }

  // ---------------- Laboratorios del paciente (0070) ------------------------

  /// Laboratorios del paciente, del más reciente al más antiguo.
  List<PatientLab> listPatientLabs(String patientId) => _store
      .getAll(Collections.patientLabs)
      .map(PatientLab.fromJson)
      .where((l) => l.patientId == patientId)
      .toList()
    ..sort((a, b) => b.takenAt.compareTo(a.takenAt));

  /// Laboratorio más reciente del paciente (el que usa el motor), o null.
  PatientLab? latestPatientLab(String patientId) {
    final list = listPatientLabs(patientId);
    return list.isEmpty ? null : list.first;
  }

  Future<PatientLab> addPatientLab({
    required String organizationId,
    required String patientId,
    required DateTime takenAt,
    double? glucoseMgDl,
    double? hba1cPct,
    double? albuminGdl,
    double? hemoglobinGdl,
    double? o2SaturationPct,
    double? prealbuminMgDl,
    double? totalProteinGdl,
    double? crpMgL,
    double? ptSeconds,
    double? hematocritPct,
    double? plateletsUl,
    double? pttSeconds,
    String? notes,
    String? createdBy,
  }) async {
    final saved = await _store.insertRow(Collections.patientLabs, {
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'patient_id': patientId,
      'taken_at': takenAt.toIso8601String().substring(0, 10),
      'glucose_mg_dl': glucoseMgDl,
      'hba1c_pct': hba1cPct,
      'albumin_g_dl': albuminGdl,
      'hemoglobin_g_dl': hemoglobinGdl,
      'o2_saturation_pct': o2SaturationPct,
      'prealbumin_mg_dl': prealbuminMgDl,
      'total_protein_g_dl': totalProteinGdl,
      'crp_mg_l': crpMgL,
      'pt_seconds': ptSeconds,
      'hematocrit_pct': hematocritPct,
      'platelets_ul': plateletsUl,
      'ptt_seconds': pttSeconds,
      'notes': notes,
      'created_by': createdBy,
      'created_at': DateTime.now().toIso8601String(),
    });
    return PatientLab.fromJson(saved);
  }

  Future<void> deletePatientLab(String id) async {
    await _store.deleteRow(Collections.patientLabs, id);
  }

  Future<void> upsertComorbidity(PatientComorbidity comorbidity) async {
    await _store.upsertRow(Collections.patientComorbidities, comorbidity.toJson());
  }

  /// Registra o actualiza el estado de una comorbilidad (APP) de un paciente
  /// (Fase 1, NOM-004). Una fila por (patient_id, code): si ya existe se
  /// actualiza su estado, fechándolo (noted_at) y atribuyéndolo al profesional
  /// (noted_by); si no, se inserta. El historial de cambios queda en audit_log
  /// (trigger 0030). `staffId` lo pasa la pantalla desde la sesión.
  Future<PatientComorbidity> setComorbidity({
    required String patientId,
    required Comorbilidad code,
    required ComorbilidadEstado status,
    required String? staffId,
  }) async {
    final pc = PatientComorbidity(
      id: _uuid.v4(),
      patientId: patientId,
      code: code,
      status: status,
      notedAt: DateTime.now(),
      notedBy: staffId,
    );
    final json = pc.toJson();
    // KT-5: confirma contra el servidor antes de decidir insert/update (la cache
    // puede estar incompleta por RLS y provocar inserts duplicados).
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.refreshCollection(Collections.patientComorbidities);
    }
    final existing = _store
        .getAll(Collections.patientComorbidities)
        .where((c) => c['patient_id'] == patientId && c['code'] == json['code'])
        .toList();
    if (existing.isNotEmpty) {
      final saved = await _store.updateRow(
        Collections.patientComorbidities,
        existing.first['id'] as String,
        {
          'status': json['status'],
          'noted_at': json['noted_at'],
          'noted_by': json['noted_by'],
        },
      );
      // Limpia duplicados previos del mismo (paciente, código), si los hubiera.
      for (final dup in existing.skip(1)) {
        await _store.deleteRow(
            Collections.patientComorbidities, dup['id'] as String);
      }
      return PatientComorbidity.fromJson(saved);
    }
    final saved =
        await _store.insertRow(Collections.patientComorbidities, json);
    return PatientComorbidity.fromJson(saved);
  }

  // ---------------- Diagnósticos CIE-10 (NOM-004, expediente) ----------------
  // Alcance DOCUMENTAL: no alimentan el motor Kura+ (eso vive en las
  // comorbilidades de arriba). Ver 0034_patient_diagnoses.sql y
  // lib/engine/cie10_catalog.dart (catálogo empaquetado como asset).

  List<PatientDiagnosis> listDiagnoses(String patientId) => _store
      .getAll(Collections.patientDiagnoses)
      .where((d) => d['patient_id'] == patientId)
      .map(PatientDiagnosis.fromJson)
      .toList()
    ..sort((a, b) {
      // Principal primero; luego por relación (causa→herida) y código.
      if (a.isPrimary != b.isPrimary) return a.isPrimary ? -1 : 1;
      final r = a.relation.index.compareTo(b.relation.index);
      return r != 0 ? r : a.code.compareTo(b.code);
    });

  /// Agrega un diagnóstico CIE-10 al expediente. Toma el `code` del catálogo y
  /// guarda un SNAPSHOT del nombre. `staffId`/`organizationId` los pasa la
  /// pantalla desde la sesión. Idempotente por (patient_id, code): si el código
  /// ya existe se reactiva/actualiza (re-fechado y re-atribuido).
  Future<PatientDiagnosis> addDiagnosis({
    required String patientId,
    required Cie10Code code,
    required DiagnosisRelation relation,
    String? woundId,
    bool isPrimary = false,
    String? notes,
    required String? organizationId,
    required String? staffId,
  }) async {
    final existing = _store
        .getAll(Collections.patientDiagnoses)
        .where((d) => d['patient_id'] == patientId && d['code'] == code.code)
        .toList();
    if (existing.isNotEmpty) {
      final saved = await _store.updateRow(
        Collections.patientDiagnoses,
        existing.first['id'] as String,
        {
          'name': code.name,
          'relation': relation.dbValue,
          'wound_id': woundId,
          'notes': notes,
          'status': DiagnosisStatus.activo.dbValue,
          'noted_at': DateTime.now().toIso8601String(),
          'noted_by': staffId,
        },
      );
      final reactivated = PatientDiagnosis.fromJson(saved);
      if (isPrimary) await setPrimaryDiagnosis(patientId, reactivated.id);
      return reactivated;
    }
    final diag = PatientDiagnosis(
      id: _uuid.v4(),
      organizationId: organizationId,
      patientId: patientId,
      woundId: woundId,
      staffId: staffId,
      code: code.code,
      name: code.name,
      relation: relation,
      isPrimary: false, // el principal se fija abajo para desmarcar el previo
      status: DiagnosisStatus.activo,
      notes: notes,
      notedAt: DateTime.now(),
      notedBy: staffId,
      createdAt: DateTime.now(),
    );
    final saved =
        await _store.insertRow(Collections.patientDiagnoses, diag.toJson());
    final created = PatientDiagnosis.fromJson(saved);
    if (isPrimary) await setPrimaryDiagnosis(patientId, created.id);
    return created;
  }

  /// Marca [diagnosisId] como el diagnóstico principal del paciente y desmarca
  /// cualquier otro (restricción de "un solo principal", uq_..._primary en BD).
  ///
  /// Orden IMPORTANTE: primero se DESMARCA cualquier otro principal y solo
  /// después se marca el objetivo. En el backend Supabase cada updateRow es una
  /// llamada independiente; marcar antes de desmarcar dejaría dos filas con
  /// is_primary=true a la vez y violaría el índice único parcial uq_..._primary.
  Future<void> setPrimaryDiagnosis(String patientId, String diagnosisId) async {
    final all = _store
        .getAll(Collections.patientDiagnoses)
        .where((d) => d['patient_id'] == patientId)
        .toList();
    // 1) Desmarcar los otros principales.
    for (final d in all) {
      if (d['id'] != diagnosisId && (d['is_primary'] as bool? ?? false)) {
        await _store.updateRow(
          Collections.patientDiagnoses,
          d['id'] as String,
          {'is_primary': false},
        );
      }
    }
    // 2) Marcar el objetivo (si no lo estaba ya).
    final target = all.where((d) => d['id'] == diagnosisId);
    if (target.isNotEmpty && !(target.first['is_primary'] as bool? ?? false)) {
      await _store.updateRow(
        Collections.patientDiagnoses,
        diagnosisId,
        {'is_primary': true},
      );
    }
  }

  /// Cambia el estado de un diagnóstico (activo/resuelto/descartado),
  /// re-fechándolo y re-atribuyéndolo. No se borra.
  Future<PatientDiagnosis> setDiagnosisStatus({
    required String diagnosisId,
    required DiagnosisStatus status,
    required String? staffId,
  }) async {
    final saved = await _store.updateRow(
      Collections.patientDiagnoses,
      diagnosisId,
      {
        'status': status.dbValue,
        'noted_at': DateTime.now().toIso8601String(),
        'noted_by': staffId,
      },
    );
    return PatientDiagnosis.fromJson(saved);
  }

  /// Borrado físico (solo admin, según RLS). El flujo clínico normal usa
  /// `setDiagnosisStatus(descartado)`.
  Future<void> deleteDiagnosis(String diagnosisId) async {
    await _store.deleteRow(Collections.patientDiagnoses, diagnosisId);
  }

  // ---------------- Prevención / Riesgo (módulo v1) ----------------
  // Capa DOCUMENTAL/asesor: no altera el motor de tratamiento. Persiste los
  // INSUMOS (internamiento + valoración Braden); las alertas se computan al
  // vuelo con prevention_risk_engine.dart. Ver 0036_prevention_module.sql.

  // -- Internamiento --
  List<PatientAdmission> listAdmissions(String patientId) => _store
      .getAll(Collections.patientAdmissions)
      .where((a) => a['patient_id'] == patientId)
      .map(PatientAdmission.fromJson)
      .toList()
    ..sort((a, b) => b.admittedAt.compareTo(a.admittedAt));

  /// Internamiento ACTIVO del paciente (o null si no está internado).
  // ---------------- Terapia VAC (NPWT, módulo transversal, 0064) ------------

  /// Terapias VAC del centro (o de un paciente), opcionalmente solo activas.
  List<VacTherapy> listVacTherapies({
    String? organizationId,
    String? patientId,
    bool activeOnly = false,
  }) =>
      _store
          .getAll(Collections.vacTherapies)
          .map(VacTherapy.fromJson)
          .where((t) =>
              (organizationId == null || t.organizationId == organizationId) &&
              (patientId == null || t.patientId == patientId) &&
              (!activeOnly || t.isActive))
          .toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  VacTherapy? getVacTherapy(String id) {
    final match =
        _store.getAll(Collections.vacTherapies).where((t) => t['id'] == id);
    return match.isEmpty ? null : VacTherapy.fromJson(match.first);
  }

  /// Terapia VAC activa de un paciente (la más reciente), o null.
  VacTherapy? activeVacTherapy(String patientId) {
    final list = listVacTherapies(patientId: patientId, activeOnly: true);
    return list.isEmpty ? null : list.first;
  }

  /// Crea una terapia VAC y registra el evento de colocación en la bitácora.
  Future<VacTherapy> createVacTherapy({
    required String organizationId,
    required String patientId,
    String? woundId,
    required VacEquipment equipment,
    String? deviceSerial,
    VacMode? mode,
    int? targetPressureMmhg,
    bool instillation = false,
    String? instillSolution,
    int? instillDwellMin,
    VacDressing? dressing,
    int? changeIntervalHours,
    DateTime? placedAt,
    VacLocation? placedLocation,
    String? caregiverInstructions,
    String? notes,
    String? createdBy,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final data = {
      'id': id,
      'organization_id': organizationId,
      'patient_id': patientId,
      'wound_id': woundId,
      'equipment_type': equipment.dbValue,
      'device_serial': deviceSerial,
      'mode': mode?.dbValue,
      'target_pressure_mmhg': targetPressureMmhg,
      'instillation': instillation,
      'instill_solution': instillSolution,
      'instill_dwell_min': instillDwellMin,
      'dressing_type': dressing?.dbValue,
      'change_interval_hours': changeIntervalHours,
      'placed_at': (placedAt ?? now).toIso8601String(),
      'placed_by': createdBy,
      'placed_location': placedLocation?.dbValue,
      'current_location': placedLocation?.dbValue,
      'status': VacTherapyStatus.activa.dbValue,
      'caregiver_instructions': caregiverInstructions,
      'notes': notes,
      'started_at': now.toIso8601String(),
      'created_by': createdBy,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    final saved = await _store.insertRow(Collections.vacTherapies, data);
    await addVacEvent(
      organizationId: organizationId,
      therapyId: id,
      patientId: patientId,
      type: VacEventType.colocacion,
      location: placedLocation,
      byProfile: createdBy,
      note: 'Colocación de terapia (${equipment.label})',
    );
    return VacTherapy.fromJson(saved);
  }

  /// Actualiza campos de una terapia (parámetros, ubicación, estado,
  /// indicaciones). Solo se envían los campos provistos.
  Future<void> updateVacTherapy(
    String therapyId, {
    VacEquipment? equipment,
    String? deviceSerial,
    VacMode? mode,
    int? targetPressureMmhg,
    bool? instillation,
    String? instillSolution,
    int? instillDwellMin,
    VacDressing? dressing,
    int? changeIntervalHours,
    VacLocation? currentLocation,
    VacTherapyStatus? status,
    String? caregiverInstructions,
    String? notes,
    DateTime? endedAt,
  }) async {
    final patch = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (equipment != null) patch['equipment_type'] = equipment.dbValue;
    if (deviceSerial != null) patch['device_serial'] = deviceSerial;
    if (mode != null) patch['mode'] = mode.dbValue;
    if (targetPressureMmhg != null) {
      patch['target_pressure_mmhg'] = targetPressureMmhg;
    }
    if (instillation != null) patch['instillation'] = instillation;
    if (instillSolution != null) patch['instill_solution'] = instillSolution;
    if (instillDwellMin != null) patch['instill_dwell_min'] = instillDwellMin;
    if (dressing != null) patch['dressing_type'] = dressing.dbValue;
    if (changeIntervalHours != null) {
      patch['change_interval_hours'] = changeIntervalHours;
    }
    if (currentLocation != null) {
      patch['current_location'] = currentLocation.dbValue;
    }
    if (status != null) patch['status'] = status.dbValue;
    if (caregiverInstructions != null) {
      patch['caregiver_instructions'] = caregiverInstructions;
    }
    if (notes != null) patch['notes'] = notes;
    if (endedAt != null) patch['ended_at'] = endedAt.toIso8601String();
    await _store.updateRow(Collections.vacTherapies, therapyId, patch);
  }

  /// Bitácora de una terapia (más reciente primero).
  List<VacEvent> listVacEvents(String therapyId) => _store
      .getAll(Collections.vacEvents)
      .map(VacEvent.fromJson)
      .where((e) => e.therapyId == therapyId)
      .toList()
    ..sort((a, b) => b.at.compareTo(a.at));

  /// Agrega un evento a la bitácora de la terapia (append-only).
  Future<void> addVacEvent({
    required String organizationId,
    required String therapyId,
    required String patientId,
    required VacEventType type,
    VacLocation? location,
    String? byProfile,
    String? note,
    DateTime? at,
  }) async {
    final now = DateTime.now();
    await _store.insertRow(Collections.vacEvents, {
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'therapy_id': therapyId,
      'patient_id': patientId,
      'event_type': type.dbValue,
      'at': (at ?? now).toIso8601String(),
      'by_profile': byProfile,
      'location': location?.dbValue,
      'detail': <String, dynamic>{},
      'note': note,
      'created_at': now.toIso8601String(),
    });
  }

  /// Número de guardia VAC del centro (para escalar alarmas por WhatsApp), o
  /// null si no se ha configurado.
  String? vacOncallPhone(String? organizationId) {
    if (organizationId == null) return null;
    final match = _store.getAll(Collections.vacSettings).where(
        (s) => s['organization_id'] == organizationId);
    if (match.isEmpty) return null;
    final phone = match.first['oncall_phone'] as String?;
    return (phone == null || phone.trim().isEmpty) ? null : phone.trim();
  }

  /// Fija el número de guardia VAC del centro (upsert por organización).
  Future<void> setVacOncallPhone({
    required String organizationId,
    required String phone,
    String? updatedBy,
  }) async {
    final existing = _store
        .getAll(Collections.vacSettings)
        .where((s) => s['organization_id'] == organizationId);
    final now = DateTime.now().toIso8601String();
    final data = {
      'organization_id': organizationId,
      'oncall_phone': phone.trim(),
      'updated_by': updatedBy,
      'updated_at': now,
    };
    if (existing.isNotEmpty) {
      await _store.updateRow(
          Collections.vacSettings, existing.first['id'] as String, data);
    } else {
      await _store.insertRow(Collections.vacSettings, {
        'id': _uuid.v4(),
        'created_at': now,
        ...data,
      });
    }
  }

  PatientAdmission? activeAdmission(String patientId) {
    final match = _store.getAll(Collections.patientAdmissions).where((a) =>
        a['patient_id'] == patientId && (a['status'] as String?) == 'activo');
    return match.isEmpty ? null : PatientAdmission.fromJson(match.first);
  }

  /// Todos los internamientos activos (para el tablero de riesgo), filtrable
  /// por organización.
  List<PatientAdmission> listActiveAdmissions({String? organizationId}) => _store
      .getAll(Collections.patientAdmissions)
      .where((a) =>
          (a['status'] as String?) == 'activo' &&
          (organizationId == null || a['organization_id'] == organizationId))
      .map(PatientAdmission.fromJson)
      .toList();

  /// Ingresa (interna) a un paciente. Respeta "un solo activo": egresa primero
  /// cualquier internamiento activo previo.
  Future<PatientAdmission> admitPatient({
    required String patientId,
    required String? organizationId,
    String? unit,
    String? floor,
    String? area,
    String? bed,
    String? notes,
  }) async {
    final current = activeAdmission(patientId);
    if (current != null) await dischargePatient(current.id);
    final data = {
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'patient_id': patientId,
      'unit': unit,
      'floor': floor,
      'area': area,
      'bed': bed,
      'admitted_at': DateTime.now().toIso8601String(),
      'discharged_at': null,
      'status': AdmissionStatus.activo.dbValue,
      'notes': notes,
      'created_at': DateTime.now().toIso8601String(),
    };
    final saved = await _store.insertRow(Collections.patientAdmissions, data);
    return PatientAdmission.fromJson(saved);
  }

  Future<void> dischargePatient(String admissionId) async {
    await _store.updateRow(Collections.patientAdmissions, admissionId, {
      'status': AdmissionStatus.egresado.dbValue,
      'discharged_at': DateTime.now().toIso8601String(),
    });
  }

  // -- Valoración de riesgo (Braden) --
  List<RiskAssessment> listRiskAssessments(String patientId) => _store
      .getAll(Collections.riskAssessments)
      .where((r) => r['patient_id'] == patientId)
      .map(RiskAssessment.fromJson)
      .toList()
    ..sort((a, b) => b.assessedAt.compareTo(a.assessedAt));

  RiskAssessment? latestRiskAssessment(String patientId) {
    final all = listRiskAssessments(patientId);
    return all.isEmpty ? null : all.first;
  }

  Future<RiskAssessment> addRiskAssessment({
    required String patientId,
    required String? organizationId,
    int? bradenScore,
    Map<String, dynamic>? bradenSubscores,
    String? notes,
    required String? staffId,
  }) async {
    final data = {
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'patient_id': patientId,
      'braden_score': bradenScore,
      'braden_subscores': bradenSubscores,
      'assessed_at': DateTime.now().toIso8601String(),
      'assessed_by': staffId,
      'notes': notes,
      'created_at': DateTime.now().toIso8601String(),
    };
    final saved = await _store.insertRow(Collections.riskAssessments, data);
    return RiskAssessment.fromJson(saved);
  }

  // -------------------- Escalas clínicas genéricas (0084) --------------------

  /// Valoraciones de una escala para un paciente (más reciente primero).
  List<ScaleAssessment> listScaleAssessments(String patientId, {String? scaleId}) {
    final list = _store
        .getAll(Collections.scaleAssessments)
        .map(ScaleAssessment.fromJson)
        .where((s) =>
            s.patientId == patientId && (scaleId == null || s.scaleId == scaleId))
        .toList()
      ..sort((a, b) => b.assessedAt.compareTo(a.assessedAt));
    return list;
  }

  ScaleAssessment? latestScaleAssessment(String patientId, String scaleId) {
    final all = listScaleAssessments(patientId, scaleId: scaleId);
    return all.isEmpty ? null : all.first;
  }

  /// Última respuesta de TRIAGE del paciente (señales que no se derivan del
  /// expediente: dispositivos, adhesivos, terapia IV vesicante, etc.).
  ScaleAssessment? latestTriage(String patientId) =>
      latestScaleAssessment(patientId, 'TRIAGE');

  /// Guarda las escalas habilitadas del protocolo del centro (0085). null =
  /// todas. RPC set_enabled_scales (master o admin del centro).
  Future<void> setEnabledScales(
      String organizationId, List<String>? scales) async {
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.callRpc('set_enabled_scales', {
        'p_org': organizationId,
        'p_scales': scales,
      });
      await store.refreshCollection(Collections.organizations);
    } else {
      await _store.updateRow(Collections.organizations, organizationId,
          {'enabled_scales': scales});
    }
  }

  /// Escalas que DEBE realizar el paciente, según el triage + el expediente
  /// (comorbilidades, heridas activas, Braden, internamiento). Routing puro.
  /// Se filtran por las escalas HABILITADAS del centro (0085): una escala que el
  /// admin apagó no se ofrece, aunque el triage la dispararía.
  List<ApplicableScale> applicableScales(
      String patientId, ScaleApplicabilityCatalog catalog) {
    final comorbilidades = listComorbidities(patientId)
        .where((c) => c.status == ComorbilidadEstado.presente)
        .map((c) => c.code.name.toLowerCase())
        .toSet();
    final activeWounds =
        listWoundsForPatient(patientId).where((w) => w.isActive).toList();
    final etiologies = activeWounds.map((w) => w.etiology.name).toSet();
    final braden = latestRiskAssessment(patientId);
    final triageRow = latestTriage(patientId);
    final triage = <String, bool>{
      for (final e in (triageRow?.subscores ?? const {}).entries)
        if (e.value is bool) e.key: e.value as bool,
    };
    final admission = activeAdmission(patientId);
    final admissionDays = admission == null
        ? null
        : DateTime.now().difference(admission.admittedAt).inDays;
    final result = catalog.evaluate(ScaleEvalContext(
      comorbilidades: comorbilidades,
      woundEtiologies: etiologies,
      hasActiveWound: activeWounds.isNotEmpty,
      braden: braden?.bradenScore,
      bradenHumedad: (braden?.bradenSubscores?['humedad'] as num?)?.toInt(),
      triage: triage,
      unit: admission?.unit,
      age: getPatient(patientId)?.age,
      admissionDays: admissionDays,
    ));
    // Filtro por las escalas habilitadas del centro (null = todas).
    final orgId = getPatient(patientId)?.organizationId;
    final enabled = organizationById(orgId)?.enabledScales;
    if (enabled == null) return result;
    return result.where((s) => enabled.contains(s.scaleId)).toList();
  }

  /// Guarda las respuestas del triage como una valoración de escala 'TRIAGE'
  /// (subscores = mapa de señales booleanas).
  Future<void> saveTriage(
    String patientId, {
    required String? organizationId,
    required Map<String, bool> answers,
    required String? staffId,
  }) async {
    await addScaleAssessment(
      patientId: patientId,
      organizationId: organizationId,
      scaleId: 'TRIAGE',
      scaleVersion: '0.1',
      subscores: answers,
      staffId: staffId,
    );
  }

  Future<ScaleAssessment> addScaleAssessment({
    required String patientId,
    required String? organizationId,
    String? woundId,
    required String scaleId,
    String? scaleVersion,
    Map<String, dynamic>? subscores,
    double? totalScore,
    String? categoryResult,
    String? bandId,
    String? notes,
    required String? staffId,
  }) async {
    final now = DateTime.now().toIso8601String();
    final data = {
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'patient_id': patientId,
      'wound_id': woundId,
      'scale_id': scaleId,
      'scale_version': scaleVersion,
      'subscores': subscores,
      'total_score': totalScore,
      'category_result': categoryResult,
      'band_id': bandId,
      'assessed_at': now,
      'assessed_by': staffId,
      'notes': notes,
      'created_at': now,
    };
    final saved = await _store.insertRow(Collections.scaleAssessments, data);
    return ScaleAssessment.fromJson(saved);
  }

  /// Traduce el resultado de GLOBIAD (DAI) a tratamiento en la bitácora, SOLO en
  /// centros hospital: 2A/2B (pérdida de piel) → intensifica el control de
  /// humedad / barrera cutánea; subcategoría B (infección) → agrega vigilancia.
  /// Idempotente por rule_id 'globiad' (no toca el plan preventivo de Braden).
  Future<int> applyGlobiadTreatment(
    String patientId,
    String category, {
    required String? organizationId,
    required PreventionRulesCatalog catalog,
    String? createdBy,
  }) async {
    if (centerTypeFor(organizationId) != CenterType.hospital) return 0;
    final now = DateTime.now();
    // Limpia tareas GLOBIAD futuras pendientes (refleja la valoración actual).
    final existing = _store
        .getAll(Collections.preventiveTasks)
        .map(PreventiveTask.fromJson)
        .where((t) =>
            t.patientId == patientId &&
            t.ruleId == 'globiad' &&
            t.isPending &&
            !t.scheduledAt.isBefore(now))
        .toList();
    for (final t in existing) {
      await _store.deleteRow(Collections.preventiveTasks, t.id);
    }
    final perdida = category.startsWith('2'); // 2A/2B
    final infeccion = category.endsWith('B'); // 1B/2B
    if (!perdida && !infeccion) return 0;

    final admissionId = activeAdmission(patientId)?.id;
    var created = 0;
    Future<void> materialize(String actionId, String title, int everyHours) async {
      final count = (24 / everyHours).floor().clamp(1, 24);
      for (var i = 1; i <= count; i++) {
        await createPreventiveTask(
          patientId: patientId,
          organizationId: organizationId,
          title: title,
          scheduledAt: now.add(Duration(hours: everyHours * i)),
          admissionId: admissionId,
          ruleId: 'globiad',
          actionId: actionId,
          actionLabel: title,
          source: 'auto',
          createdBy: createdBy,
        );
        created++;
      }
    }

    if (perdida) {
      final c = catalog.cadenceFor('control_humedad');
      await materialize('control_humedad',
          c?.title ?? 'Control de humedad / barrera cutánea', c?.everyHours ?? 8);
    }
    if (infeccion) {
      await materialize('vigilancia_infeccion_dai',
          'Vigilancia/tratamiento de infección de la piel (DAI)', 12);
    }
    return created;
  }

  /// STAR: color del colgajo comprometido (categoría 1b/2b/3) → agenda una
  /// reevaluación del desgarro en 24–48 h (bitácora). Solo hospital. Idempotente
  /// por rule_id 'star'.
  Future<void> applyStarTreatment(
    String patientId,
    String category, {
    required String? organizationId,
    String? createdBy,
  }) async {
    if (centerTypeFor(organizationId) != CenterType.hospital) return;
    final now = DateTime.now();
    final existing = _store
        .getAll(Collections.preventiveTasks)
        .map(PreventiveTask.fromJson)
        .where((t) =>
            t.patientId == patientId &&
            t.ruleId == 'star' &&
            t.isPending &&
            !t.scheduledAt.isBefore(now))
        .toList();
    for (final t in existing) {
      await _store.deleteRow(Collections.preventiveTasks, t.id);
    }
    final comprometido = category.endsWith('b') || category == '3';
    if (!comprometido) return;
    await createPreventiveTask(
      patientId: patientId,
      organizationId: organizationId,
      title: 'Reevaluar desgarro (STAR color comprometido)',
      scheduledAt: now.add(const Duration(hours: 36)),
      admissionId: activeAdmission(patientId)?.id,
      ruleId: 'star',
      actionId: 'reeval_desgarro',
      actionLabel: 'Reevaluar desgarro (24–48 h)',
      source: 'auto',
      createdBy: createdBy,
    );
  }

  /// Quemaduras: gravedad crítica/mortal o criterio ABA → agenda valoración por
  /// unidad de quemados / hospitalización. Solo hospital. Idempotente ('quemadura').
  Future<void> applyQuemaduraTreatment(
    String patientId, {
    required String band,
    required bool criterioHospitalizacion,
    required String? organizationId,
    String? createdBy,
  }) async {
    if (centerTypeFor(organizationId) != CenterType.hospital) return;
    final now = DateTime.now();
    final existing = _store
        .getAll(Collections.preventiveTasks)
        .map(PreventiveTask.fromJson)
        .where((t) =>
            t.patientId == patientId &&
            t.ruleId == 'quemadura' &&
            t.isPending &&
            !t.scheduledAt.isBefore(now))
        .toList();
    for (final t in existing) {
      await _store.deleteRow(Collections.preventiveTasks, t.id);
    }
    final urgente =
        band == 'Crítico' || band == 'Mortal' || criterioHospitalizacion;
    if (!urgente) return;
    await createPreventiveTask(
      patientId: patientId,
      organizationId: organizationId,
      title: 'Valoración por unidad de quemados / hospitalización',
      scheduledAt: now.add(const Duration(hours: 1)),
      admissionId: activeAdmission(patientId)?.id,
      ruleId: 'quemadura',
      actionId: 'interconsulta_quemados',
      actionLabel: 'Interconsulta a quemados',
      source: 'auto',
      createdBy: createdBy,
    );
  }

  /// Limpia las tareas AUTO futuras pendientes de una regla (idempotencia por
  /// scale/rule). Compartido por los tratamientos de escala.
  Future<void> _clearFutureRuleTasks(String patientId, String ruleId) async {
    final now = DateTime.now();
    final existing = _store
        .getAll(Collections.preventiveTasks)
        .map(PreventiveTask.fromJson)
        .where((t) =>
            t.patientId == patientId &&
            t.ruleId == ruleId &&
            t.isPending &&
            !t.scheduledAt.isBefore(now))
        .toList();
    for (final t in existing) {
      await _store.deleteRow(Collections.preventiveTasks, t.id);
    }
  }

  /// ASEPSIS: total > corte ISQ → infección de sitio quirúrgico; agenda
  /// confirmar/tratar ISQ. Solo hospital. Idempotente ('asepsis'). El corte
  /// (asepsis_isq_above, borrador) vive en ClinicalParams para revisión de María.
  Future<void> applyAsepsisTreatment(
    String patientId,
    double total, {
    required String? organizationId,
    String? createdBy,
  }) async {
    if (centerTypeFor(organizationId) != CenterType.hospital) return;
    await _clearFutureRuleTasks(patientId, 'asepsis');
    final cut =
        ClinicalParams.isLoaded ? ClinicalParams.instance.asepsisIsqAbove : 20;
    if (total <= cut) return;
    await createPreventiveTask(
      patientId: patientId,
      organizationId: organizationId,
      title:
          'Confirmar y tratar infección de sitio quirúrgico (ASEPSIS > ${cut.toStringAsFixed(0)})',
      scheduledAt: DateTime.now().add(const Duration(hours: 2)),
      admissionId: activeAdmission(patientId)?.id,
      ruleId: 'asepsis',
      actionId: 'tratar_isq',
      actionLabel: 'Confirmar/tratar ISQ',
      source: 'auto',
      createdBy: createdBy,
    );
  }

  /// Extravasación: grado 1–4 → monitorización cada 4 h (24 h) + interconsulta a
  /// cirugía plástica. Solo hospital. Idempotente ('extravasacion').
  Future<void> applyExtravasacionTreatment(
    String patientId,
    String grado, {
    required String? organizationId,
    String? createdBy,
  }) async {
    if (centerTypeFor(organizationId) != CenterType.hospital) return;
    await _clearFutureRuleTasks(patientId, 'extravasacion');
    final g = int.tryParse(grado) ?? 0;
    if (g < 1) return;
    final now = DateTime.now();
    final admissionId = activeAdmission(patientId)?.id;
    for (var i = 1; i <= 6; i++) {
      await createPreventiveTask(
        patientId: patientId,
        organizationId: organizationId,
        title: 'Monitorización de extravasación (cada 4 h)',
        scheduledAt: now.add(Duration(hours: 4 * i)),
        admissionId: admissionId,
        ruleId: 'extravasacion',
        actionId: 'monitoreo_extravasacion',
        actionLabel: 'Monitorización c/4 h',
        source: 'auto',
        createdBy: createdBy,
      );
    }
    await createPreventiveTask(
      patientId: patientId,
      organizationId: organizationId,
      title: 'Interconsulta a cirugía plástica (extravasación grado $g)',
      scheduledAt: now.add(const Duration(hours: 1)),
      admissionId: admissionId,
      ruleId: 'extravasacion',
      actionId: 'interconsulta_plastica',
      actionLabel: 'Interconsulta cirugía plástica',
      source: 'auto',
      createdBy: createdBy,
    );
  }

  /// Tratamiento a bitácora de las escalas categóricas de clasificación (NPIAP,
  /// Wagner, CEAP, MDRPI): agenda la tarea/alerta que corresponde según el
  /// resultado. Solo hospital. Idempotente por scale_id.
  Future<void> applyCategoricalScaleTreatment(
    String patientId,
    String scaleId,
    String category, {
    required String? organizationId,
    String? createdBy,
  }) async {
    if (centerTypeFor(organizationId) != CenterType.hospital) return;
    final ruleId = scaleId.toLowerCase();
    await _clearFutureRuleTasks(patientId, ruleId);
    String? title;
    String actionId = ruleId;
    var hours = 2;
    switch (scaleId) {
      case 'NPIAP':
        if (const {'III', 'IV', 'NO_CLASIFICABLE', 'SOSPECHA_TEJIDO_PROFUNDO'}
            .contains(category)) {
          title =
              'Registro fotográfico + valoración especializada (LPP $category)';
          actionId = 'lpp_alta_complejidad';
        }
        break;
      case 'WAGNER':
        final g = int.tryParse(category) ?? 0;
        if (g >= 3) {
          title = 'Valoración especializada del pie (sospecha osteomielitis/'
              'gangrena, Wagner $g)';
          actionId = 'wagner_especialista';
          hours = 1;
        }
        break;
      case 'CEAP':
        if (category == 'C6') {
          title = 'Seguimiento de úlcera venosa activa (CEAP C6)';
          actionId = 'seguimiento_venosa';
        }
        break;
      case 'MDRPI':
        title = 'Inspección del sitio del dispositivo (por turno)';
        actionId = 'inspeccion_dispositivo';
        hours = 8;
        break;
    }
    if (title == null) return;
    await createPreventiveTask(
      patientId: patientId,
      organizationId: organizationId,
      title: title,
      scheduledAt: DateTime.now().add(Duration(hours: hours)),
      admissionId: activeAdmission(patientId)?.id,
      ruleId: ruleId,
      actionId: actionId,
      actionLabel: title,
      source: 'auto',
      createdBy: createdBy,
    );
  }

  /// Computa el riesgo de un paciente AL VUELO (no se persiste): junta sus
  /// comorbilidades presentes + última Braden + heridas activas y aplica el
  /// catálogo de reglas. Devuelve nivel + alertas preventivas.
  PreventionRiskResult computeRisk(
      String patientId, PreventionRulesCatalog catalog) {
    final patient = getPatient(patientId);
    if (patient == null) return PreventionRiskResult.empty;
    final presentes = listComorbidities(patientId)
        .where((c) => c.status == ComorbilidadEstado.presente)
        .map((c) => c.code)
        .toSet();
    final activeWounds =
        listWoundsForPatient(patientId).where((w) => w.isActive).toList();
    return catalog.evaluate(
      patient: patient,
      comorbilidadesPresentes: presentes,
      latestBraden: latestRiskAssessment(patientId)?.bradenScore,
      activeWounds: activeWounds,
      // deterioration: hook de fase 2 (requiere historial de consultas).
    );
  }

  // -- Bitácora de acciones preventivas realizadas --
  List<PreventiveActionLog> listPreventiveActions(String patientId) => _store
      .getAll(Collections.preventiveActionLog)
      .where((a) => a['patient_id'] == patientId)
      .map(PreventiveActionLog.fromJson)
      .toList()
    ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));

  /// Última vez que se registró la acción [actionId] de la regla [ruleId] para
  /// el paciente (o null si nunca). Las medidas preventivas se repiten, por eso
  /// interesa la ÚLTIMA aplicación, no un booleano.
  DateTime? lastAppliedAt(String patientId, String ruleId, String actionId) {
    DateTime? latest;
    for (final a in _store.getAll(Collections.preventiveActionLog)) {
      if (a['patient_id'] == patientId &&
          a['rule_id'] == ruleId &&
          a['action_id'] == actionId) {
        final t = DateTime.tryParse(a['applied_at'] as String? ?? '');
        if (t != null && (latest == null || t.isAfter(latest))) latest = t;
      }
    }
    return latest;
  }

  Future<PreventiveActionLog> logPreventiveAction({
    required String patientId,
    required String? organizationId,
    required String ruleId,
    required String actionId,
    required String actionLabel,
    String? notes,
    required String? staffId,
  }) async {
    final data = {
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'patient_id': patientId,
      'rule_id': ruleId,
      'action_id': actionId,
      'action_label': actionLabel,
      'applied_at': DateTime.now().toIso8601String(),
      'applied_by': staffId,
      'notes': notes,
      'created_at': DateTime.now().toIso8601String(),
    };
    final saved =
        await _store.insertRow(Collections.preventiveActionLog, data);
    return PreventiveActionLog.fromJson(saved);
  }

  // ---------------- Agenda de prevención: tareas (Fase 3) ----------------
  // (0042_preventive_tasks.sql). Tareas AGENDADAS (fecha + asignado + estado),
  // autogeneradas desde las cadencias del asset o creadas a mano.

  List<PreventiveTask> listPreventiveTasks({
    String? organizationId,
    String? patientId,
    String? assigneeProfileId,
    DateTime? from,
    DateTime? to,
  }) =>
      _store
          .getAll(Collections.preventiveTasks)
          .map(PreventiveTask.fromJson)
          .where((t) =>
              (organizationId == null || t.organizationId == organizationId) &&
              (patientId == null || t.patientId == patientId) &&
              (assigneeProfileId == null || t.assigneeProfileId == assigneeProfileId) &&
              (from == null || !t.scheduledAt.isBefore(from)) &&
              (to == null || t.scheduledAt.isBefore(to)))
          .toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  Future<PreventiveTask> createPreventiveTask({
    required String patientId,
    required String? organizationId,
    required String title,
    required DateTime scheduledAt,
    String? admissionId,
    String? ruleId,
    String? actionId,
    String? actionLabel,
    String? assigneeProfileId,
    String assigneeKind = 'staff',
    String source = 'manual',
    String? notes,
    String? createdBy,
  }) async {
    final data = {
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'patient_id': patientId,
      'admission_id': admissionId,
      'rule_id': ruleId,
      'action_id': actionId,
      'title': title,
      'action_label': actionLabel,
      'scheduled_at': scheduledAt.toIso8601String(),
      'assignee_profile_id': assigneeProfileId,
      'assignee_kind': assigneeKind,
      'status': PreventiveTaskStatus.pending.dbValue,
      'source': source,
      'notes': notes,
      'created_by': createdBy,
      'created_at': DateTime.now().toIso8601String(),
    };
    final saved = await _store.insertRow(Collections.preventiveTasks, data);
    return PreventiveTask.fromJson(saved);
  }

  Future<void> updatePreventiveTask(String id, Map<String, dynamic> patch) async {
    await _store.updateRow(Collections.preventiveTasks, id, patch);
  }

  Future<void> reschedulePreventiveTask(String id, DateTime scheduledAt) =>
      updatePreventiveTask(id, {'scheduled_at': scheduledAt.toIso8601String()});

  /// Marca una tarea como SALTADA dejando traza de quién y cuándo (reusa
  /// done_at/done_by como "resuelta por/en") para que aparezca en la bitácora.
  Future<void> skipPreventiveTask(String id, {String? byProfileId}) =>
      updatePreventiveTask(id, {
        'status': PreventiveTaskStatus.skipped.dbValue,
        'done_at': DateTime.now().toIso8601String(),
        'done_by': byProfileId,
      });

  /// Marca una tarea como HECHA y, si viene de una regla/acción, deja también
  /// el registro en preventive_action_log (bitácora, misma trazabilidad que las
  /// acciones sueltas). [byProfileId] = quién la marcó (staff o cuidador);
  /// [staffId] = su staff.id si aplica (para el log; null en cuidador).
  Future<void> completePreventiveTask(
    PreventiveTask task, {
    required String? byProfileId,
    String? staffId,
    String? notes,
  }) async {
    await updatePreventiveTask(task.id, {
      'status': PreventiveTaskStatus.done.dbValue,
      'done_at': DateTime.now().toIso8601String(),
      'done_by': byProfileId,
      if (notes != null) 'notes': notes,
    });
    if (task.ruleId != null && task.actionId != null) {
      await logPreventiveAction(
        patientId: task.patientId,
        organizationId: task.organizationId,
        ruleId: task.ruleId!,
        actionId: task.actionId!,
        actionLabel: task.actionLabel ?? task.title,
        notes: notes,
        staffId: staffId,
      );
    }
  }

  /// (Re)genera la agenda de tareas preventivas de un paciente a partir de las
  /// cadencias de las reglas que dispara su riesgo. Idempotente: borra primero
  /// las tareas AUTO FUTURAS pendientes del paciente y crea el plan fresco sobre
  /// el horizonte del catálogo. No toca tareas hechas/saltadas (historial) ni
  /// las manuales. Devuelve cuántas tareas creó.
  Future<int> generatePreventiveTasksFor(
    String patientId,
    PreventionRulesCatalog catalog, {
    required String? organizationId,
    String? assigneeProfileId,
    String assigneeKind = 'staff',
    String? createdBy,
  }) async {
    final risk = computeRisk(patientId, catalog);
    final specs = catalog.schedulableActionsFor(risk);
    return generatePreventiveTasksFromSpecs(
      patientId,
      specs,
      horizonHours: catalog.cadenceHorizonHours,
      organizationId: organizationId,
      assigneeProfileId: assigneeProfileId,
      assigneeKind: assigneeKind,
      createdBy: createdBy,
    );
  }

  /// Materializa un plan preventivo concreto (specs con cadencia) en la agenda.
  /// Idempotente: borra las tareas AUTO FUTURAS pendientes del paciente y crea
  /// el plan fresco sobre el horizonte. No toca hechas/saltadas ni manuales.
  /// Lo usan tanto la generación por reglas como el cuestionario unificado.
  /// Devuelve cuántas tareas creó.
  Future<int> generatePreventiveTasksFromSpecs(
    String patientId,
    List<ScheduledActionSpec> specs, {
    int horizonHours = 24,
    required String? organizationId,
    String? assigneeProfileId,
    String assigneeKind = 'staff',
    String? createdBy,
    bool skipNight = false,
  }) async {
    final admissionId = activeAdmission(patientId)?.id;
    final now = DateTime.now();
    // Ventana nocturna que se omite si skipNight (cuidados que no se realizan
    // de noche para no interrumpir el descanso): 22:00–06:00 hora local.
    bool isNight(DateTime d) => d.hour >= 22 || d.hour < 6;

    // Limpia tareas AUTO futuras pendientes (para reflejar la evaluación actual).
    // IMPORTANTE: materializar con .toList() ANTES de borrar — deleteRow muta
    // la lista subyacente del store; iterar el where perezoso mientras se borra
    // lanzaría ConcurrentModificationError.
    final existing = _store
        .getAll(Collections.preventiveTasks)
        .map(PreventiveTask.fromJson)
        .where((t) =>
            t.patientId == patientId &&
            t.source == 'auto' &&
            t.isPending &&
            !t.scheduledAt.isBefore(now))
        .toList();
    for (final t in existing) {
      await _store.deleteRow(Collections.preventiveTasks, t.id);
    }

    var created = 0;
    for (final s in specs) {
      // Nº de ocurrencias en el horizonte (cap defensivo a 24 por acción).
      final count = (horizonHours / s.everyHours).floor().clamp(1, 24);
      for (var i = 1; i <= count; i++) {
        final at = now.add(Duration(hours: s.everyHours * i));
        if (skipNight && isNight(at)) continue; // se omite el cuidado nocturno
        await createPreventiveTask(
          patientId: patientId,
          organizationId: organizationId,
          title: s.title,
          scheduledAt: at,
          admissionId: admissionId,
          ruleId: s.ruleId,
          actionId: s.actionId,
          actionLabel: s.actionLabel,
          assigneeProfileId: assigneeProfileId,
          assigneeKind: assigneeKind,
          source: 'auto',
          createdBy: createdBy,
        );
        created++;
      }
    }
    return created;
  }

  // ------------- Prevención hospitalaria: auto-plan + cumplimiento -------------

  /// En centros HOSPITAL, al valorar el riesgo (Braden) se materializa
  /// AUTOMÁTICAMENTE el plan esperado por nivel (tareas sin dueño, siguen al
  /// paciente). En otros tipos no hace nada (el plan lo define el profesional/
  /// cuidador). El profesional puede ajustar después con el selector.
  Future<void> autoGeneratePlanIfHospital(
    String patientId,
    PreventionRulesCatalog catalog, {
    required String? organizationId,
    String? createdBy,
  }) async {
    if (centerTypeFor(organizationId) != CenterType.hospital) return;
    await generatePreventiveTasksFor(
      patientId,
      catalog,
      organizationId: organizationId,
      createdBy: createdBy,
    );
  }

  /// Inicio de la ventana de cumplimiento para un centro: el turno actual si el
  /// centro tiene turnos configurados (organizations.shift_config), o las
  /// últimas 24 h por defecto.
  DateTime complianceWindowStart(String? organizationId, DateTime now) {
    final orgs = _store
        .getAll(Collections.organizations)
        .where((o) => o['id'] == organizationId);
    final cfg = orgs.isEmpty ? null : orgs.first['shift_config'];
    if (cfg is List && cfg.isNotEmpty) {
      for (final s in cfg) {
        if (s is! Map) continue;
        final start = (s['startHour'] as num?)?.toInt();
        final end = (s['endHour'] as num?)?.toInt();
        if (start == null || end == null) continue;
        final h = now.hour;
        final inShift =
            start <= end ? (h >= start && h < end) : (h >= start || h < end);
        if (inShift) {
          var d = DateTime(now.year, now.month, now.day, start);
          // Turno que cruza medianoche y ya pasó la medianoche: empezó ayer.
          if (start > end && now.hour < end) {
            d = d.subtract(const Duration(days: 1));
          }
          return d;
        }
      }
    }
    return now.subtract(const Duration(hours: 24));
  }

  /// Cumplimiento preventivo del paciente en la ventana (turno actual o 24 h):
  /// por tipo de actividad y global. Fuente ÚNICA para tarjeta/perfil/dashboard.
  PreventiveComplianceResult preventiveCompliance(
    String patientId, {
    required String? organizationId,
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final start = complianceWindowStart(organizationId, ref);
    final tasks = listPreventiveTasks(patientId: patientId).where((t) =>
        !t.scheduledAt.isBefore(start) &&
        !t.scheduledAt.isAfter(ref) && // ya vencidas dentro de la ventana
        t.status != PreventiveTaskStatus.canceled);
    final byType = <String, PreventiveComplianceType>{};
    var doneTotal = 0;
    var expectedTotal = 0;
    for (final t in tasks) {
      final key = t.actionId ?? t.title;
      final cur = byType[key] ??
          PreventiveComplianceType(actionId: key, title: t.title, done: 0, expected: 0);
      final isDone = t.status == PreventiveTaskStatus.done;
      byType[key] = PreventiveComplianceType(
        actionId: key,
        title: t.title,
        done: cur.done + (isDone ? 1 : 0),
        expected: cur.expected + 1,
      );
      expectedTotal += 1;
      if (isDone) doneTotal += 1;
    }
    return PreventiveComplianceResult(
      byType: byType.values.toList(),
      doneTotal: doneTotal,
      expectedTotal: expectedTotal,
    );
  }

  // ---------------- Cuidador ↔ paciente (Fase 3) ----------------

  List<CaregiverPatientAssignment> listCaregiverAssignments({
    String? organizationId,
    String? caregiverProfileId,
    String? patientId,
  }) =>
      _store
          .getAll(Collections.caregiverPatientAssignments)
          .map(CaregiverPatientAssignment.fromJson)
          .where((a) =>
              (organizationId == null || a.organizationId == organizationId) &&
              (caregiverProfileId == null || a.caregiverProfileId == caregiverProfileId) &&
              (patientId == null || a.patientId == patientId))
          .toList();

  /// Pacientes que un cuidador puede monitorear (ids).
  List<String> patientIdsForCaregiver(String caregiverProfileId) =>
      listCaregiverAssignments(caregiverProfileId: caregiverProfileId)
          .map((a) => a.patientId)
          .toList();

  Future<void> assignCaregiverToPatient({
    required String caregiverProfileId,
    required String patientId,
    required String? organizationId,
    String? assignedBy,
  }) async {
    // Evita duplicar (unique en BD; aquí también en demo).
    final dup = listCaregiverAssignments(
        caregiverProfileId: caregiverProfileId, patientId: patientId);
    if (dup.isNotEmpty) return;
    await _store.insertRow(Collections.caregiverPatientAssignments, {
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'caregiver_profile_id': caregiverProfileId,
      'patient_id': patientId,
      'assigned_by': assignedBy,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> removeCaregiverAssignment(String id) async {
    await _store.deleteRow(Collections.caregiverPatientAssignments, id);
  }

  // -- Indicaciones del profesional para el cuidador (0044) --

  /// Texto de indicaciones para el cuidador de un paciente, o null.
  String? caregiverInstructionsFor(String patientId) {
    final match = _store
        .getAll(Collections.caregiverInstructions)
        .where((r) => r['patient_id'] == patientId);
    return match.isEmpty ? null : match.first['instructions'] as String?;
  }

  /// Crea o actualiza las indicaciones para el cuidador (upsert por paciente).
  /// Solo personal del centro (RLS 0044). [text] vacío borra la fila.
  Future<void> setCaregiverInstructions({
    required String patientId,
    required String? organizationId,
    required String text,
    String? updatedBy,
  }) async {
    final existing = _store
        .getAll(Collections.caregiverInstructions)
        .where((r) => r['patient_id'] == patientId)
        .toList();
    final trimmed = text.trim();
    if (existing.isNotEmpty) {
      final id = existing.first['id'] as String;
      if (trimmed.isEmpty) {
        await _store.deleteRow(Collections.caregiverInstructions, id);
      } else {
        await _store.updateRow(Collections.caregiverInstructions, id, {
          'instructions': trimmed,
          'updated_by': updatedBy,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
      return;
    }
    if (trimmed.isEmpty) return;
    await _store.insertRow(Collections.caregiverInstructions, {
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'patient_id': patientId,
      'instructions': trimmed,
      'updated_by': updatedBy,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Próxima cita (manual) futura de un paciente, o null. Para la vista del
  /// cuidador (contacto/agenda del centro).
  ManualAppointment? nextManualAppointmentForPatient(String patientId) {
    final now = DateTime.now();
    final upcoming = _store
        .getAll(Collections.manualAppointments)
        .map(ManualAppointment.fromJson)
        .where((a) =>
            a.patientId == patientId &&
            a.status != 'canceled' &&
            a.datetime.isAfter(now))
        .toList()
      ..sort((a, b) => a.datetime.compareTo(b.datetime));
    return upcoming.isEmpty ? null : upcoming.first;
  }

  // ---------------- Consultas ----------------

  List<Consultation> listConsultationsForPatient(String patientId) => _store
      .getAll(Collections.consultations)
      .where((c) => c['patient_id'] == patientId)
      .map(Consultation.fromJson)
      .toList()
    ..sort((a, b) => b.visitDate.compareTo(a.visitDate));

  Consultation? getConsultation(String id) {
    final match = _store.getAll(Collections.consultations).where((c) => c['id'] == id);
    return match.isEmpty ? null : Consultation.fromJson(match.first);
  }

  /// Herida asociada a una consulta (vía su medición). Sirve para reabrir un
  /// borrador de seguimiento en el formulario correcto.
  String? woundIdForConsultation(String consultationId) {
    final m = _store
        .getAll(Collections.woundMeasurements)
        .where((x) => x['consultation_id'] == consultationId);
    return m.isEmpty ? null : m.first['wound_id'] as String?;
  }

  /// Borra los datos de HERIDA de una consulta (fotos, evaluaciones,
  /// mediciones) SIN borrar la consulta ni sus cobros/insumos. Se usa al
  /// finalizar un borrador (se re-crean con los datos definitivos).
  Future<void> deleteWoundDataForConsultation(String consultationId) async {
    for (final coll in [
      Collections.woundPhotos,
      Collections.woundAssessments,
      Collections.woundMeasurements,
    ]) {
      final rows = _store
          .getAll(coll)
          .where((r) => r['consultation_id'] == consultationId)
          .toList();
      for (final r in rows) {
        await _store.deleteRow(coll, r['id'] as String);
      }
    }
  }

  /// Actualiza campos de una consulta en su lugar (finalizar borrador: conserva
  /// el id para no huerfanar cobros/insumos ya ligados).
  Future<void> updateConsultationFields(
      String consultationId, Map<String, dynamic> patch) async {
    await _store.updateRow(Collections.consultations, consultationId, patch);
    // KT-1: confirma contra el servidor que el cambio quedó (evita el detalle
    // fantasma "Consulta no encontrada" por cache desincronizada).
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.refreshCollection(Collections.consultations);
    }
  }

  /// Elimina una consulta EN BORRADOR y su captura de herida asociada (fotos/
  /// valoración/mediciones de esa consulta). Usado para descartar un borrador
  /// que ya no se va a completar. No borra la herida en sí (persiste entre
  /// consultas), solo los datos capturados en esta consulta.
  Future<void> deleteConsultation(String consultationId) async {
    await deleteWoundDataForConsultation(consultationId);
    await _store.deleteRow(Collections.consultations, consultationId);
  }

  /// Consulta ligada a una cita de la agenda, por su referencia
  /// ("acuity:<id>" | "manual:<uuid>"), o null si aún no se ha realizado.
  /// Usado por la agenda para el botón inteligente "Iniciar / Ir a la consulta".
  Consultation? consultationForAppointmentRef(String ref) {
    final match = _store
        .getAll(Collections.consultations)
        .where((c) => c['scheduled_appointment_ref'] == ref);
    return match.isEmpty ? null : Consultation.fromJson(match.first);
  }

  Future<Consultation> createConsultation({
    required String patientId,
    required String staffId,
    required String siteId,
    required VisitType visitType,
    required DateTime visitDate,
    Map<String, dynamic>? vitalSigns,
    bool isDraft = false,
    // Nota de seguimiento obligatoria (Instructivo de Archivo), aplica a
    // visit_type=seguimiento; ver migracion 0008.
    String? followUpCareType,
    String? followUpProcedureDesc,
    String? followUpMaterialsUsed,
    String? followUpEvolution,
    String? followUpSignedBy,
    String? followUpSignedLicense,
    String? followUpSignedSpecialty,
    String? followUpSignature,
    DateTime? followUpSignedAt,
    // Cita de la agenda que originó esta consulta (0035), formato
    // "acuity:<id>" | "manual:<uuid>". La pasa el hub de consulta cuando se
    // entra desde la agenda ("Iniciar consulta").
    String? scheduledAppointmentRef,
    String? specialistNotes,
    String? visitSummary,
    String? transcript,
  }) async {
    final data = {
      'id': _uuid.v4(),
      'patient_id': patientId,
      'staff_id': staffId,
      'site_id': siteId,
      'visit_type': visitType.dbValue,
      'visit_date': visitDate.toIso8601String().substring(0, 10),
      'vital_signs': vitalSigns,
      'is_draft': isDraft,
      'created_at': DateTime.now().toIso8601String(),
      'follow_up_care_type': followUpCareType,
      'follow_up_procedure_desc': followUpProcedureDesc,
      'follow_up_materials_used': followUpMaterialsUsed,
      'follow_up_evolution': followUpEvolution,
      'follow_up_signed_by': followUpSignedBy,
      'follow_up_signed_license': followUpSignedLicense,
      'follow_up_signed_specialty': followUpSignedSpecialty,
      'follow_up_signature': followUpSignature,
      'follow_up_signed_at': followUpSignedAt?.toIso8601String(),
      'scheduled_appointment_ref': scheduledAppointmentRef,
      'specialist_notes': specialistNotes,
      'visit_summary': visitSummary,
      'transcript': transcript,
    };
    final saved = await _store.insertRow(Collections.consultations, data);
    // KT-1: refresca la colección tras crear para que el detalle (que lee de
    // cache) encuentre la consulta recién guardada y se confirme la persistencia.
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.refreshCollection(Collections.consultations);
    }
    return Consultation.fromJson(saved);
  }

  Future<void> updateConsultationDraftStatus(String id, bool isDraft) async {
    await _store.updateRow(Collections.consultations, id, {'is_draft': isDraft});
  }

  // ---------------- Notas de enmienda / aclaración (NOM-004, Fase 4) ----------

  /// Enmiendas de una consulta (nota), de la más antigua a la más reciente
  /// (orden cronológico del expediente). Append-only.
  List<ClinicalAmendment> listAmendmentsForConsultation(String consultationId) =>
      _store
          .getAll(Collections.clinicalAmendments)
          .where((a) => a['consultation_id'] == consultationId)
          .map(ClinicalAmendment.fromJson)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  /// Agrega una nota de enmienda/aclaración a una consulta. NO edita ni borra el
  /// original (append-only). `staffId`/firma los pasa la pantalla desde sesión.
  Future<ClinicalAmendment> addAmendment({
    required String patientId,
    required String consultationId,
    required String body,
    String? reason,
    required String? staffId,
    String? signedBy,
    String? signedLicense,
  }) async {
    final amendment = ClinicalAmendment(
      id: _uuid.v4(),
      patientId: patientId,
      consultationId: consultationId,
      body: body,
      reason: reason,
      staffId: staffId,
      signedBy: signedBy,
      signedLicense: signedLicense,
      createdAt: DateTime.now(),
    );
    final saved = await _store.insertRow(
        Collections.clinicalAmendments, amendment.toJson());
    return ClinicalAmendment.fromJson(saved);
  }

  // ---------------- Eventos adversos (COFEPRIS) ----------------

  /// Bitácora de eventos adversos de un paciente, del más reciente al más
  /// antiguo (por fecha de ocurrencia). Ver migración 0025_adverse_events.sql.
  List<AdverseEvent> listAdverseEventsForPatient(String patientId) => _store
      .getAll(Collections.adverseEvents)
      .where((e) => e['patient_id'] == patientId)
      .map(AdverseEvent.fromJson)
      .toList()
    ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

  AdverseEvent? getAdverseEvent(String id) {
    final match =
        _store.getAll(Collections.adverseEvents).where((e) => e['id'] == id);
    return match.isEmpty ? null : AdverseEvent.fromJson(match.first);
  }

  /// Crea un evento adverso. `organizationId` y `staffId` los pasa la pantalla
  /// desde `session.user` (mismo patrón que createPatient/createConsultation):
  /// el repo no lee la sesión. `organizationId` es obligatorio por RLS
  /// (adverse_events.organization_id not null + policy de inserción).
  Future<AdverseEvent> createAdverseEvent({
    required String organizationId,
    required String patientId,
    required String? staffId,
    String? woundId,
    String? consultationId,
    required DateTime occurredAt,
    required String type,
    required AdverseEventSeverity severity,
    Set<AdverseEventAlarmSign> alarmSigns = const {},
    String? description,
    String? actionsTaken,
    String? evolution,
    DateTime? reportedAt,
  }) async {
    final event = AdverseEvent(
      id: _uuid.v4(),
      organizationId: organizationId,
      patientId: patientId,
      staffId: staffId,
      woundId: woundId,
      consultationId: consultationId,
      occurredAt: occurredAt,
      type: type,
      severity: severity,
      alarmSigns: alarmSigns,
      description: description,
      actionsTaken: actionsTaken,
      evolution: evolution,
      reportedAt: reportedAt,
      createdAt: DateTime.now(),
    );
    final saved =
        await _store.insertRow(Collections.adverseEvents, event.toJson());
    return AdverseEvent.fromJson(saved);
  }

  /// Marca un evento como reportado a la autoridad (registra reported_at).
  /// Usado por el recordatorio de reporte ≤24 h de los eventos centinela.
  Future<AdverseEvent> markAdverseEventReported(
    String id, {
    DateTime? reportedAt,
  }) async {
    final saved = await _store.updateRow(Collections.adverseEvents, id, {
      'reported_at': (reportedAt ?? DateTime.now()).toIso8601String(),
    });
    return AdverseEvent.fromJson(saved);
  }

  // ---------------- Consentimientos (Expedientes clínicos / Desbridamiento) ----

  /// Consentimientos vigentes de un paciente (uno por tipo).
  List<Consent> listConsentsForPatient(String patientId) => _store
      .getAll(Collections.consents)
      .where((c) => c['patient_id'] == patientId)
      .map(Consent.fromJson)
      .toList();

  /// Consentimiento de un tipo para el paciente (null si no existe fila).
  Consent? consentFor(String patientId, ConsentType type) {
    final match = _store.getAll(Collections.consents).where(
        (c) => c['patient_id'] == patientId && c['type'] == type.dbValue);
    return match.isEmpty ? null : Consent.fromJson(match.first);
  }

  /// true si el paciente tiene el consentimiento [type] otorgado (granted).
  bool hasConsent(String patientId, ConsentType type) =>
      consentFor(patientId, type)?.granted ?? false;

  /// true si el paciente tiene TODOS los consentimientos indicados otorgados.
  bool hasConsents(String patientId, Iterable<ConsentType> types) =>
      types.every((t) => hasConsent(patientId, t));

  /// Tipos requeridos que faltan (no otorgados) para el paciente.
  List<ConsentType> missingConsents(
          String patientId, Iterable<ConsentType> required) =>
      required.where((t) => !hasConsent(patientId, t)).toList();

  /// Registra/actualiza un consentimiento (uno por paciente+tipo, ver
  /// unique(patient_id,type) en 0026). Si ya existe fila para ese tipo se
  /// actualiza (permite otorgar o revocar); si no, se inserta.
  Future<Consent> setConsent({
    required String patientId,
    required ConsentType type,
    required bool granted,
    String? signedBy,
    String? docRef,
  }) async {
    final existing = _store.getAll(Collections.consents).where(
        (c) => c['patient_id'] == patientId && c['type'] == type.dbValue);
    final patch = {
      'granted': granted,
      'granted_at': granted ? DateTime.now().toIso8601String() : null,
      'signed_by': signedBy,
      'doc_ref': docRef,
    };
    if (existing.isNotEmpty) {
      final saved = await _store.updateRow(
          Collections.consents, existing.first['id'] as String, patch);
      return Consent.fromJson(saved);
    }
    final row = {
      'id': _uuid.v4(),
      'patient_id': patientId,
      'type': type.dbValue,
      ...patch,
      'created_at': DateTime.now().toIso8601String(),
    };
    final saved = await _store.insertRow(Collections.consents, row);
    return Consent.fromJson(saved);
  }

  // ---------------- Referencias / interconsultas (Prompt 6) ----------------

  /// Referencias de un paciente, de la más reciente a la más antigua.
  List<Referral> listReferralsForPatient(String patientId) => _store
      .getAll(Collections.referrals)
      .where((r) => r['patient_id'] == patientId)
      .map(Referral.fromJson)
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Referral? getReferral(String id) {
    final match =
        _store.getAll(Collections.referrals).where((r) => r['id'] == id);
    return match.isEmpty ? null : Referral.fromJson(match.first);
  }

  /// Crea una referencia. `staffId` y las firmas las pasa la pantalla desde la
  /// sesión (mismo patrón que createConsultation).
  Future<Referral> createReferral({
    required String patientId,
    required String? staffId,
    String? woundId,
    String? consultationId,
    required String especialidad,
    required String motivo,
    Set<ReferralAdjunto> adjuntos = const {},
    String? referralSignedBy,
    String? referralSignedLicense,
  }) async {
    final referral = Referral(
      id: _uuid.v4(),
      patientId: patientId,
      staffId: staffId,
      woundId: woundId,
      consultationId: consultationId,
      especialidad: especialidad,
      motivo: motivo,
      adjuntos: adjuntos,
      referralSignedBy: referralSignedBy,
      referralSignedLicense: referralSignedLicense,
      createdAt: DateTime.now(),
    );
    final saved =
        await _store.insertRow(Collections.referrals, referral.toJson());
    return Referral.fromJson(saved);
  }

  /// Registra el documento de RETORNO del especialista y marca la referencia
  /// como respondida (Prompt 6).
  Future<Referral> registerReferralReturn(
    String id, {
    String? returnDocRef,
    String? returnNotes,
  }) async {
    final saved = await _store.updateRow(Collections.referrals, id, {
      'return_doc_ref': returnDocRef,
      'return_notes': returnNotes,
      'returned_at': DateTime.now().toIso8601String(),
      'status': ReferralStatus.respondida.dbValue,
    });
    return Referral.fromJson(saved);
  }

  // ---------------- Heridas ----------------

  List<Wound> listWoundsForPatient(String patientId) => _store
      .getAll(Collections.wounds)
      .where((w) => w['patient_id'] == patientId)
      .map(Wound.fromJson)
      .toList();

  Wound? getWound(String id) {
    final match = _store.getAll(Collections.wounds).where((w) => w['id'] == id);
    return match.isEmpty ? null : Wound.fromJson(match.first);
  }

  Future<Wound> createWound(Map<String, dynamic> data) async {
    final row = Map<String, dynamic>.from(data);
    row['id'] = row['id'] ?? _uuid.v4();
    row['created_at'] = row['created_at'] ?? DateTime.now().toIso8601String();
    row['is_active'] = row['is_active'] ?? true;
    final saved = await _store.insertRow(Collections.wounds, row);
    return Wound.fromJson(saved);
  }

  /// Actualiza campos de una herida existente (patch parcial). Usado para
  /// persistir el perfil diagnóstico (subtipo vascular / no revascularizable)
  /// cuando se re-valora una herida ya creada.
  Future<Wound> updateWound(String woundId, Map<String, dynamic> patch) async {
    final saved = await _store.updateRow(Collections.wounds, woundId, patch);
    return Wound.fromJson(saved);
  }

  /// Egreso del episodio de una herida (Prompt 5): cierra la herida con un
  /// motivo estructurado (cierre/alta voluntaria/abandono/defunción) y marca
  /// closed_at. `motivoEgreso` es el `name` del enum MotivoEgreso.
  Future<Wound> closeWound(String woundId, MotivoEgreso motivoEgreso,
      {String? dischargeNote}) async {
    final saved = await _store.updateRow(Collections.wounds, woundId, {
      'is_active': false,
      'closed_at': DateTime.now().toIso8601String(),
      'discharge_reason': motivoEgreso.name,
      'discharge_note': dischargeNote,
    });
    return Wound.fromJson(saved);
  }

  // ---------------- Evaluaciones ----------------

  List<WoundAssessment> listAssessmentsForWound(String woundId) => _store
      .getAll(Collections.woundAssessments)
      .where((a) => a['wound_id'] == woundId)
      .map(WoundAssessment.fromJson)
      .toList();

  Future<WoundAssessment> createAssessment(Map<String, dynamic> data) async {
    final row = Map<String, dynamic>.from(data);
    row['id'] = row['id'] ?? _uuid.v4();
    final saved = await _store.insertRow(Collections.woundAssessments, row);
    return WoundAssessment.fromJson(saved);
  }

  // ---------------- Mediciones ----------------

  List<WoundMeasurement> listMeasurementsForWound(String woundId) {
    final list = _store
        .getAll(Collections.woundMeasurements)
        .where((m) => m['wound_id'] == woundId)
        .map(WoundMeasurement.fromJson)
        .toList();
    list.sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    return list;
  }

  Future<WoundMeasurement> createMeasurement(Map<String, dynamic> data) async {
    final row = Map<String, dynamic>.from(data);
    row['id'] = row['id'] ?? _uuid.v4();
    final saved = await _store.insertRow(Collections.woundMeasurements, row);
    return WoundMeasurement.fromJson(saved);
  }

  // ---------------- Perfusion / nutricion ----------------

  PerfusionNutritionData? getPerfusionForWound(String woundId) {
    final list = _store
        .getAll(Collections.perfusionNutrition)
        .where((p) => p['wound_id'] == woundId)
        .toList();
    if (list.isEmpty) return null;
    return PerfusionNutritionData.fromJson(list.last);
  }

  Future<PerfusionNutritionData> upsertPerfusion(Map<String, dynamic> data) async {
    final row = Map<String, dynamic>.from(data);
    row['id'] = row['id'] ?? _uuid.v4();
    final saved = await _store.upsertRow(Collections.perfusionNutrition, row);
    return PerfusionNutritionData.fromJson(saved);
  }

  // ---------------- Fotos ----------------

  List<WoundPhoto> listPhotosForWound(String woundId) => _store
      .getAll(Collections.woundPhotos)
      .where((p) => p['wound_id'] == woundId)
      .map(WoundPhoto.fromJson)
      .toList();

  Future<WoundPhoto> createPhoto(Map<String, dynamic> data) async {
    final row = Map<String, dynamic>.from(data);
    row['id'] = row['id'] ?? _uuid.v4();
    row['taken_at'] = row['taken_at'] ?? DateTime.now().toIso8601String();
    final saved = await _store.insertRow(Collections.woundPhotos, row);
    return WoundPhoto.fromJson(saved);
  }

  // ---------------- Planes de tratamiento ----------------

  TreatmentPlan? getTreatmentPlanForConsultation(String consultationId, String woundId) {
    final plans = _store
        .getAll(Collections.treatmentPlans)
        .where((p) => p['consultation_id'] == consultationId && p['wound_id'] == woundId);
    if (plans.isEmpty) return null;
    final planJson = plans.first;
    final components = _store
        .getAll(Collections.treatmentComponents)
        .where((c) => c['treatment_plan_id'] == planJson['id'])
        .map(TreatmentComponentRecord.fromJson)
        .toList();
    return TreatmentPlan.fromJson(planJson, components: components);
  }

  Future<TreatmentPlan> saveTreatmentPlan({
    required String consultationId,
    required String woundId,
    required bool usedKuraProtocol,
    String? finalDescription,
    required List<TreatmentComponentRecord> components,
  }) async {
    final existing = _store
        .getAll(Collections.treatmentPlans)
        .where((p) => p['consultation_id'] == consultationId && p['wound_id'] == woundId);
    final planId = existing.isEmpty ? _uuid.v4() : existing.first['id'] as String;

    final planData = {
      'id': planId,
      'consultation_id': consultationId,
      'wound_id': woundId,
      'used_kura_protocol': usedKuraProtocol,
      'final_description': finalDescription,
    };
    await _store.upsertRow(Collections.treatmentPlans, planData);

    // Reemplaza componentes: borra los existentes del plan y crea los nuevos.
    // (Se hace fila por fila via la interfaz DataStore, en vez de un
    // "replace masivo", para que funcione igual sobre LocalStore y sobre
    // Postgrest sin necesitar un endpoint de bulk-replace).
    final existingComponents = _store
        .getAll(Collections.treatmentComponents)
        .where((c) => c['treatment_plan_id'] == planId)
        .toList();
    for (final c in existingComponents) {
      await _store.deleteRow(Collections.treatmentComponents, c['id'] as String);
    }
    for (var i = 0; i < components.length; i++) {
      final c = components[i];
      await _store.insertRow(Collections.treatmentComponents, {
        'id': c.id.isEmpty ? _uuid.v4() : c.id,
        'treatment_plan_id': planId,
        'method': c.method,
        'product': c.product,
        'origin': c.origin.dbValue,
        'sort_order': i,
      });
    }

    return getTreatmentPlanForConsultation(consultationId, woundId)!;
  }

  // ---------------- Programa de tratamiento mensual (0075) ----------------

  /// Crea el encabezado de un programa (plan mensual) en estado borrador.
  Future<TreatmentProgram> createTreatmentProgram({
    required String organizationId,
    required String patientId,
    required String woundId,
    String? consultationId,
    String? siteId,
    String? staffId,
    int weeks = 4,
    String? createdBy,
  }) async {
    final now = DateTime.now().toIso8601String();
    final saved = await _store.insertRow(Collections.treatmentPrograms, {
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'patient_id': patientId,
      'wound_id': woundId,
      'consultation_id': consultationId,
      'site_id': siteId,
      'staff_id': staffId,
      'weeks': weeks,
      'status': 'borrador',
      'created_by': createdBy,
      'created_at': now,
      'updated_at': now,
    });
    return TreatmentProgram.fromJson(saved);
  }

  TreatmentProgram? programById(String? id) {
    if (id == null) return null;
    final m = _store
        .getAll(Collections.treatmentPrograms)
        .where((p) => p['id'] == id);
    return m.isEmpty ? null : TreatmentProgram.fromJson(m.first);
  }

  TreatmentProgram? programForConsultation(String consultationId) {
    final rows = _store
        .getAll(Collections.treatmentPrograms)
        .where((p) => p['consultation_id'] == consultationId)
        .map(TreatmentProgram.fromJson)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows.isEmpty ? null : rows.first;
  }

  /// Programa vigente (no cancelado) más reciente de una herida.
  TreatmentProgram? activeProgramForWound(String woundId) {
    final rows = _store
        .getAll(Collections.treatmentPrograms)
        .map(TreatmentProgram.fromJson)
        .where((p) =>
            p.woundId == woundId && p.status != ProgramStatus.cancelado)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateProgramStatus(String id, ProgramStatus status,
      {DateTime? acceptedAt}) async {
    await _store.updateRow(Collections.treatmentPrograms, id, {
      'status': status.dbValue,
      if (acceptedAt != null) 'accepted_at': acceptedAt.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  List<TreatmentProgramSupply> listProgramSupplies(String programId) => _store
      .getAll(Collections.treatmentProgramSupplies)
      .map(TreatmentProgramSupply.fromJson)
      .where((s) => s.programId == programId)
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// Reemplaza los insumos del programa (borra los existentes y crea los nuevos),
  /// mismo patrón que saveTreatmentPlan (fila por fila para LocalStore/Postgrest).
  Future<void> saveProgramSupplies(
    String programId,
    String organizationId,
    List<
            ({
              String method,
              String? product,
              String? inventoryItemId,
              String name,
              double quantityPerSession,
              bool isMonthly,
              double? unitCost,
              double? unitPrice,
              String? currency
            })>
        supplies,
  ) async {
    final existing = _store
        .getAll(Collections.treatmentProgramSupplies)
        .where((s) => s['program_id'] == programId)
        .toList();
    for (final s in existing) {
      await _store.deleteRow(
          Collections.treatmentProgramSupplies, s['id'] as String);
    }
    final now = DateTime.now().toIso8601String();
    for (var i = 0; i < supplies.length; i++) {
      final s = supplies[i];
      await _store.insertRow(Collections.treatmentProgramSupplies, {
        'id': _uuid.v4(),
        'program_id': programId,
        'organization_id': organizationId,
        'method': s.method,
        'product': s.product,
        'inventory_item_id': s.inventoryItemId,
        'name': s.name,
        'quantity_per_session': s.quantityPerSession,
        'is_monthly': s.isMonthly,
        'unit_cost': s.unitCost,
        'unit_price': s.unitPrice,
        'currency': s.currency ?? 'MXN',
        'sort_order': i,
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  List<TreatmentProgramSession> listProgramSessions(String programId) => _store
      .getAll(Collections.treatmentProgramSessions)
      .map(TreatmentProgramSession.fromJson)
      .where((s) => s.programId == programId)
      .toList()
    ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  /// Reemplaza las sesiones del programa.
  Future<void> saveProgramSessions(
    String programId,
    String organizationId,
    String patientId,
    List<
            ({
              String? staffId,
              DateTime scheduledAt,
              DateTime? endAt,
              String? appointmentRef
            })>
        sessions,
  ) async {
    final existing = _store
        .getAll(Collections.treatmentProgramSessions)
        .where((s) => s['program_id'] == programId)
        .toList();
    for (final s in existing) {
      await _store.deleteRow(
          Collections.treatmentProgramSessions, s['id'] as String);
    }
    final now = DateTime.now().toIso8601String();
    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      await _store.insertRow(Collections.treatmentProgramSessions, {
        'id': _uuid.v4(),
        'program_id': programId,
        'organization_id': organizationId,
        'patient_id': patientId,
        'staff_id': s.staffId,
        'scheduled_at': s.scheduledAt.toIso8601String(),
        'end_at': s.endAt?.toIso8601String(),
        'status': 'planeada',
        'appointment_ref': s.appointmentRef,
        'sort_index': i,
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  /// Sesiones de programas de un centro (para la agenda), no canceladas.
  /// `staffId` filtra por Kurador; null = todas las del centro.
  List<TreatmentProgramSession> listProgramSessionsForOrg({
    required String organizationId,
    String? staffId,
  }) =>
      _store
          .getAll(Collections.treatmentProgramSessions)
          .map(TreatmentProgramSession.fromJson)
          .where((s) =>
              s.organizationId == organizationId &&
              s.status != SessionStatus.cancelada &&
              (staffId == null || s.staffId == staffId))
          .toList()
        ..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));

  /// Pre-carga en un SEGUIMIENTO los insumos POR SESIÓN del plan mensual
  /// aceptado de la herida, si la consulta aún no tiene insumos. Así el
  /// seguimiento llega con los insumos listos (el especialista solo captura
  /// herida + notas y al final ajusta/cobra). Los insumos MENSUALES (multidosis)
  /// NO se auto-cargan por sesión (evita sobre-cobro; se manejan aparte).
  /// Devuelve cuántos se agregaron. Idempotente: no hace nada si ya hay insumos.
  Future<int> preloadProgramSuppliesIntoConsultation({
    required String consultationId,
    required String organizationId,
    required String? patientId,
    String? createdBy,
  }) async {
    if (listSupplyUsageForConsultation(consultationId).isNotEmpty) return 0;
    final woundId = woundIdForConsultation(consultationId);
    if (woundId == null) return 0;
    final program = activeProgramForWound(woundId);
    if (program == null || program.status != ProgramStatus.aceptado) return 0;
    var added = 0;
    for (final s in listProgramSupplies(program.id)) {
      if (s.inventoryItemId == null || s.isMonthly) continue;
      await addSupplyUsage(
        organizationId: organizationId,
        consultationId: consultationId,
        patientId: patientId,
        name: s.name,
        inventoryItemId: s.inventoryItemId,
        quantity:
            s.quantityPerSession <= 0 ? 1 : s.quantityPerSession.ceil(),
        unitCost: s.unitCost,
        unitPrice: s.unitPrice,
        currency: s.currency,
        createdBy: createdBy,
      );
      added++;
    }
    return added;
  }

  /// Explosión de materiales del CENTRO: agrega la explosión mensual de TODOS
  /// los programas aceptados de la organización, por producto, y la compara con
  /// el stock actual. Para que atención a cliente reserve/compre el mes.
  List<
      ({
        String name,
        String? inventoryItemId,
        double needed,
        int onHand,
      })> centerMaterialsExplosion(String organizationId) {
    final programs = _store
        .getAll(Collections.treatmentPrograms)
        .map(TreatmentProgram.fromJson)
        .where((p) =>
            p.organizationId == organizationId &&
            p.status == ProgramStatus.aceptado);
    final agg = <String, ({String name, String? inventoryItemId, double needed})>{};
    for (final p in programs) {
      for (final e in monthlyExplosion(p.id)) {
        final key = e.inventoryItemId ?? e.name;
        final prev = agg[key];
        agg[key] = (
          name: e.name,
          inventoryItemId: e.inventoryItemId,
          needed: (prev?.needed ?? 0) + e.totalQuantity,
        );
      }
    }
    final out = [
      for (final v in agg.values)
        (
          name: v.name,
          inventoryItemId: v.inventoryItemId,
          needed: v.needed,
          onHand: v.inventoryItemId == null ? 0 : onHandFor(v.inventoryItemId!),
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// Actualiza la cita/estado de una sesión (tras empujarla a Acuity).
  Future<void> updateProgramSessionAcuity(
    String sessionId, {
    String? appointmentRef,
    SessionStatus? status,
  }) async {
    await _store.updateRow(Collections.treatmentProgramSessions, sessionId, {
      if (appointmentRef != null) 'appointment_ref': appointmentRef,
      if (status != null) 'status': status.dbValue,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Explosión de materiales MENSUAL: por cada insumo del plan, cantidad por
  /// sesión × nº de sesiones no canceladas. Para que atención a cliente reserve
  /// stock del mes.
  List<
      ({
        String name,
        String? inventoryItemId,
        double totalQuantity,
        double? unitCost,
        double? unitPrice,
      })> monthlyExplosion(String programId) {
    final sessions = listProgramSessions(programId)
        .where((s) => s.status != SessionStatus.cancelada)
        .length;
    return [
      for (final sup in listProgramSupplies(programId))
        (
          name: sup.name,
          inventoryItemId: sup.inventoryItemId,
          // Multidosis: la cantidad ya es la del mes (no se multiplica por
          // sesiones); consumibles por sesión sí se multiplican.
          totalQuantity:
              sup.isMonthly ? sup.quantityPerSession : sup.quantityPerSession * sessions,
          unitCost: sup.unitCost,
          unitPrice: sup.unitPrice,
        ),
    ];
  }

  // ------------- Reglas producto-por-categoría del protocolo (0076) -------------

  List<ProtocolProductRule> listProtocolProductRules(String? organizationId) =>
      _store
          .getAll(Collections.protocolProductRules)
          .map(ProtocolProductRule.fromJson)
          .where((r) =>
              organizationId == null || r.organizationId == organizationId)
          .toList()
        ..sort((a, b) {
          final c = a.category.compareTo(b.category);
          return c != 0 ? c : a.sortOrder.compareTo(b.sortOrder);
        });

  List<ProtocolProductRule> protocolRulesForCategory(
          String organizationId, KuraTag category) =>
      listProtocolProductRules(organizationId)
          .where((r) => r.category == category.dbValue)
          .toList();

  Future<void> saveProtocolProductRule(ProtocolProductRule rule) async {
    await _store.upsertRow(Collections.protocolProductRules, {
      ...rule.toJson(),
      'id': rule.id.isEmpty ? _uuid.v4() : rule.id,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteProtocolProductRule(String id) async {
    await _store.deleteRow(Collections.protocolProductRules, id);
  }

  /// RESOLUCIÓN unificada protocolo → producto. Para cada categoría del régimen
  /// (KuraTag), elige la(s) regla(s) cuya dimensión/rango calza con la medida de
  /// la herida (área/volumen) y devuelve el producto concreto + cantidad. Es la
  /// misma resolución para el armador del plan y el "sugerir del plan" del
  /// seguimiento. Enriquece costo/precio desde el inventario.
  List<ResolvedProtocolProduct> resolveProtocolProducts({
    required String organizationId,
    required Set<KuraTag> categories,
    double? areaCm2,
    double? volumeCm3,
    String? exudateLevel, // ExudadoCantidad.name
    String? zoneGroup, // ZoneGroup key
    bool? infectionSuspected,
    String? siteId,
  }) {
    final inv = {
      for (final it in listInventoryItems(
          organizationId: organizationId, siteId: siteId, activeOnly: false))
        it.id: it
    };
    final out = <ResolvedProtocolProduct>[];
    final seen = <String>{};
    for (final cat in categories) {
      // Reglas de la categoría que APLICAN a este caso.
      final matching = protocolRulesForCategory(organizationId, cat)
          .where((r) => r.inventoryItemId != null)
          .where((r) => r.appliesTo(
                areaCm2: areaCm2,
                volumeCm3: volumeCm3,
                exudateLevel: exudateLevel,
                zoneGroup: zoneGroup,
                infectionSuspected: infectionSuspected,
              ))
          .toList();
      if (matching.isEmpty) continue;
      // Gana la MÁS ESPECÍFICA (más condiciones); el comodín solo aplica si no
      // hubo match específico. Empate de especificidad → todas (p. ej. limpieza
      // = solución + gasa, ambas sin condiciones).
      final maxSpec =
          matching.map((r) => r.specificity).reduce((a, b) => a > b ? a : b);
      for (final r in matching.where((r) => r.specificity == maxSpec)) {
        if (!seen.add('${cat.dbValue}::${r.inventoryItemId}')) continue;
        final item = inv[r.inventoryItemId];
        if (item == null) continue;
        out.add(ResolvedProtocolProduct(
          category: cat.dbValue,
          inventoryItemId: item.id,
          name: item.name,
          quantity: r.quantityFor(areaCm2: areaCm2, volumeCm3: volumeCm3),
          unitCost: item.unitCost,
          unitPrice: item.unitPrice,
          currency: item.currency,
        ));
      }
    }
    return out;
  }

  // ---------------- Recomendaciones Kura+ ----------------

  Future<void> saveKuraRecommendation({
    required String consultationId,
    required String woundId,
    String? treatmentPlanId,
    required KuraEngineOutput output,
    required ClinicianDecision decision,
    String? clinicianNotes,
  }) async {
    final data = {
      'id': _uuid.v4(),
      'consultation_id': consultationId,
      'wound_id': woundId,
      'treatment_plan_id': treatmentPlanId,
      'model_version': output.modelVersion,
      'adjustments_version': output.adjustmentsVersion,
      'rules_version': output.rulesVersion,
      'prob_a': output.probabilities.entries.firstWhere((e) => e.key.code == 'A').value,
      'prob_b': output.probabilities.entries.firstWhere((e) => e.key.code == 'B').value,
      'prob_c': output.probabilities.entries.firstWhere((e) => e.key.code == 'C').value,
      'dominant_scenario': output.dominantScenario.code,
      'commercial_phenotype': output.dominantScenario.commercialPhenotype,
      'regimen': output.regimen.map((r) => r.toJson()).toList(),
      'interconsultas': output.interconsultas.map((i) => i.toJson()).toList(),
      'alertas': output.alertas,
      'debug_features': output.debugFeatures,
      'debug_raw_scores': output.debugRawScores,
      'clinician_decision': decision.name,
      'clinician_decision_at': DateTime.now().toIso8601String(),
      'clinician_notes': clinicianNotes,
      'generated_at': output.generatedAt.toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    };
    await _store.insertRow(Collections.kuraRecommendations, data);
  }

  List<Map<String, dynamic>> listRecommendationsForWound(String woundId) => _store
      .getAll(Collections.kuraRecommendations)
      .where((r) => r['wound_id'] == woundId)
      .toList();

  // ---------------- Checkpoints Sheehan ----------------

  Future<void> saveSheehanCheckpoint(Map<String, dynamic> data) async {
    final row = Map<String, dynamic>.from(data);
    row['id'] = row['id'] ?? _uuid.v4();
    row['created_at'] = row['created_at'] ?? DateTime.now().toIso8601String();
    await _store.insertRow(Collections.sheehanCheckpoints, row);
  }

  List<Map<String, dynamic>> listSheehanCheckpointsForWound(String woundId) => _store
      .getAll(Collections.sheehanCheckpoints)
      .where((c) => c['wound_id'] == woundId)
      .toList();

  // ---------------- Auditoria ----------------
  // La auditoria de patients/wounds/consultations/measurements/
  // treatment_plans/kura_recommendations/staff/profiles la genera
  // EXCLUSIVAMENTE el trigger AFTER INSERT/UPDATE/DELETE de Postgres
  // (audit_trigger_fn en 0002_triggers_and_functions.sql), que corre como
  // SECURITY DEFINER. Ningun flujo clinico de la app debe insertar
  // manualmente en audit_log: la tabla solo tiene politica de SELECT para
  // admin (audit_log_admin_select) y deliberadamente NO tiene politica de
  // INSERT, para que un cliente no pueda falsificar la bitacora. Por eso
  // se eliminaron los antiguos metodos logAudit()/listAuditLog() de este
  // repositorio (y sus 3 llamadas desde la UI): un INSERT directo del
  // cliente a audit_log siempre sera rechazado por RLS con 403. Si se
  // necesita registrar una accion adicional, se debe agregar/ajustar el
  // trigger en Postgres, nunca una llamada manual desde el cliente.
}

/// Resultado del alta de un usuario con login (createUserWithLogin). En
/// Supabase, [tempPassword] es una contrasena temporal generada por la Edge
/// Function para compartir con el usuario cuando no hay SMTP configurado; en
/// modo demo local es null (no hay Auth real).
class CreatedUser {
  final String uid;
  final String email;
  final String? tempPassword;
  final AppRole role;

  const CreatedUser({
    required this.uid,
    required this.email,
    required this.tempPassword,
    required this.role,
  });
}

/// Estado de la conexión de Acuity de un centro (sin exponer la API key: solo
/// el user id, los últimos 4 de la key y si los webhooks quedaron registrados).
class AcuityConfigStatus {
  final String userId;
  final String keyLast4;
  final bool webhooksRegistered;
  const AcuityConfigStatus({
    required this.userId,
    required this.keyLast4,
    required this.webhooksRegistered,
  });
}

/// Una fila cruda del CSV de importacion del catalogo (Configuracion >
/// catalogo de la nota de seguimiento). `activo` ya viene parseado a bool
/// (columna CSV "activo" con valores "true"/"false"/"1"/"0"/"si"/"no"; el
/// parseo tolerante vive en la pantalla que lee el archivo, no aqui).
class NoteOptionImportRow {
  final String seccion;
  final String concepto;
  final bool activo;

  const NoteOptionImportRow({
    required this.seccion,
    required this.concepto,
    required this.activo,
  });
}

/// Resumen de una importacion masiva (bulkImportNoteOptions), mostrado al
/// admin en un dialogo tras cargar el CSV.
class NoteOptionImportSummary {
  final int added;
  final int updated;
  final int skipped;
  final List<String> errors;

  const NoteOptionImportSummary({
    required this.added,
    required this.updated,
    required this.skipped,
    required this.errors,
  });
}
