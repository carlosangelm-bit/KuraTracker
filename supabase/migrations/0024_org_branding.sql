-- 0024_org_branding.sql
--
-- Branding por centro para los reportes al paciente: cada organización puede
-- fijar su color principal y su logo. El reporte PDF los usa (encabezado y
-- acentos); si no hay, cae al color de marca por defecto y al nombre del centro.

alter table public.organizations
  add column if not exists brand_primary_color text, -- hex '#7C3AED'
  add column if not exists brand_logo_path text;      -- ruta en bucket org-branding

comment on column public.organizations.brand_primary_color is
  'Color principal del centro para reportes (hex, p.ej. #7C3AED). NULL = color '
  'de marca por defecto.';

-- Bucket privado para logos (no es dato clínico, pero se mantiene privado y se
-- sirve por signed URL, consistente con el resto). Escribible por admin del
-- propio centro (RLS por organization_id en la ruta).
insert into storage.buckets (id, name, public, file_size_limit)
values ('org-branding', 'org-branding', false, 5242880) -- 5 MB
on conflict (id) do nothing;

create policy "org_branding_select" on storage.objects
  for select using (
    bucket_id = 'org-branding'
    and (
      public.is_master()
      or (storage.foldername(name))[1] = public.current_organization_id()::text
    )
  );

create policy "org_branding_insert" on storage.objects
  for insert with check (
    bucket_id = 'org-branding'
    and (
      public.is_master()
      or (storage.foldername(name))[1] = public.current_organization_id()::text
    )
  );

create policy "org_branding_delete" on storage.objects
  for delete using (
    bucket_id = 'org-branding'
    and (
      public.is_master()
      or (storage.foldername(name))[1] = public.current_organization_id()::text
    )
  );

-- RPC: fija el branding del centro (admin del propio centro o master). La RLS de
-- organizations solo permite UPDATE al master (0012), por eso este RPC acotado.
create or replace function public.set_org_branding(
  p_org uuid, p_primary_color text, p_logo_path text
) returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if not (public.is_master() or (public.is_admin() and p_org = public.current_organization_id())) then
    raise exception 'No autorizado para configurar el branding de este centro.';
  end if;
  update public.organizations
    set brand_primary_color = p_primary_color,
        brand_logo_path = p_logo_path
    where id = p_org;
end;
$$;

grant execute on function public.set_org_branding(uuid, text, text) to authenticated;
