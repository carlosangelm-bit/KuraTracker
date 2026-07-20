// _shared/acuity_patient.ts — Alta automática de pacientes a partir de citas de
// Acuity. Lo usan acuity-webhook (citas nuevas) y acuity-backfill (histórico).
//
// Contrato: dado el dueño de la cita (Kurador activo mapeado) y los datos del
// cliente en Acuity, devuelve el patient_id de KuraTracker, creándolo si no
// existe y asignándolo al Kurador (para que aparezca en su lista de pacientes).
//
// Deduplicación (ver 0018_acuity_auto_patient.sql):
//   1) por email dentro del centro (llave estable; Acuity siempre trae email);
//   2) si no hay email, por nombre normalizado dentro del centro (best-effort);
//   3) si no hay coincidencia, se crea.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export interface PatientFromAppointment {
  organizationId: string;
  staffId: string;
  firstName: string;
  lastName: string;
  email: string | null;
}

/// Devuelve el patient_id (creándolo/asignándolo si hace falta) o null si no se
/// pudo crear (p.ej. error de DB); el llamador puede guardar la cita igual con
/// patient_id null.
export async function resolveOrCreatePatient(
  db: SupabaseClient,
  a: PatientFromAppointment,
): Promise<string | null> {
  const fullName = `${a.firstName} ${a.lastName}`.trim() || "Paciente sin nombre";
  const email = (a.email ?? "").trim().toLowerCase() || null;

  const patientId = await findExistingPatient(db, a.organizationId, email, fullName);
  const resolved = patientId ?? (await createPatient(db, a.organizationId, fullName, email));
  if (resolved) await ensureAssignment(db, a.staffId, resolved);
  return resolved;
}

async function findExistingPatient(
  db: SupabaseClient,
  organizationId: string,
  email: string | null,
  fullName: string,
): Promise<string | null> {
  if (email) {
    const { data } = await db
      .from("patients")
      .select("id")
      .eq("organization_id", organizationId)
      .eq("acuity_email", email)
      .maybeSingle();
    if (data) return data.id as string;
    return null; // con email, no se cae al match por nombre (email es la llave)
  }
  // Sin email: best-effort por nombre exacto (case-insensitive) en el centro.
  const { data } = await db
    .from("patients")
    .select("id")
    .eq("organization_id", organizationId)
    .ilike("full_name", fullName)
    .limit(1)
    .maybeSingle();
  return data ? (data.id as string) : null;
}

async function createPatient(
  db: SupabaseClient,
  organizationId: string,
  fullName: string,
  email: string | null,
): Promise<string | null> {
  const folio = await nextPatientFolio(db);
  const { data, error } = await db
    .from("patients")
    .insert({
      folio,
      full_name: fullName,
      organization_id: organizationId,
      acuity_email: email,
      background_notes: "Alta automática desde Acuity Scheduling.",
      is_active: true,
    })
    .select("id")
    .single();
  if (error || !data) return null;
  return data.id as string;
}

// Asignación Kurador <-> paciente (idempotente): sin ella, el clínico no ve al
// paciente en su lista (staff_patient_assignments).
async function ensureAssignment(
  db: SupabaseClient,
  staffId: string,
  patientId: string,
): Promise<void> {
  const { data } = await db
    .from("staff_patient_assignments")
    .select("staff_id")
    .eq("staff_id", staffId)
    .eq("patient_id", patientId)
    .maybeSingle();
  if (!data) {
    await db
      .from("staff_patient_assignments")
      .insert({ staff_id: staffId, patient_id: patientId });
  }
}

// Folio PA<year>-NNNN (mismo formato que usa la app para pacientes; prefijo PA
// para distinguir los originados en Acuity de los EXP creados manualmente).
async function nextPatientFolio(db: SupabaseClient): Promise<string> {
  const year = new Date().getFullYear();
  const { data } = await db.from("patients").select("folio");
  const count = (data ?? []).filter(
    (r: { folio: string | null }) => (r.folio ?? "").startsWith(`PA${year}`),
  ).length;
  return `PA${year}-${String(count + 1).padStart(4, "0")}`;
}
