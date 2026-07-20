/// Cita de Acuity Scheduling, tal como queda espejada en la tabla
/// public.appointments de Supabase (ver 0016_acuity_agenda.sql). La app solo
/// LEE estas filas; las altas/cambios pasan por la Edge Function acuity-proxy.
class Appointment {
  final int id;
  final String? staffId;
  final String? appointmentType;
  final String firstName;
  final String lastName;
  final String? email;
  final String? phone;
  final DateTime? datetime; // en hora local del dispositivo
  final String status; // scheduled | rescheduled | canceled
  final String? patientId; // paciente de KuraTracker vinculado (0018), si existe
  // Ruta en el bucket privado acuity-intake de la foto de la herida del
  // formulario de admisión (0019). Sentinelas 'no-photo'/'error' = sin foto
  // mostrable. Ver hasIntakePhoto.
  final String? intakePhotoPath;
  // Objeto COMPLETO de Acuity tal cual (columna appointments.raw). Contiene
  // todos los campos que Acuity devuelve (notas, formularios de admisión,
  // ubicación, pago, etiquetas, metadatos...), aunque solo algunos tengan
  // columna propia. La pantalla de detalle lo usa para mostrar "todos los
  // campos".
  final Map<String, dynamic>? raw;

  const Appointment({
    required this.id,
    required this.staffId,
    required this.appointmentType,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.datetime,
    required this.status,
    this.patientId,
    this.intakePhotoPath,
    this.raw,
  });

  String get patientName => '$firstName $lastName'.trim();
  bool get isCanceled => status == 'canceled';

  /// true si hay una foto de herida guardada mostrable (ruta real, no sentinela).
  bool get hasIntakePhoto {
    final p = intakePhotoPath;
    return p != null && p.contains('/') && p != 'no-photo' && p != 'error';
  }

  factory Appointment.fromMap(Map<String, dynamic> m) {
    final dt = m['datetime'];
    return Appointment(
      id: (m['id'] as num).toInt(),
      staffId: m['staff_id'] as String?,
      appointmentType: m['appointment_type'] as String?,
      firstName: (m['first_name'] ?? '') as String,
      lastName: (m['last_name'] ?? '') as String,
      email: m['email'] as String?,
      phone: m['phone'] as String?,
      datetime: dt == null ? null : DateTime.tryParse(dt.toString())?.toLocal(),
      status: (m['status'] ?? 'scheduled') as String,
      patientId: m['patient_id'] as String?,
      intakePhotoPath: m['intake_photo_path'] as String?,
      raw: m['raw'] is Map ? Map<String, dynamic>.from(m['raw'] as Map) : null,
    );
  }
}
