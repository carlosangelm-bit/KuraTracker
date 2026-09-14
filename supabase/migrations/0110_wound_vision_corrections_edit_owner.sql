-- =============================================================================
-- 0110_wound_vision_corrections_edit_owner.sql — Restringe UPDATE/DELETE de las
-- correcciones a su AUTOR (o admin). INSERT sigue abierto a todo staff asignado.
-- =============================================================================
-- Motivo: reproducibilidad del dataset. Si cualquier evaluador puede reescribir
-- la etiqueta de otro, las etiquetas cambian DESPUÉS de exportarlas y el modelo
-- entrenado deja de corresponder a la base; y la concordancia inter-evaluador
-- (created_by_role) solo tiene sentido si la etiqueta de cada quien es inmutable
-- para los demás. El autor puede rehacer la suya; admin modera.
--
-- Predicado: created_by referencia profiles(id), y is_admin() está definido como
-- profiles.id = auth.uid(), o sea profiles.id ES auth.uid(). Por eso se compara
-- created_by = auth.uid() (NO current_staff_id(), que devuelve staff.id y sería
-- un bug silencioso: nadie podría editar su propia corrección).
--
-- Aditiva: reemplaza SOLO la policy de escritura de 0109 (wvc_write, for all) por
-- INSERT/UPDATE/DELETE separadas. wvc_select (0109) no se toca.
-- =============================================================================

drop policy if exists wvc_write on public.wound_vision_corrections;

-- INSERT: cualquier staff activo asignado al paciente de la herida (o admin).
-- Igual que antes: todo el equipo puede aportar correcciones.
create policy wvc_insert on public.wound_vision_corrections
  for insert with check (
    public.is_admin()
    or exists (
      select 1 from public.wounds w
      join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
      where w.id = wound_vision_corrections.wound_id
        and spa.staff_id = public.current_staff_id()
    )
  );

-- UPDATE: solo el AUTOR o admin.
-- DECISIÓN EXPLÍCITA sobre created_by NULL: la comparación created_by = auth.uid()
-- da NULL cuando created_by es NULL, así que una corrección SIN autor solo la
-- puede editar admin. Es a propósito (una fila sin autor no debe ser editable por
-- cualquiera), no un descuido.
create policy wvc_update on public.wound_vision_corrections
  for update
  using (public.is_admin() or created_by = auth.uid())
  with check (public.is_admin() or created_by = auth.uid());

-- DELETE: solo el AUTOR o admin (misma lógica de NULL).
create policy wvc_delete on public.wound_vision_corrections
  for delete
  using (public.is_admin() or created_by = auth.uid());
