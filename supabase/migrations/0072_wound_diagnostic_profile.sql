-- 0072_wound_diagnostic_profile.sql
-- Perfil diagnóstico persistente de la herida (fix/followup-inherited-profile).
--
-- Bug: el seguimiento perdía el subtipo vascular y la determinación de "no
-- revascularizable" porque nunca se guardaban en la herida (solo se pasaban al
-- motor en vivo durante la valoración). Sin ellos, una úlcera arterial se
-- trataba como venosa en seguimiento (compresión/cura húmeda en vez de terapia
-- seca). Estos dos campos son atributos DIAGNÓSTICOS de la herida (estables
-- entre visitas), por eso viven en `wounds` (braden_score es por-visita y ya
-- existe en wound_assessments, 0005).
--
-- Solo agrega columnas; NO toca RLS (las policies de wounds ya cubren las
-- columnas nuevas).

alter table public.wounds
  add column if not exists subtipo_vascular text,
  add column if not exists no_revascularizable boolean not null default false;

comment on column public.wounds.subtipo_vascular is
  'Subtipo de úlcera vascular: venosa|arterial|mixta. Separa el manejo venoso (compresión) del arterial/isquémico (terapia seca). NULL si no aplica/no clasificado.';
comment on column public.wounds.no_revascularizable is
  'Determinación (Doppler/angiólogo) de lesión NO revascularizable: gatilla terapia seca aunque el ITB no sea crítico.';
