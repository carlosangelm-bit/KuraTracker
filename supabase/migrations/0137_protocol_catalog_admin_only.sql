-- =============================================================================
-- 0137_protocol_catalog_admin_only.sql — Matriz del protocolo · etapa 1 (corrección A)
-- =============================================================================
-- 0136 cerró la RLS del catálogo solo por ORGANIZACIÓN: con protocol:author, CUALQUIER
-- miembro del centro (clínico, enfermería, cuidador) podía LEER y —por `for all` con
-- with check— también ESCRIBIR y BORRAR el catálogo. La autoría del catálogo Kura+ es del
-- ADMIN del centro, no de cualquiera; el clínico recibe el régimen RESUELTO (etapa 2), no
-- necesita los renglones. Se restringe lectura Y escritura a admin + protocol:author (o
-- master, según el patrón de las demás tablas). Hueco de la especificación, no de conducta
-- previa: 0136 ya está aplicado, así que la corrección va en migración nueva.
-- =============================================================================

-- Corrección C: vigencia con la ASIMETRÍA POR ORIGEN de canWriteModule (data_repository).
-- protocol:author lo otorga el master, y la autoridad de vigencia del master SÍ mira la
-- fecha; la de Stripe NO (una renovación tardía no debe cerrarle el catálogo a quien paga).
--   - source='master' → status='active' Y (current_period_end null O aún vigente).
--   - source='stripe' → status='active' solamente.
-- Hoy es un no-op (los otorgamientos del master van sin fecha = permanentes); cubre el día
-- en que alguien ponga una, sin la falla silenciosa que la fecha-para-todos causaría en
-- Stripe. NOTA aparte (a agendar): SQL y Dart discrepan en qué es un derecho "vigente"
-- (Dart distingue por origen; 0115/0121 miran solo status) — misma familia que los dos
-- resolvedores; se reporta, no se arregla aquí.
create or replace function public.current_org_has_protocol_author()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.org_entitlements e
    where e.organization_id = public.current_organization_id()
      and e.kind = 'module'
      and e.key = 'protocol:author'
      and e.status = 'active'
      and (
        e.source = 'stripe'
        or (e.source = 'master'
            and (e.current_period_end is null or e.current_period_end > now()))
      )
  );
$$;

drop policy if exists protocol_catalog_rules_all on public.protocol_catalog_rules;
create policy protocol_catalog_rules_all on public.protocol_catalog_rules
  for all
  using (
    public.is_master()
    or (public.is_admin() and public.current_org_has_protocol_author())
  )
  with check (
    public.is_master()
    or (public.is_admin() and public.current_org_has_protocol_author())
  );

-- Nota B: documenta protocol:author entre las claves válidas de kind='module' EN LA BASE.
-- 0113 solo lo tenía como comentario inline en el CREATE (no consultable); aquí queda como
-- comment on column, consultable, con la clave nueva incluida.
comment on column public.org_entitlements.key is
  'Identificador dentro de kind. plan → basico (gratuito retirado en 0126); '
  'module → clinico | insumos | comercial | admin | protocol:author '
  '(protocol:author = derecho de AUTORÍA del catálogo Kura+; solo Kura+; gobierna la RLS de '
  'protocol_catalog_rules vía current_org_has_protocol_author()); seat → clinico | protocolo.';
