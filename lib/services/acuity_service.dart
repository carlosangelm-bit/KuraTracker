import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../models/appointment.dart';

/// Cliente de la agenda de Acuity Scheduling.
///
/// - LECTURA en tiempo real: stream de la tabla `appointments` de Supabase
///   (la RLS ya la acota por rol: clínico ve las suyas, admin las del centro).
/// - ESCRITURA / disponibilidad: a través de la Edge Function `acuity-proxy`
///   (las credenciales de Acuity viven en el servidor, nunca en la app).
///
/// Solo funciona en modo Supabase; en la demo local no hay Edge Functions
/// (ver [isAvailable]).
class AcuityService {
  bool get isAvailable => AppConfig.isSupabaseConfigured;

  SupabaseClient get _sb => Supabase.instance.client;

  /// Citas (Acuity) en un rango de fechas, en una sola lectura. Se usa para
  /// VALIDAR EMPALMES al armar el plan de tratamiento (marcar en rojo las
  /// sesiones que chocan con el calendario del especialista). Devuelve vacío si
  /// no hay Supabase configurado (demo).
  Future<List<Appointment>> appointmentsBetween(
      DateTime from, DateTime to) async {
    if (!isAvailable) return const [];
    final rows = await _sb
        .from('appointments')
        .select()
        .gte('datetime', from.toUtc().toIso8601String())
        .lte('datetime', to.toUtc().toIso8601String());
    return (rows as List)
        .map((r) => Appointment.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Citas en tiempo real (RLS aplica el aislamiento por rol/centro).
  Stream<List<Appointment>> watchAppointments() {
    return _sb
        .from('appointments')
        .stream(primaryKey: ['id'])
        .order('datetime')
        .map((rows) => rows.map(Appointment.fromMap).toList());
  }

  Future<dynamic> _proxy(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Map<String, dynamic>? payload,
  }) async {
    final res = await _sb.functions.invoke('acuity-proxy', body: {
      'method': method,
      'path': path,
      if (query != null) 'query': query,
      if (payload != null) 'payload': payload,
    });
    return res.data;
  }

  // --- Disponibilidad (para el flujo de nueva cita / reagendar) ---
  Future<List<dynamic>> appointmentTypes() async =>
      (await _proxy('GET', '/appointment-types')) as List<dynamic>? ?? const [];

  Future<List<dynamic>> availabilityDates(int typeId, String month) async =>
      (await _proxy('GET', '/availability/dates',
          query: {'appointmentTypeID': typeId, 'month': month})) as List<dynamic>? ??
      const [];

  Future<List<dynamic>> availabilityTimes(int typeId, String date) async =>
      (await _proxy('GET', '/availability/times',
          query: {'appointmentTypeID': typeId, 'date': date})) as List<dynamic>? ??
      const [];

  // --- Gestión de citas ---
  Future<void> createAppointment({
    required int appointmentTypeID,
    required String datetime,
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    await _proxy('POST', '/appointments', payload: {
      'appointmentTypeID': appointmentTypeID,
      'datetime': datetime,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
    });
  }

  /// Crea una cita en Acuity forzando el horario (admin=true, salta la
  /// validación de disponibilidad) — para agendar en lote las sesiones del plan
  /// de tratamiento. Devuelve el objeto de la cita creada (incluye `id`).
  /// [calendarID] agenda en el calendario del Kurador; [phone] habilita
  /// recordatorios por SMS/WhatsApp del lado de Acuity.
  Future<Map<String, dynamic>> createAppointmentAdmin({
    required int appointmentTypeID,
    required String datetime,
    required String firstName,
    required String lastName,
    required String email,
    int? calendarID,
    String? phone,
  }) async {
    final data = await _proxy(
      'POST',
      '/appointments',
      query: {'admin': true},
      payload: {
        'appointmentTypeID': appointmentTypeID,
        'datetime': datetime,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        if (calendarID != null) 'calendarID': calendarID,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      },
    );
    return (data as Map?)?.cast<String, dynamic>() ?? const {};
  }

  /// Signed URL (1 h) para mostrar la foto de herida guardada en el bucket
  /// privado acuity-intake (ver 0019). Devuelve null si no hay ruta válida o
  /// falla la firma.
  Future<String?> intakePhotoUrl(String path) async {
    if (!isAvailable) return null;
    try {
      return await _sb.storage.from('acuity-intake').createSignedUrl(path, 3600);
    } catch (_) {
      return null;
    }
  }

  Future<void> cancel(int id) async => _proxy('PUT', '/appointments/$id/cancel');

  Future<void> reschedule(int id, String datetime) async =>
      _proxy('PUT', '/appointments/$id/reschedule', payload: {'datetime': datetime});

  // --- Configuración por centro (Fase 2b) ---

  /// Prueba la conexión con Acuity usando las credenciales del centro del
  /// usuario (vía el proxy). Devuelve null si OK, o un mensaje de error.
  Future<String?> testConnection() async {
    try {
      await _proxy('GET', '/me');
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  /// Registra en Acuity los webhooks del centro, apuntando a la Edge Function
  /// con el `?org=` de este centro (para enrutamiento/validación por centro).
  Future<void> registerWebhooks(String organizationId) async {
    final target =
        '${AppConfig.supabaseUrl}/functions/v1/acuity-webhook?org=$organizationId';
    const events = [
      'appointment.scheduled',
      'appointment.rescheduled',
      'appointment.canceled',
      'appointment.changed',
    ];
    for (final e in events) {
      await _proxy('POST', '/webhooks', payload: {'event': e, 'target': target});
    }
  }

  /// Mapea los calendarios de Acuity del centro a su personal (por email).
  Future<dynamic> syncCalendars(String organizationId) async {
    final res = await _sb.functions.invoke('acuity-sync-calendars',
        body: {'organizationId': organizationId});
    return res.data;
  }
}

final acuityServiceProvider = Provider<AcuityService>((ref) => AcuityService());
