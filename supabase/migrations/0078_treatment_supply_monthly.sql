-- 0078: modo de cantidad por insumo del plan (por sesión vs mensual/multidosis).
--
-- Algunos productos son MULTIDOSIS: se compran una o dos veces por mes según el
-- uso, independientemente del número de sesiones. Para esos, la cantidad que
-- captura el profesional en el plan del mes ES la cantidad mensual y NO debe
-- multiplicarse por el número de sesiones en la explosión de materiales.
--
-- is_monthly = false (default): cantidad POR SESIÓN (consumibles de cada cura);
--   mensual = quantity_per_session × sesiones (comportamiento previo, sin cambios).
-- is_monthly = true: cantidad MENSUAL directa (multidosis); mensual = quantity_per_session.
--
-- Cambio ADITIVO (solo agrega columna con default); no toca RLS ni datos.

alter table public.treatment_program_supplies
  add column if not exists is_monthly boolean not null default false;
