// demo-lead — Función portera de los leads de la demo. Recibe el formulario de
// captura previo a la demo (pantalla /demo del cliente Flutter) y crea un lead
// en Bitrix vía su webhook entrante. El TOKEN de Bitrix vive SOLO del lado del
// servidor (secret de Supabase); el bundle público nunca lo ve.
//
// NO guarda nada en Supabase: recibe, valida y reenvía a Bitrix. Sin
// identificadores del navegador, sin IP, sin lo que el prospecto hizo dentro de
// la demo — solo los campos del formulario (§3 del spec).
//
// Endpoint PÚBLICO (se llama desde el navegador en modo demo, sin sesión de
// Supabase) → se despliega con --no-verify-jwt, igual que los webhooks de pago.
// Radio de daño: lo peor es que alguien meta leads basura al CRM; no puede leer
// nada útil (solo crea leads). Validación mínima: método, tamaño, campos,
// correo, honeypot.
//
// Deploy: supabase functions deploy demo-lead --use-api --no-verify-jwt
// Secrets/variables (Supabase → Edge Functions):
//   BITRIX_WEBHOOK_URL      URL del webhook entrante de Bitrix
//                           (https://<portal>/rest/<user>/<token>/). Da acceso a
//                           TODO el CRM: solo del lado servidor, nunca al navegador.
//   BITRIX_ASSIGNED_BY_ID   ID numérico del responsable comercial. OPCIONAL: si no
//                           está puesto (o no es un número válido), la función NO
//                           fija responsable y los leads caen en la cuenta dueña del
//                           webhook (Carlos). No falla por su ausencia.
//   BITRIX_USERTYPE_FIELD   Código del campo de LISTA "tipo de usuario"
//                           (ufCrm_LEAD_1788382308670). La etiqueta que manda la app
//                           se traduce al ID de su opción (leyendo crm.item.fields)
//                           para que Carlos pueda FILTRAR leads por tipo. Las seis
//                           opciones empatan palabra por palabra con las etiquetas de
//                           la app (IDs 284/286/288/290/292/294): el mapeo es directo.
//
// El EVENTO no usa campo propio (Carlos decidió no crearlo): su valor —el que la
// app manda en `event` desde su dart-define DEMO_EVENT— se concatena a
// sourceDescription como "Demo KuraTracker · <evento>". Si algún día se quiere
// filtrar por evento, se crea el campo y se vuelve a rutear ahí.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const BITRIX_WEBHOOK_URL = Deno.env.get("BITRIX_WEBHOOK_URL") ?? "";
const ASSIGNED_BY_ID = Deno.env.get("BITRIX_ASSIGNED_BY_ID") ?? "";
const USERTYPE_FIELD = Deno.env.get("BITRIX_USERTYPE_FIELD") ?? "";

// entityTypeId del LEAD en la API universal de Bitrix (crm.item.*). Se usa
// crm.item.add porque crm.lead.add está marcado como obsoleto.
const LEAD_ENTITY_TYPE_ID = 1;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

const MAX_BODY_BYTES = 8 * 1024; // un formulario legítimo son cientos de bytes
const MAX_FIELD = 200;
const MAX_TEXT = 2000;
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function badField(s: string): boolean {
  return s.length === 0 || s.length > MAX_FIELD;
}

// deno-lint-ignore no-explicit-any
type Json = any;

// Llamada REST al webhook de Bitrix (la URL trae user+token embebidos).
async function bitrix(method: string, params: unknown): Promise<
  { ok: boolean; status: number; data: Json }
> {
  const url = BITRIX_WEBHOOK_URL.replace(/\/?$/, "/") + method + ".json";
  const resp = await fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(params),
  });
  const data = await resp.json().catch(() => ({}));
  return { ok: resp.ok && !data?.error, status: resp.status, data };
}

// Metadatos de campos del lead, cacheados mientras viva el isolate (evita un
// round-trip extra por request).
let _fieldsCache: Json = null;

// Traduce la etiqueta del tipo de usuario al ID de su opción en el campo de
// lista de Bitrix. Devuelve null si no hay campo configurado o no empata.
async function userTypeOptionId(label: string): Promise<string | null> {
  if (!USERTYPE_FIELD) return null;
  if (!_fieldsCache) {
    const r = await bitrix("crm.item.fields", {
      entityTypeId: LEAD_ENTITY_TYPE_ID,
    });
    if (!r.ok) {
      console.error(`demo-lead: crm.item.fields falló (${r.status})`);
      return null;
    }
    _fieldsCache = r.data?.result?.fields ?? {};
  }
  const field = _fieldsCache[USERTYPE_FIELD];
  const items: Json[] = field?.items ?? [];
  const norm = (s: string) => s.trim().toLowerCase();
  const match = items.find(
    (it) => norm(String(it.VALUE ?? it.value ?? "")) === norm(label),
  );
  return match ? String(match.ID ?? match.id) : null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Método no permitido." }, 405);

  if (!BITRIX_WEBHOOK_URL) {
    console.error("demo-lead: falta el secret BITRIX_WEBHOOK_URL");
    return json({ error: "Captura de leads no configurada." }, 500);
  }

  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > MAX_BODY_BYTES) {
    return json({ error: "Payload demasiado grande." }, 413);
  }

  let raw: string;
  try {
    raw = await req.text();
  } catch {
    return json({ error: "No se pudo leer el cuerpo." }, 400);
  }
  if (raw.length > MAX_BODY_BYTES) {
    return json({ error: "Payload demasiado grande." }, 413);
  }

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return json({ error: "JSON inválido." }, 400);
  }

  // Honeypot: campo trampa que los bots llenan y las personas no. Si viene con
  // algo, se responde 200 sin crear nada (no se le da señal al bot).
  if (str(body["hp"]).length > 0) return json({ ok: true });

  const firstName = str(body["first_name"]);
  const lastName = str(body["last_name"]);
  const email = str(body["email"]).toLowerCase();
  const phone = str(body["phone"]);
  const userType = str(body["user_type"]);
  const otherText = str(body["other_text"]);
  const event = str(body["event"]);
  const createdAt = str(body["created_at"]);

  if (badField(firstName) || badField(lastName)) {
    return json({ error: "Nombre y apellido son obligatorios." }, 400);
  }
  if (!EMAIL_RE.test(email) || email.length > MAX_FIELD) {
    return json({ error: "Correo inválido." }, 400);
  }
  if (userType.length === 0 || userType.length > MAX_FIELD) {
    return json({ error: "Falta el tipo de usuario." }, 400);
  }
  if (
    phone.length > MAX_FIELD || otherText.length > MAX_TEXT ||
    event.length > MAX_FIELD
  ) {
    return json({ error: "Campo demasiado largo." }, 400);
  }

  // El texto libre de "Otro" y la fecha van a comentarios; el TIPO DE USUARIO ya
  // NO va aquí — va a su campo de lista para poder filtrar (§ cambio 1).
  const comments = [
    otherText ? `¿A qué se dedica?: ${otherText}` : "",
    createdAt ? `Capturado: ${createdAt}` : "",
    "Origen: Demo KuraTracker",
  ].filter((s) => s.length > 0).join("\n");

  // El evento va en sourceDescription (no en un campo propio): "Demo KuraTracker
  // · <evento>". Sin evento, queda solo "Demo KuraTracker".
  const sourceDescription = event.length > 0
    ? `Demo KuraTracker · ${event}`.slice(0, MAX_FIELD)
    : "Demo KuraTracker";

  const fields: Record<string, unknown> = {
    title: `Demo KuraTracker — ${firstName} ${lastName}`.slice(0, MAX_FIELD),
    name: firstName,
    lastName: lastName,
    sourceDescription,
    comments,
    email: [{ value: email, valueType: "WORK" }],
  };
  if (phone.length > 0) fields.phone = [{ value: phone, valueType: "WORK" }];
  // Responsable OPCIONAL: solo se fija si BITRIX_ASSIGNED_BY_ID es un número
  // válido. Ausente o mal puesto → no se manda y el lead cae en la cuenta del
  // webhook (no se envía un NaN).
  const assignedBy = Number(ASSIGNED_BY_ID);
  if (Number.isFinite(assignedBy) && assignedBy > 0) {
    fields.assignedById = assignedBy;
  }

  // Tipo de usuario → ID de opción del campo de lista.
  const optId = await userTypeOptionId(userType);
  if (USERTYPE_FIELD && optId) {
    fields[USERTYPE_FIELD] = optId;
  } else if (USERTYPE_FIELD) {
    console.error(
      `demo-lead: tipo de usuario no empató ninguna opción de ${USERTYPE_FIELD}`,
    );
  } else {
    console.error("demo-lead: falta BITRIX_USERTYPE_FIELD (tipo de usuario)");
  }

  const r = await bitrix("crm.item.add", {
    entityTypeId: LEAD_ENTITY_TYPE_ID,
    fields,
  });
  if (!r.ok) {
    // No se registra el correo ni el nombre: solo lo necesario para diagnosticar.
    console.error(
      `demo-lead: crm.item.add rechazó (${r.status}) ${r.data?.error ?? ""} ${
        r.data?.error_description ?? ""
      }`,
    );
    return json({ error: "No se pudo registrar el contacto." }, 502);
  }
  return json({ ok: true });
});
