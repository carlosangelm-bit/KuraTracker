// vac-bot — Proxy al asistente de CustomGPT.ai para el módulo Terapia VAC.
// Mantiene la API key del lado del servidor (nunca en el cliente). El chat
// nativo de la app llama a esta función; el handoff a un humano (WhatsApp) lo
// resuelve la app aparte.
//
// Deploy: supabase functions deploy vac-bot --use-api   (verify_jwt)
// Secrets (Supabase):
//   CUSTOMGPT_API_KEY     -> token de API de CustomGPT.ai (Bearer).
//   CUSTOMGPT_PROJECT_ID  -> id del proyecto/agente con la info de los equipos.
//
// Acciones (body JSON):
//   { "action": "create" }                        -> { sessionId }
//   { "action": "message", sessionId, prompt }     -> { reply }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CUSTOMGPT_API_KEY = Deno.env.get("CUSTOMGPT_API_KEY") ?? "";
const CUSTOMGPT_PROJECT_ID = Deno.env.get("CUSTOMGPT_PROJECT_ID") ?? "";
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
          body: JSON.stringify({ name: "Asesoría VAC" }),
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
      const res = await fetch(
        `${BASE}/projects/${CUSTOMGPT_PROJECT_ID}/conversations/${sessionId}/messages?stream=false`,
        {
          method: "POST",
          headers: cgptHeaders(),
          body: JSON.stringify({ prompt, response_source: "default" }),
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
    console.error("vac-bot error", e);
    return json({ error: "Error al contactar al asistente." }, 502);
  }
});
