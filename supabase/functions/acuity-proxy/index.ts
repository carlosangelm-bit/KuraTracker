// acuity-proxy — Proxy autenticado hacia la API de Acuity Scheduling.
//
// Por qué existe: Acuity no soporta CORS y las credenciales (API Key) NO
// pueden vivir en el cliente. La app (Flutter) llama a esta función con su JWT
// de Supabase (supabase.functions.invoke lo adjunta automáticamente), y aquí
// se traduce la llamada a Acuity usando Basic Auth desde secrets del servidor.
//
// Con verify_jwt ACTIVADO (default), solo usuarios autenticados de Supabase
// pueden invocarla. La autorización fina (qué puede ver/hacer cada rol) se
// aplica en la app + RLS sobre la tabla appointments; este proxy es un puente.
//
// Uso desde la app: functions.invoke('acuity-proxy', body: {
//   'method': 'GET'|'POST'|'PUT', 'path': '/appointment-types', 'query': {...},
//   'payload': {...}   // cuerpo JSON para POST/PUT
// })
//
// Deploy:  supabase functions deploy acuity-proxy
// Secrets: supabase secrets set ACUITY_USER_ID=... ACUITY_API_KEY=...

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const USER_ID = Deno.env.get("ACUITY_USER_ID") ?? "";
const API_KEY = Deno.env.get("ACUITY_API_KEY") ?? "";
const AUTH = btoa(`${USER_ID}:${API_KEY}`);
const ACUITY_BASE = "https://acuityscheduling.com/api/v1";

interface ProxyRequest {
  method?: string;
  path?: string;
  query?: Record<string, string | number | boolean>;
  payload?: unknown;
}

serve(async (req) => {
  if (!USER_ID || !API_KEY) {
    return json({ error: "Acuity no configurado (faltan secrets)." }, 503);
  }
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
      headers: { Authorization: `Basic ${AUTH}`, "Content-Type": "application/json" },
      body: method === "GET" || method === "HEAD" ? undefined : JSON.stringify(body.payload ?? {}),
    });
    if (res.status === 429 && attempt < 2) {
      await new Promise((r) => setTimeout(r, 300 * (attempt + 1)));
      continue;
    }
    const text = await res.text();
    return new Response(text, {
      status: res.status,
      headers: { "Content-Type": "application/json" },
    });
  }
  return json({ error: "Acuity rate limit (429)." }, 429);
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
