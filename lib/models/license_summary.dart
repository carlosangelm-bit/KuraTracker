/// Estado de licencias de un centro para el panel del admin (`AdminHomeScreen`).
/// Se calcula en el repo desde org_entitlements + membresías + perfiles (mismo
/// criterio que las funciones del servidor consumed_clinical_seats/admin_slots,
/// que son la fuente de verdad del TOPE; esto es la vista para MOSTRAR).
library;

/// Techo del autoservicio: hasta aquí el admin puede comprar solo; por encima,
/// "Solicitar más licencias" (formulario a la plataforma).
const int kSelfServiceSeatCeiling = 5;

/// Tope de pacientes del plan gratuito (para el contador de esa etapa).
const int kFreePlanPatientCap = 5;

enum LicenseState {
  /// Contadores con holgura.
  holgado,

  /// 0 asientos clínicos disponibles: "Agregar licencias" pasa a acción principal.
  lleno,

  /// En el techo del autoservicio: ya no se compra solo → "Solicitar más".
  techoAutoservicio,

  /// Suscripción vencida (past_due): banda de gracia; se cierra el alta, no la consulta.
  impago,

  /// Plan gratuito: contador de pacientes restantes en vez de licencias.
  gratuito,
}

/// Un contador "usado de contratado". [contracted] < 0 = sin límite / no aplica.
class LicenseCounter {
  final int used;
  final int contracted;
  const LicenseCounter({required this.used, required this.contracted});

  bool get unlimited => contracted < 0;
  int get available => unlimited ? -1 : (contracted - used);
  bool get full => !unlimited && available <= 0;
}

class LicenseSummary {
  /// Asientos clínicos (rol clínico, no exentos) usados vs. contratados.
  final LicenseCounter clinicalSeats;

  /// Cupos administrativos (solo-admin, no exentos) usados vs. incluidos
  /// (3 con module:admin, 0 sin él).
  final LicenseCounter adminSlots;

  /// Cuidadores activos: no consumen licencia (se muestra explícito).
  final int caregivers;

  /// Protocolo Kura+: asignadas (perfiles con premium_enabled) vs. compradas
  /// (seat:protocolo). purchased < 0 = el centro no tiene el add-on.
  final LicenseCounter protocolo;

  /// Plan del centro ('gratuito' | 'basico').
  final String plan;

  /// Suscripción vencida (algún derecho en past_due).
  final bool pastDue;

  /// Pacientes creados (para el contador del plan gratuito).
  final int patientsUsed;

  const LicenseSummary({
    required this.clinicalSeats,
    required this.adminSlots,
    required this.caregivers,
    required this.protocolo,
    required this.plan,
    required this.pastDue,
    required this.patientsUsed,
  });

  bool get isFreePlan => plan == 'gratuito';
  bool get hasProtocoloAddon => !protocolo.unlimited && protocolo.contracted >= 0;

  /// Estado del panel. Precedencia: impago manda sobre todo (se cobra primero);
  /// luego el plan gratuito es su propia etapa. Con holgura → holgado. LLENO (0
  /// disponibles): si está en el techo del autoservicio (≥5 asientos contratados)
  /// ya no se compra solo → techoAutoservicio; si no, lleno (aún cabe autoservicio).
  /// "4 de 5" es holgado; "5 de 5" es el techo.
  LicenseState get state {
    if (pastDue) return LicenseState.impago;
    if (isFreePlan) return LicenseState.gratuito;
    if (!clinicalSeats.full) return LicenseState.holgado;
    if (clinicalSeats.contracted >= kSelfServiceSeatCeiling) {
      return LicenseState.techoAutoservicio;
    }
    return LicenseState.lleno;
  }
}
