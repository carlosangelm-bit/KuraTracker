-- SOLO LECTURA (§1.5.c). Correr en el SANDBOX (y luego, si Carlos lo decide, mirar prod)
-- ANTES de aplicar 0138. Dice cuántas organizaciones tienen HOY un derecho que 0138 dejará
-- de contar: source='master', status='active', current_period_end en el PASADO. Agrupado por
-- clave. Estas son las orgs cuyo comportamiento cambia (pierden vigencia por tiempo).
--
-- No modifica nada. Si el resultado trae centros REALES en producción, lo decide Carlos.
select
  e.kind,
  e.key,
  count(distinct e.organization_id) as organizaciones,
  min(e.current_period_end)         as vencio_mas_antiguo,
  max(e.current_period_end)         as vencio_mas_reciente
from public.org_entitlements e
where e.source = 'master'
  and e.status = 'active'
  and e.current_period_end is not null
  and e.current_period_end < now()
group by e.kind, e.key
order by organizaciones desc, e.kind, e.key;
