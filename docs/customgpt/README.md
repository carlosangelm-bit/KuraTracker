# Asistente de soporte (CustomGPT.ai) — configuración

Asistente de ayuda embebido en la app que detecta el **perfil** (rol + tipo de centro) y
el **proceso** (pantalla actual) del usuario para dar soporte personalizado sobre el uso
de la plataforma. Reutiliza el patrón del bot de VAC.

## Arquitectura

```
App Flutter (menú de usuario → "Asistente de ayuda")
   │  captura contexto NO sensible: {rol, centro, ruta, pantalla}
   ▼
Edge Function  supabase/functions/support-bot   ← API key server-side; borra ids de la ruta
   │  antepone el bloque [CONTEXTO_KURATRACKER] al prompt
   ▼
CustomGPT.ai (agente de soporte, conocimiento = docs/MANUAL.md)
```

- La app **nunca** manda datos del paciente. Solo el rol, el tipo de centro, la ruta
  (sin ids: la Edge Function los reemplaza por `:id`) y una etiqueta de pantalla.
- El acceso requiere sesión válida de Supabase (`verify_jwt`); solo aparece en producción.

## Componentes en el repo

- `supabase/functions/support-bot/index.ts` — proxy autenticado + inyección de contexto.
- `lib/features/support/support_bot_screen.dart` — UI del chat.
- `lib/features/support/support_launcher.dart` — captura el contexto de la pantalla actual
  (`openSupportAssistant`) y el mapa ruta → etiqueta (`supportScreenLabelFor`).
- Ruta `/support` (`lib/core/router/app_router.dart`) y el ítem "Asistente de ayuda" en el
  menú de usuario (`lib/core/router/app_shell.dart`).
- `docs/customgpt/AGENT_INSTRUCTIONS.md` — la persona del agente (pegar en customgpt.ai).
- `docs/MANUAL.md` — el conocimiento del agente (subir a customgpt.ai).

## Configuración (una sola vez)

1. **Agente en customgpt.ai:** crea un agente de soporte; pega `AGENT_INSTRUCTIONS.md` en
   Instructions/Persona y sube `docs/MANUAL.md` como fuente de conocimiento.
2. **Secrets en Supabase** (los pone el equipo; no van en el repo):
   ```bash
   supabase secrets set CUSTOMGPT_SUPPORT_API_KEY=<api_key> --project-ref mhnhgnzajdjhllypdutr
   supabase secrets set CUSTOMGPT_SUPPORT_PROJECT_ID=<project_id> --project-ref mhnhgnzajdjhllypdutr
   ```
3. **Deploy:** el CI despliega `support-bot` automáticamente (paso en `deploy_functions`
   de `.github/workflows/deploy.yml`).

## Contrato de contexto

La app envía en cada mensaje `context = {rol, centro, ruta, pantalla}` y la Edge Function
lo convierte en:

```
[CONTEXTO_KURATRACKER]
rol: clinico
centro: clinica_heridas
ruta: /patients/:id/wound/:id/capture
pantalla: Valoración: captura de herida
[/CONTEXTO_KURATRACKER]

<pregunta del usuario>
```

## Mantenimiento

El conocimiento del agente es `docs/MANUAL.md`: cuando el manual cambie, vuelve a subirlo
al agente en customgpt.ai. La persona vive en `AGENT_INSTRUCTIONS.md`.
