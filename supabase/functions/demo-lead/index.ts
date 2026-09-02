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
// nada (solo crea). Validación mínima: método, tamaño, campos, correo, honeypot.
//
// Deploy: supabase functions deploy demo-lead --use-api --no-verify-jwt
// Secrets (Supabase):
//   BITRIX_WEBHOOK_URL -> URL del webhook entrante de Bitrix
//                         (https://<portal>/rest/<user>/<token>/). Da acceso a
//                         TODO el CRM: solo del lado del servidor, nunca al navegador.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const BITRIX_WEBHOOK_URL = Deno.env.get("BITRIX_WEBHOOK_URL") ?? "";

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

// Tope de tamaño del payload: un formulario legítimo son unos cientos de bytes.
const MAX_BODY_BYTES = 8 * 1024;
const MAX_FIELD = 200; // longitud máxima por campo simple
const MAX_TEXT = 2000; // longitud máxima del texto libre / comentarios

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

// Requerido y dentro de longitud.
function badField(s: string): boolean {
  return s.length === 0 || s.length > MAX_FIELD;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Método no permitido." }, 405);

  if (!BITRIX_WEBHOOK_URL) {
    console.error("demo-lead: falta el secret BITRIX_WEBHOOK_URL");
    return json({ error: "Captura de leads no configurada." }, 500);
  }

  // Rechazo de payloads grandes (defensa contra abuso), por header y por lectura.
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > MAX_BODY_BYTES) return json({ error: "Payload demasiado grande." }, 413);

  let raw: string;
  try {
    raw = await req.text();
  } catch {
    return json({ error: "No se pudo leer el cuerpo." }, 400);
  }
  if (raw.length > MAX_BODY_BYTES) return json({ error: "Payload demasiado grande." }, 413);

  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return json({ error: "JSON inválido." }, 400);
  }

  // Honeypot: un campo trampa que los bots llenan y las personas no. Si viene
  // con algo, se responde 200 sin crear nada (no se le da señal al bot).
  if (str(body["hp"]).length > 0) return json({ ok: true });

  const firstName = str(body["first_name"]);
  const lastName = str(body["last_name"]);
  const email = str(body["email"]).toLowerCase();
  const phone = str(body["phone"]);
  const userType = str(body["user_type"]);
  const otherText = str(body["other_text"]);
  const createdAt = str(body["created_at"]);

  // Validación de requeridos + formato + longitudes.
  if (badField(firstName) || badField(lastName)) {
    return json({ error: "Nombre y apellido son obligatorios." }, 400);
  }
  if (!EMAIL_RE.test(email) || email.length > MAX_FIELD) {
    return json({ error: "Correo inválido." }, 400);
  }
  if (userType.length === 0 || userType.length > MAX_FIELD) {
    return json({ error: "Falta el tipo de usuario." }, 400);
  }
  if (phone.length > MAX_FIELD || otherText.length > MAX_TEXT) {
    return json({ error: "Campo demasiado largo." }, 400);
  }

  // Comentario del lead: tipo de usuario elegido + texto libre de "Otro" + fecha.
  const comments = [
    `Tipo de usuario: ${userType}`,
    otherText ? `¿A qué se dedica?: ${otherText}` : "",
    createdAt ? `Capturado: ${createdAt}` : "",
    "Origen: Demo KuraTracker",
  ].filter((s) => s.length > 0).join("\n");

  const fields: Record<string, unknown> = {
    TITLE: `Demo KuraTracker — ${firstName} ${lastName}`.slice(0, MAX_FIELD),
    NAME: firstName,
    LAST_NAME: lastName,
    EMAIL: [{ VALUE: email, VALUE_TYPE: "WORK" }],
    SOURCE_DESCRIPTION: "Demo KuraTracker",
    COMMENTS: comments,
  };
  if (phone.length > 0) {
    fields["PHONE"] = [{ VALUE: phone, VALUE_TYPE: "WORK" }];
  }

  // crm.lead.add en el webhook de Bitrix (la URL trae user+token embebidos).
  const url = BITRIX_WEBHOOK_URL.replace(/\/?$/, "/") + "crm.lead.add.json";
  try {
    const resp = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ fields, params: { REGISTER_SONET_EVENT: "Y" } }),
    });
    const data = await resp.json().catch(() => ({}));
    if (!resp.ok || (data && data.error)) {
      // No se registra el correo ni el nombre: solo lo necesario para diagnosticar.
      console.error(
        `demo-lead: Bitrix rechazó (${resp.status}) ${data?.error ?? ""} ${data?.error_description ?? ""}`,
      );
      return json({ error: "No se pudo registrar el contacto." }, 502);
    }
    return json({ ok: true });
  } catch (e) {
    console.error(`demo-lead: error de red hacia Bitrix: ${e}`);
    return json({ error: "No se pudo contactar el CRM." }, 502);
  }
});
