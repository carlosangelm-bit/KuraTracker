// admin-create-user — Crea un usuario de KuraTracker CON cuenta de acceso
// (login), a solicitud de un admin de centro o del master, desde la app.
//
// Por qué una Edge Function: crear una cuenta en Supabase Auth requiere la
// SERVICE ROLE (admin.createUser), que JAMÁS puede vivir en el cliente. La app
// (Flutter) invoca esta función con su JWT (functions.invoke lo adjunta), aquí
// se verifica que el llamador sea admin/master y se hace el alta con el rol de
// servicio. El profile lo crea el trigger handle_new_auth_user() a partir de
// user_metadata (role/full_name/organization_id); esta función lo refuerza y,
// para clínicos, crea también su registro en `staff`.
//
// Reglas de autorización:
//   - master: puede crear en CUALQUIER centro (organizationId del body).
//   - admin : solo en SU propio centro (se ignora el organizationId del body y
//             se fuerza al del llamador).
//   - role permitido: 'admin' | 'clinico' (nunca 'master' por esta vía).
//
// SMTP: si no está configurado el correo en Supabase, no se puede enviar la
// invitación; por eso se crea con email_confirm=true y una contraseña temporal
// que se DEVUELVE en la respuesta para que el admin la comparta. Cuando haya
// SMTP, el usuario puede usar "olvidé mi contraseña" para fijar la suya.
//
// Deploy:  supabase functions deploy admin-create-user   (con verify_jwt, default)

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req) => {
  // Cliente con service role: hace los writes reales (bypass de RLS). También
  // se usa para resolver al llamador desde su JWT (auth.getUser).
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 1) Resolver e identificar al llamador (por su JWT).
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "No autenticado." }, 401);
  const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
  if (callerErr || !caller.user) return json({ error: "Sesión inválida." }, 401);

  const { data: callerProfile } = await admin
    .from("profiles")
    .select("role, organization_id")
    .eq("id", caller.user.id)
    .maybeSingle();
  if (!callerProfile) return json({ error: "Perfil del llamador no encontrado." }, 403);

  const isMaster = callerProfile.role === "master";
  const isAdmin = callerProfile.role === "admin";
  if (!isMaster && !isAdmin) {
    return json({ error: "No autorizado (requiere admin o master)." }, 403);
  }

  // 2) Parsear y validar el cuerpo.
  const body = await req.json().catch(() => ({} as Record<string, unknown>));
  const email = String(body.email ?? "").trim().toLowerCase();
  const fullName = String(body.fullName ?? "").trim();
  const role = String(body.role ?? "clinico");
  const phone = body.phone ? String(body.phone).trim() : null;
  const cedulaProfesional = body.cedulaProfesional ? String(body.cedulaProfesional).trim() : null;
  const primarySiteId = body.primarySiteId ? String(body.primarySiteId) : null;
  const roleTitle = String(body.roleTitle ?? "Kurador").trim() || "Kurador";

  if (!email || !fullName) return json({ error: "email y fullName son obligatorios." }, 400);
  // 'cuidador' (Fase 3): rol restringido con cuenta propia; NO se le crea fila de
  // staff (su acceso es solo lectura vía caregiver_patient_assignments, ver 0042).
  if (role !== "admin" && role !== "clinico" && role !== "cuidador") {
    return json({ error: "role debe ser 'admin', 'clinico' o 'cuidador'." }, 400);
  }

  // 3) Acotar la organización según el rol del llamador.
  let organizationId: string;
  if (isMaster) {
    organizationId = String(body.organizationId ?? "");
    if (!organizationId) return json({ error: "organizationId es obligatorio para master." }, 400);
  } else {
    // admin: siempre su propio centro, sin importar lo que venga en el body.
    organizationId = callerProfile.organization_id as string;
  }

  // 4) Crear la cuenta en Auth. El trigger handle_new_auth_user() creará el
  //    profile leyendo role/full_name/organization_id de user_metadata.
  const tempPassword = genPassword();
  const { data: createdUser, error: createErr } = await admin.auth.admin.createUser({
    email,
    password: tempPassword,
    email_confirm: true,
    user_metadata: { role, full_name: fullName, organization_id: organizationId },
  });
  if (createErr || !createdUser.user) {
    const msg = createErr?.message ?? "desconocido";
    const already = /registered|already/i.test(msg);
    return json(
      { error: already ? "Ya existe un usuario con ese correo." : `No se pudo crear la cuenta: ${msg}` },
      already ? 409 : 400,
    );
  }
  const uid = createdUser.user.id;

  // 5) Reforzar el profile (el trigger ya lo creó; se completan phone/is_active
  //    y se re-afirman role/org por si el trigger no estuviera presente).
  const { error: profileErr } = await admin.from("profiles").upsert({
    id: uid,
    role,
    full_name: fullName,
    email,
    phone,
    organization_id: organizationId,
    is_active: true,
  });
  if (profileErr) {
    return json({ error: `Cuenta creada pero falló el perfil: ${profileErr.message}`, uid }, 500);
  }

  // 6) Registro de personal sanitario (staff). Siempre para 'clinico'; para
  //    'admin' solo si se pide explícitamente (createStaff=true).
  let staffId: string | null = null;
  if (role === "clinico" || body.createStaff === true) {
    staffId = await createStaffRow(admin, {
      organizationId,
      profileId: uid,
      fullName,
      roleTitle: role === "clinico" ? roleTitle : "Administrador",
      cedulaProfesional,
      primarySiteId,
    });
  }

  return json({ uid, email, tempPassword, role, organizationId, staffId });
});

// Crea la fila de staff generando el folio K<year>-NNNN (mismo formato que
// DataRepository.createStaff en la app). El folio es `unique not null` sin
// default en la columna, por lo que hay que proveerlo.
async function createStaffRow(
  admin: ReturnType<typeof createClient>,
  s: {
    organizationId: string;
    profileId: string;
    fullName: string;
    roleTitle: string;
    cedulaProfesional: string | null;
    primarySiteId: string | null;
  },
): Promise<string | null> {
  const year = new Date().getFullYear();
  const { data: existing } = await admin.from("staff").select("folio");
  const countThisYear = (existing ?? []).filter(
    (r: { folio: string | null }) => (r.folio ?? "").startsWith(`K${year}`),
  ).length;
  const folio = `K${year}-${String(countThisYear + 1).padStart(4, "0")}`;

  const { data, error } = await admin
    .from("staff")
    .insert({
      organization_id: s.organizationId,
      profile_id: s.profileId,
      folio,
      full_name: s.fullName,
      role_title: s.roleTitle,
      cedula_profesional: s.cedulaProfesional,
      primary_site_id: s.primarySiteId,
      is_active: true,
    })
    .select("id")
    .single();
  if (error) return null;
  return data.id as string;
}

// Contraseña temporal legible pero con suficiente entropía (12 chars).
function genPassword(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789";
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return Array.from(bytes, (b) => chars[b % chars.length]).join("");
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
