-- 0031_patient_identification.sql
--
-- FASE 2 de cumplimiento (NOM-004): ficha de identificación del paciente.
-- La NOM-004 exige, en la apertura del expediente: nombre, sexo, edad,
-- domicilio, ocupación, CURP (recomendada) y datos del responsable en caso de
-- menores o urgencias. La app ya tiene nombre/sexo/fecha de nacimiento; aquí se
-- agregan los campos faltantes. Todos nullable (CURP y domicilio se piden como
-- recomendados-no-bloqueantes; el resto opcionales).
--
-- Peso/talla son parte de la exploración física (idealmente por consulta); se
-- guardan aquí como referencia BASAL del expediente. Sin cambios de RLS ni de
-- auditoría (patients ya está auditada desde 0002).

alter table public.patients
  add column if not exists curp text,
  add column if not exists address text,                    -- domicilio
  add column if not exists occupation text,                 -- ocupación
  add column if not exists responsible_name text,           -- responsable/tutor
  add column if not exists responsible_relationship text,   -- parentesco
  add column if not exists responsible_phone text,
  add column if not exists weight_kg numeric,               -- peso basal (kg)
  add column if not exists height_cm numeric;               -- talla basal (cm)

comment on column public.patients.curp is
  'CURP del paciente (recomendada por NOM-004). 18 caracteres; validación ligera '
  'en la app, sin restricción de unicidad en BD (puede ser NULL).';
comment on column public.patients.address is 'Domicilio del paciente (NOM-004).';
comment on column public.patients.occupation is 'Ocupación del paciente (NOM-004).';
comment on column public.patients.responsible_name is
  'Nombre del responsable/tutor (para menores o urgencias, NOM-004).';
comment on column public.patients.responsible_relationship is
  'Parentesco/relación del responsable con el paciente.';
comment on column public.patients.weight_kg is
  'Peso basal en kg (exploración física; referencia del expediente).';
comment on column public.patients.height_cm is
  'Talla basal en cm (exploración física; referencia del expediente).';
