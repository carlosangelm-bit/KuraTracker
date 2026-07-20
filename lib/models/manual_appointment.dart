/// Cita gestionada manualmente dentro de KuraTracker (centros con
/// scheduling_mode = 'manual', ver 0020_manual_scheduling.sql). A diferencia de
/// [Appointment] (espejo de Acuity, solo-lectura), estas se crean/editan/cancelan
/// desde la app.
class ManualAppointment {
  final String id;
  final String organizationId;
  final String? staffId;
  final String? patientId;
  final String? title;
  final DateTime datetime; // hora local
  final DateTime? endTime;
  final String? notes;
  final String status; // scheduled | canceled | completed
  // Paridad con Acuity ("Consulta a domicilio"), ver 0023.
  final String? address; // dirección donde se recibirá el tratamiento
  final String? contactName; // contacto que recibirá al especialista
  final String? contactPhone;
  final String? photoPath; // ruta en bucket intake-photos o data URL (demo)

  const ManualAppointment({
    required this.id,
    required this.organizationId,
    required this.staffId,
    required this.patientId,
    required this.title,
    required this.datetime,
    required this.endTime,
    required this.notes,
    required this.status,
    this.address,
    this.contactName,
    this.contactPhone,
    this.photoPath,
  });

  bool get isCanceled => status == 'canceled';
  bool get hasPhoto => (photoPath ?? '').isNotEmpty;

  factory ManualAppointment.fromJson(Map<String, dynamic> m) {
    final dt = m['datetime'];
    final end = m['end_time'];
    return ManualAppointment(
      id: m['id'] as String,
      organizationId: m['organization_id'] as String,
      staffId: m['staff_id'] as String?,
      patientId: m['patient_id'] as String?,
      title: m['title'] as String?,
      datetime: DateTime.tryParse('$dt')?.toLocal() ?? DateTime.now(),
      endTime: end == null ? null : DateTime.tryParse('$end')?.toLocal(),
      notes: m['notes'] as String?,
      status: (m['status'] ?? 'scheduled') as String,
      address: m['address'] as String?,
      contactName: m['contact_name'] as String?,
      contactPhone: m['contact_phone'] as String?,
      photoPath: m['photo_path'] as String?,
    );
  }
}
