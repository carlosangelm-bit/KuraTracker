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

// CORS: la función se llama desde el navegador (app.kuramas.com) a un origen
// distinto (supabase.co), así que hay que responder el preflight OPTIONS y
// enviar las cabeceras en TODAS las respuestas; si no, el navegador bloquea la
// llamada con "Failed to fetch".
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  // Preflight CORS: responder ANTES de cualquier auth (el OPTIONS no lleva JWT).
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS });
  }

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
    .select("role, roles, organization_id")
    .eq("id", caller.user.id)
    .maybeSingle();
  if (!callerProfile) return json({ error: "Perfil del llamador no encontrado." }, 403);

  // Roles como CONJUNTO (0098): un admin puede ser {admin} o {admin,clinico}, un
  // master es {master}. Se decide por pertenencia al conjunto, no por el espejo
  // escalar `role` (que por precedencia podría no reflejar todos los roles).
  const callerRoles: string[] = Array.isArray(callerProfile.roles)
    ? callerProfile.roles.map((r: unknown) => String(r))
    : (callerProfile.role ? [String(callerProfile.role)] : []);
  const isMaster = callerRoles.includes("master");
  const isAdmin = callerRoles.includes("admin");
  if (!isMaster && !isAdmin) {
    return json({ error: "No autorizado (requiere admin o master)." }, 403);
  }

  // 2) Parsear y validar el cuerpo.
  const body = await req.json().catch(() => ({} as Record<string, unknown>));
  const email = String(body.email ?? "").trim().toLowerCase();
  const fullName = String(body.fullName ?? "").trim();
  const phone = body.phone ? String(body.phone).trim() : null;
  const cedulaProfesional = body.cedulaProfesional ? String(body.cedulaProfesional).trim() : null;
  const primarySiteId = body.primarySiteId ? String(body.primarySiteId) : null;
  const roleTitle = String(body.roleTitle ?? "Kurador").trim() || "Kurador";

  // Roles como CONJUNTO (0098, punto 7). Acepta `roles: string[]`; si la UI vieja
  // manda solo `role` (escalar), se envuelve en un conjunto de 1 (compat). El
  // profile se escribe con `roles` y el trigger sync_profile_roles deriva el
  // espejo `role` — así el alta NO depende del atajo legacy (role='admin' →
  // {admin,clinico}) que hoy da rol clínico a todo admin sin que nadie lo pida.
  const rawRoles = Array.isArray(body.roles)
    ? body.roles.map((r: unknown) => String(r))
    : [String(body.role ?? "clinico")];
  const roles = [...new Set(rawRoles.map((r) => r.trim()).filter(Boolean))];

  if (!email || !fullName) return json({ error: "email y fullName son obligatorios." }, 400);
  // Validación del conjunto (misma regla de negocio que la Fase B):
  //  - no vacío;
  //  - 'master' NUNCA por esta vía (un admin no puede otorgarlo; el master se
  //    crea/gestiona aparte);
  //  - 'cuidador' es EXCLUSIVO: cuenta con acceso reducido (0042), no se combina;
  //  - roles válidos: admin | clinico | cuidador | enfermeria.
  //    'enfermeria' (0045) y 'clinico' tienen fila de staff; 'cuidador' no.
  const VALID = ["admin", "clinico", "cuidador", "enfermeria"];
  if (roles.length === 0) return json({ error: "roles no puede estar vacío." }, 400);
  if (roles.includes("master")) {
    return json({ error: "No se puede otorgar 'master' por esta vía." }, 403);
  }
  for (const r of roles) {
    if (!VALID.includes(r)) {
      return json({ error: `Rol inválido: '${r}'. Permitidos: ${VALID.join(", ")}.` }, 400);
    }
  }
  if (roles.includes("cuidador") && roles.length > 1) {
    return json({ error: "'cuidador' es exclusivo: no puede combinarse con otros roles." }, 400);
  }
  // Espejo escalar por precedencia (master>admin>clinico>enfermeria>cuidador),
  // igual que primary_role() en la BD; se usa para user_metadata del alta en Auth.
  const primaryRole = primaryRoleOf(roles);

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
  //    Para el cuidador (login por teléfono + clave), el admin FIJA la clave y
  //    se envía en el body; para el resto se genera una contraseña temporal.
  const providedPassword =
    typeof body.password === "string" && body.password.length >= 6
      ? body.password
      : null;
  const tempPassword = providedPassword ?? genPassword();
  const { data: createdUser, error: createErr } = await admin.auth.admin.createUser({
    email,
    password: tempPassword,
    email_confirm: true,
    // El trigger handle_new_auth_user crea el profile con este `role`; luego el
    // upsert de abajo fija `roles` (autoridad) y sync_profile_roles corrige el
    // espejo. Mandamos el espejo por precedencia para que el estado intermedio
    // sea coherente.
    user_metadata: { role: primaryRole, full_name: fullName, organization_id: organizationId },
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
  // Se escribe `roles` (el CONJUNTO, autoridad) y NO `role`: el trigger
  // sync_profile_roles deriva el espejo escalar desde roles. Escribir `role`
  // aquí volvería a caer en el atajo de compatibilidad.
  const { error: profileErr } = await admin.from("profiles").upsert({
    id: uid,
    roles,
    full_name: fullName,
    email,
    phone,
    organization_id: organizationId,
    is_active: true,
  });
  if (profileErr) {
    return json({ error: `Cuenta creada pero falló el perfil: ${profileErr.message}`, uid }, 500);
  }

  // 6) Registro de personal sanitario (staff). Si el CONJUNTO incluye 'clinico'
  //    o 'enfermeria' (personal del centro); para un admin puro solo si se pide
  //    (createStaff=true). 'cuidador' NO tiene staff. Un {admin}-only no recibe
  //    staff: no diagnostica (canDiagnose=false), y si alguna vez lo necesitara,
  //    ensureAdminStaffId se la crea al vuelo.
  const hasClinico = roles.includes("clinico");
  const hasEnfermeria = roles.includes("enfermeria");
  let staffId: string | null = null;
  if (hasClinico || hasEnfermeria || body.createStaff === true) {
    staffId = await createStaffRow(admin, {
      organizationId,
      profileId: uid,
      fullName,
      roleTitle: hasClinico
          ? roleTitle
          : hasEnfermeria
              ? "Enfermería"
              : "Administrador",
      cedulaProfesional,
      primarySiteId,
    });
  }

  return json({ uid, email, tempPassword, roles, role: primaryRole, organizationId, staffId });
});

// Espejo escalar por precedencia — mismo orden que primary_role() en 0098.
function primaryRoleOf(roles: string[]): string {
  const precedence = ["master", "admin", "clinico", "enfermeria", "cuidador"];
  return precedence.find((r) => roles.includes(r)) ?? "clinico";
}

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
    headers: { "Content-Type": "application/json", ...CORS },
  });
}
