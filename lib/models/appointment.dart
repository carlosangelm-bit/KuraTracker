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
  });

  String get patientName => '$firstName $lastName'.trim();
  bool get isCanceled => status == 'canceled';

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
    );
  }
}
