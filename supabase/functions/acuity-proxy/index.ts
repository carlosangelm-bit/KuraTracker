// acuity-proxy — Proxy autenticado hacia la API de Acuity Scheduling.
//
// Por qué existe: Acuity no soporta CORS y las credenciales (API Key) NO
// pueden vivir en el cliente. La app (Flutter) llama a esta función con su JWT
// de Supabase (supabase.functions.invoke lo adjunta), y aquí se traduce la
// llamada a Acuity usando Basic Auth.
//
// MULTI-CENTRO (Fase 2): las credenciales se resuelven según la organización
// del usuario que llama (organization_acuity_credentials, 0022), con fallback a
// los secrets globales (cuenta única actual). Así cada centro habla con SU
// propia cuenta de Acuity.
//
// Uso desde la app: functions.invoke('acuity-proxy', body: {
//   'method': 'GET'|'POST'|'PUT', 'path': '/appointment-types', 'query': {...},
//   'payload': {...}
// })
//
// Deploy:  supabase functions deploy acuity-proxy   (con verify_jwt, default)

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getAcuityAuth } from "../_shared/acuity_auth.ts";

const ACUITY_BASE = "https://acuityscheduling.com/api/v1";

// CORS: la app (Flutter Web) llama esta función cross-origin
// (app.kuramas.com → supabase.co); sin estos headers ni manejo del preflight
// OPTIONS, el navegador bloquea la llamada ("Failed to fetch").
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { autoRefreshToken: false, persistSession: false } },
);

interface ProxyRequest {
  method?: string;
  path?: string;
  query?: Record<string, string | number | boolean>;
  payload?: unknown;
}

serve(async (req) => {
  // Preflight CORS: debe responder 200 con los headers ANTES de validar el JWT
  // (el navegador no manda Authorization en el preflight).
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  // Resolver el centro del usuario que llama (por su JWT) y sus credenciales.
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "No autenticado." }, 401);
  const { data: caller, error: callerErr } = await supabase.auth.getUser(jwt);
  if (callerErr || !caller.user) return json({ error: "Sesión inválida." }, 401);
  const { data: profile } = await supabase
    .from("profiles")
    .select("organization_id")
    .eq("id", caller.user.id)
    .maybeSingle();

  const auth = await getAcuityAuth(supabase, (profile?.organization_id as string | null) ?? null);
  if (!auth) return json({ error: "Acuity no configurado para este centro." }, 503);

  let body: ProxyRequest;
  try {
    body = (await req.json()) as ProxyRequest;
  } catch (_) {
    return json({ error: "Cuerpo JSON inválido." }, 400);
  }

  const method = (body.method ?? "GET").toUpperCase();
  const path = body.path ?? "";
  if (!path.startsWith("/")) return json({ error: "path debe iniciar con /." }, 400);

  const qs = new URLSearchParams();
  for (const [k, v] of Object.entries(body.query ?? {})) qs.set(k, String(v));
  const target = `${ACUITY_BASE}${path}${qs.toString() ? `?${qs}` : ""}`;

  // Reintento simple ante 429 (rate limit: 10 req/s en Acuity).
  for (let attempt = 0; attempt < 3; attempt++) {
    const res = await fetch(target, {
      method,
      headers: { Authorization: `Basic ${auth.basic}`, "Content-Type": "application/json" },
      body: method === "GET" || method === "HEAD" ? undefined : JSON.stringify(body.payload ?? {}),
    });
    if (res.status === 429 && attempt < 2) {
      await new Promise((r) => setTimeout(r, 300 * (attempt + 1)));
      continue;
    }
    const text = await res.text();
    return new Response(text, {
      status: res.status,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
  return json({ error: "Acuity rate limit (429)." }, 429);
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
