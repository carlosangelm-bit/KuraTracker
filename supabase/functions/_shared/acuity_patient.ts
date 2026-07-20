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
//
// Enriquecimiento del expediente (extractEnrichment): además del nombre/email,
// se mapean los campos del formulario de admisión de Acuity ("Consulta a
// domicilio") al expediente:
//   - "nombre del contacto que recibirá al especialista" -> caregiver_name
//   - "teléfono de la persona que recibirá al especialista" -> caregiver_phone
//   - "dirección donde se recibirá el tratamiento" -> background_notes
//   - teléfono del paciente / notas / foto de la herida / demás respuestas ->
//     background_notes (texto legible, para no perder nada).
// El emparejamiento es por SUBCADENA del texto de la pregunta (normalizado sin
// acentos), tolerante a variaciones menores; lo que no reconoce se vuelca igual
// como "Pregunta: respuesta" en background_notes.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

export const STUB_NOTE = "Alta automática desde Acuity Scheduling.";

export interface Enrichment {
  caregiverName: string | null;
  caregiverPhone: string | null;
  hasCaregiver: boolean;
  backgroundNotes: string;
}

export interface PatientFromAppointment {
  organizationId: string;
  staffId: string;
  firstName: string;
  lastName: string;
  email: string | null;
  enrichment?: Enrichment;
}

interface ExistingPatient {
  id: string;
  background_notes: string | null;
  caregiver_name: string | null;
  caregiver_phone: string | null;
}

/// Devuelve el patient_id (creándolo/asignándolo/enriqueciéndolo si hace falta)
/// o null si no se pudo crear.
export async function resolveOrCreatePatient(
  db: SupabaseClient,
  a: PatientFromAppointment,
): Promise<string | null> {
  const fullName = `${a.firstName} ${a.lastName}`.trim() || "Paciente sin nombre";
  const email = (a.email ?? "").trim().toLowerCase() || null;

  const existing = await findExistingPatient(db, a.organizationId, email, fullName);
  let id: string | null;
  if (existing) {
    id = existing.id;
    if (a.enrichment) await enrichIfStub(db, existing, a.enrichment);
  } else {
    id = await createPatient(db, a.organizationId, fullName, email, a.enrichment);
  }
  if (id) await ensureAssignment(db, a.staffId, id);
  return id;
}

async function findExistingPatient(
  db: SupabaseClient,
  organizationId: string,
  email: string | null,
  fullName: string,
): Promise<ExistingPatient | null> {
  const cols = "id, background_notes, caregiver_name, caregiver_phone";
  if (email) {
    const { data } = await db
      .from("patients")
      .select(cols)
      .eq("organization_id", organizationId)
      .eq("acuity_email", email)
      .maybeSingle();
    return (data as ExistingPatient | null) ?? null; // con email, no cae al nombre
  }
  const { data } = await db
    .from("patients")
    .select(cols)
    .eq("organization_id", organizationId)
    .ilike("full_name", fullName)
    .limit(1)
    .maybeSingle();
  return (data as ExistingPatient | null) ?? null;
}

async function createPatient(
  db: SupabaseClient,
  organizationId: string,
  fullName: string,
  email: string | null,
  enr?: Enrichment,
): Promise<string | null> {
  const folio = await nextPatientFolio(db);
  const { data, error } = await db
    .from("patients")
    .insert({
      folio,
      full_name: fullName,
      organization_id: organizationId,
      acuity_email: email,
      background_notes: enr?.backgroundNotes ?? STUB_NOTE,
      caregiver_name: enr?.caregiverName ?? null,
      caregiver_phone: enr?.caregiverPhone ?? null,
      has_identified_caregiver: enr?.hasCaregiver ?? false,
      is_active: true,
    })
    .select("id")
    .single();
  if (error || !data) return null;
  return data.id as string;
}

// Enriquece SOLO si el expediente sigue "en blanco" (nota stub/vacía o campos
// de cuidador vacíos): así no se pisa nada que el clínico haya editado.
async function enrichIfStub(
  db: SupabaseClient,
  row: ExistingPatient,
  enr: Enrichment,
): Promise<void> {
  const patch: Record<string, unknown> = {};
  const bn = (row.background_notes ?? "").trim();
  if ((bn === "" || bn === STUB_NOTE) && enr.backgroundNotes && enr.backgroundNotes !== STUB_NOTE) {
    patch.background_notes = enr.backgroundNotes;
  }
  if (!row.caregiver_name && enr.caregiverName) {
    patch.caregiver_name = enr.caregiverName;
    patch.has_identified_caregiver = true;
  }
  if (!row.caregiver_phone && enr.caregiverPhone) {
    patch.caregiver_phone = enr.caregiverPhone;
    patch.has_identified_caregiver = true;
  }
  if (Object.keys(patch).length > 0) {
    await db.from("patients").update(patch).eq("id", row.id);
  }
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

// Folio PA<year>-NNNN (mismo formato que la app; prefijo PA para distinguir los
// originados en Acuity de los EXP creados manualmente).
async function nextPatientFolio(db: SupabaseClient): Promise<string> {
  const year = new Date().getFullYear();
  const { data } = await db.from("patients").select("folio");
  const count = (data ?? []).filter(
    (r: { folio: string | null }) => (r.folio ?? "").startsWith(`PA${year}`),
  ).length;
  return `PA${year}-${String(count + 1).padStart(4, "0")}`;
}

// --------------------------------------------------------------------------
// Extracción de campos del expediente desde el objeto de cita de Acuity.
// --------------------------------------------------------------------------

function norm(s: string): string {
  return s
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .trim();
}

/// Mapea los datos de la cita (incluido su formulario de admisión) a los campos
/// del expediente. Robusto a citas sin formulario: devuelve al menos el teléfono
/// y las notas si existen.
export function extractEnrichment(appt: Record<string, unknown>): Enrichment {
  const lines: string[] = [STUB_NOTE];
  let caregiverName: string | null = null;
  let caregiverPhone: string | null = null;

  const patientPhone = str(appt.phone);
  if (patientPhone) lines.push(`Teléfono del paciente: ${patientPhone}`);

  const notes = str(appt.notes);
  if (notes) lines.push(`Notas de la cita: ${notes}`);

  const location = str(appt.location);
  if (location) lines.push(`Ubicación: ${location}`);

  const forms = (appt.forms as unknown[]) ?? [];
  for (const f of forms) {
    if (!isRecord(f)) continue;
    const values = (f.values as unknown[]) ?? [];
    for (const v of values) {
      if (!isRecord(v)) continue;
      const label = str(v.name);
      const value = str(v.value);
      if (!label || !value) continue;
      const n = norm(label);
      if (n.includes("nombre del contacto")) {
        caregiverName = value;
      } else if (
        n.includes("numero telefonico de la persona") ||
        n.includes("telefono de la persona") ||
        (n.includes("telefon") && n.includes("persona"))
      ) {
        caregiverPhone = value;
      } else if (n.includes("direccion")) {
        lines.push(`Domicilio de tratamiento: ${value}`);
      } else if (n.includes("foto")) {
        lines.push(`Foto de la herida: ${value}`);
      } else {
        lines.push(`${label}: ${value}`);
      }
    }
  }

  return {
    caregiverName,
    caregiverPhone,
    hasCaregiver: caregiverName != null || caregiverPhone != null,
    backgroundNotes: lines.join("\n"),
  };
}

function str(v: unknown): string | null {
  if (v == null) return null;
  const s = String(v).trim();
  return s === "" ? null : s;
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null;
}
