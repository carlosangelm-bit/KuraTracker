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
}

final acuityServiceProvider = Provider<AcuityService>((ref) => AcuityService());
