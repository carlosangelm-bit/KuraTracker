// support-bot — Proxy al asistente de soporte de la plataforma (CustomGPT.ai).
// Igual que vac-bot pero con su PROPIO agente/llave y con INYECCIÓN DE CONTEXTO
// NO SENSIBLE: la app manda {rol, centro, ruta, pantalla} y esta función lo
// antepone al prompt como un bloque [CONTEXTO_KURATRACKER] para que el agente
// detecte el perfil y el proceso del usuario y personalice la ayuda.
//
// La API key vive del lado del servidor (nunca en el cliente). NUNCA se envían
// datos del paciente: el "ruta" se normaliza para borrar cualquier id (UUID/
// numérico) antes de mandarlo.
//
// Deploy: supabase functions deploy support-bot --use-api   (verify_jwt)
// Secrets (Supabase):
//   CUSTOMGPT_SUPPORT_API_KEY     -> token de API del agente de soporte (Bearer).
//   CUSTOMGPT_SUPPORT_PROJECT_ID  -> id del proyecto/agente de soporte.
//
// Acciones (body JSON):
//   { "action": "create" }                                   -> { sessionId }
//   { "action": "message", sessionId, prompt, context? }      -> { reply }
//     context = { rol, centro, ruta, pantalla }  (todos opcionales, sin PHI)

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CUSTOMGPT_API_KEY = Deno.env.get("CUSTOMGPT_SUPPORT_API_KEY") ?? "";
const CUSTOMGPT_PROJECT_ID = Deno.env.get("CUSTOMGPT_SUPPORT_PROJECT_ID") ?? "";
const BASE = "https://app.customgpt.ai/api/v1";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

function cgptHeaders() {
  return {
    Authorization: `Bearer ${CUSTOMGPT_API_KEY}`,
    "content-type": "application/json",
    accept: "application/json",
  };
}

// Quita cualquier identificador de la ruta (UUID o segmento numérico largo) para
// que no salga NADA que pueda ligar a un paciente. Deja el patrón de la pantalla.
function scrubRoute(route: string): string {
  return route
    .replace(
      /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi,
      ":id",
    )
    .replace(/\/\d{3,}/g, "/:id");
}

// Construye el bloque de contexto (solo campos presentes; todos no sensibles).
function contextBlock(ctx: Record<string, unknown> | undefined): string {
  if (!ctx || typeof ctx !== "object") return "";
  const clean = (v: unknown) =>
    typeof v === "string" ? v.slice(0, 200).replace(/[\r\n]+/g, " ").trim() : "";
  const rol = clean(ctx["rol"]);
  const centro = clean(ctx["centro"]);
  const ruta = ctx["ruta"] ? scrubRoute(clean(ctx["ruta"])) : "";
  const pantalla = clean(ctx["pantalla"]);
  const lines: string[] = [];
  if (rol) lines.push(`rol: ${rol}`);
  if (centro) lines.push(`centro: ${centro}`);
  if (ruta) lines.push(`ruta: ${ruta}`);
  if (pantalla) lines.push(`pantalla: ${pantalla}`);
  if (!lines.length) return "";
  return `[CONTEXTO_KURATRACKER]\n${lines.join("\n")}\n[/CONTEXTO_KURATRACKER]\n\n`;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  // Autenticación: requiere sesión válida de Supabase (verify_jwt).
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "No autenticado." }, 401);
  const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
  if (callerErr || !caller.user) return json({ error: "Sesión inválida." }, 401);

  if (!CUSTOMGPT_API_KEY || !CUSTOMGPT_PROJECT_ID) {
    return json(
      { error: "El asistente no está configurado (faltan secrets de CustomGPT)." },
      500,
    );
  }

  let payload: Record<string, unknown> = {};
  try {
    payload = await req.json();
  } catch (_) {
    return json({ error: "Body inválido." }, 400);
  }
  const action = payload["action"] as string | undefined;

  try {
    if (action === "create") {
      const res = await fetch(
        `${BASE}/projects/${CUSTOMGPT_PROJECT_ID}/conversations`,
        {
          method: "POST",
          headers: cgptHeaders(),
          body: JSON.stringify({ name: "Soporte KuraTracker" }),
        },
      );
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        console.error("customgpt create error", res.status, JSON.stringify(body));
        return json({ error: `CustomGPT rechazó la conversación (HTTP ${res.status}).` }, 502);
      }
      const sessionId = body?.data?.session_id ?? body?.data?.id ?? null;
      if (!sessionId) return json({ error: "CustomGPT no devolvió sesión." }, 502);
      return json({ sessionId: String(sessionId) });
    }

    if (action === "message") {
      const sessionId = payload["sessionId"] as string | undefined;
      const prompt = payload["prompt"] as string | undefined;
      if (!sessionId || !prompt) {
        return json({ error: "Faltan sessionId o prompt." }, 400);
      }
      const block = contextBlock(payload["context"] as Record<string, unknown> | undefined);
      const fullPrompt = `${block}${prompt}`;
      const res = await fetch(
        `${BASE}/projects/${CUSTOMGPT_PROJECT_ID}/conversations/${sessionId}/messages?stream=false`,
        {
          method: "POST",
          headers: cgptHeaders(),
          body: JSON.stringify({ prompt: fullPrompt, response_source: "default" }),
        },
      );
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        console.error("customgpt message error", res.status, JSON.stringify(body));
        return json({ error: `CustomGPT rechazó el mensaje (HTTP ${res.status}).` }, 502);
      }
      const d = body?.data ?? {};
      const reply = d.openai_response ?? d.response ?? d.assistant_response ??
        d.message ?? "";
      return json({ reply: String(reply) });
    }

    return json({ error: "Acción no soportada." }, 400);
  } catch (e) {
    console.error("support-bot error", e);
    return json({ error: "Error al contactar al asistente." }, 502);
  }
});
