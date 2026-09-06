-- =============================================================================
-- KuraTracker - Seed de pacientes de prueba SINTETICOS (piloto)
-- =============================================================================
-- Proposito: poblar el proyecto Supabase real con 6 pacientes ficticios,
-- variados en ETIOLOGIA y en ESCENARIO resultante del motor "Protocolo
-- Kura+" (2x A, 2x B, 2x C), para poder probar el flujo clinico completo
-- de inmediato (login -> paciente -> captura -> tratamiento con sugerencia
-- premium -> seguimiento -> reporte) sin esperar captura manual.
--
-- NINGUN dato aqui corresponde a una persona real. Nombres, telefonos y
-- folios son ficticios.
--
-- REQUISITOS PREVIOS (en este orden):
--   1) Haber aplicado TODAS las migraciones de supabase/migrations/ (desde
--      0011 sites/staff/patients exigen organization_id NOT NULL; este seed
--      lo resuelve solo — ver "ORGANIZACION DESTINO" abajo).
--   2) Crear en Supabase Auth (Authentication > Users) AL MENOS un usuario
--      admin real (con el que haras login), por ejemplo:
--        email: admin@curamas.mx
--      El trigger trg_on_auth_user_created creara automaticamente su fila en
--      public.profiles con role='clinico' por defecto. Sube su rol a admin
--      corriendo, en el SQL Editor, DESPUES de crear el usuario:
--        update public.profiles set role = 'admin' where email = 'admin@curamas.mx';
--   3) Ejecutar este script completo en el SQL Editor de Supabase. Es
--      idempotente-friendly: usa IDs fijos (no gen_random_uuid()) y borra
--      cualquier corrida previa de este mismo seed antes de reinsertar
--      (ver bloque DELETE al inicio), asi que se puede correr varias veces
--      sin duplicar datos ni fallar por folio/unique constraints.
--
-- NOTA DE PERMISOS: este script hace INSERT directo en tablas con RLS
-- habilitado. Debe ejecutarse desde el SQL Editor de Supabase (que usa el
-- rol "postgres", con bypass de RLS), NUNCA desde el cliente Flutter con la
-- anon key.
--
-- NOTA DE DISENO (paridad matematica): "pie_diabetico" y "otra" son
-- exactamente la misma categoria base en el modelo (todas las variables
-- one-hot et_* = 0), asi que el paciente A1 usa 'pie_diabetico' sin que
-- esto cambie ninguna probabilidad frente a 'otra'.
--
-- Los 6 escenarios fueron validados con una replica Python exacta de
-- assets/engine/kura_model_v2.json + kura_clinical_adjustments.json
-- (mismos coeficientes, mismo pipeline z-score -> score lineal -> ajustes
-- ITB/ALB -> softmax que lib/engine/*.dart), por lo que las probabilidades
-- prob_a/prob_b/prob_c insertadas abajo en kura_recommendations coinciden
-- con lo que el motor Dart calcularia para estos mismos datos de entrada:
--
--   Paciente          Escenario dominante   probs (A / B / C)
--   ----------------  --------------------  --------------------------
--   A1 Roberto (pie diabetico, pequena)   A   0.740061 / 0.164546 / 0.095397
--   A2 Marisol (traumatica, pequena)      A   0.547489 / 0.386043 / 0.066468
--   B1 Fernando (traumatica, mediana)     B   0.137385 / 0.722206 / 0.140408
--   B2 Herminia (LPP, ITB moderado)       B   0.141259 / 0.513370 / 0.345371
--   C1 Alicia (vascular, isquemia critica)C   0.000782 / 0.001421 / 0.997798
--   C2 Jose Luis (quirurgica, WUWHS alto) C   0.205997 / 0.218079 / 0.575923
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 00. ORGANIZACION DESTINO (multi-centro, desde la migracion 0011)
-- -----------------------------------------------------------------------------
-- sites / staff / patients llevan organization_id NOT NULL. Este seed resuelve
-- la organizacion destino UNA vez, en la tabla temporal seed_ctx, y todos los
-- INSERT la leen con (select org_id from seed_ctx):
--   * Por defecto: la organizacion mas antigua (Kura+, la que crea 0011) —
--     mismo criterio que handle_new_auth_user().
--   * Para dirigirlo a OTRO centro (p. ej. el sandbox), fija antes en la misma
--     sesion:  set kt.seed_org_id = '<uuid de la organizacion>';
--     (seed_sandbox.sql lo hace por ti.)
create temp table if not exists seed_ctx on commit preserve rows as
select coalesce(
  nullif(current_setting('kt.seed_org_id', true), '')::uuid,
  (select id from public.organizations order by created_at asc limit 1)
) as org_id;

do $$
begin
  if (select org_id from seed_ctx) is null then
    raise exception 'seed_synthetic_patients: no hay ninguna organizacion; aplica las migraciones primero.';
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- 0. LIMPIEZA DE CORRIDAS PREVIAS DE ESTE SEED (idempotencia)
-- -----------------------------------------------------------------------------
-- Se identifican por el patron de folio 'SEED-...' y se borran en cascada
-- (las FK on delete cascade se encargan de wounds/consultations/etc. de
-- estos pacientes; los folios de personal/sitio de seed tambien se limpian).

-- Las consultas FINALIZADAS son inmutables por trigger (0097) y el borrado en
-- cascada del paciente las toca. Como esto es limpieza de datos SINTETICOS de
-- una corrida previa del mismo seed, se apaga el candado solo durante el
-- DELETE y se vuelve a encender de inmediato (patron indicado en la 0097).
alter table public.consultations disable trigger trg_prevent_finalized_consultation_change;
delete from public.patients where folio like 'SEED-%';
alter table public.consultations enable trigger trg_prevent_finalized_consultation_change;
delete from public.staff where folio = 'SEED-K0001';
delete from public.sites where name = 'Kura+ Piloto (sede semilla)';

-- -----------------------------------------------------------------------------
-- 1. SITIO Y PERSONAL DE PRUEBA (para poder asignar los 6 pacientes)
-- -----------------------------------------------------------------------------
-- Si tu clinica ya tiene sitios/personal reales, puedes ignorar estos dos
-- registros y reasignar los pacientes de abajo a tu staff real cambiando
-- los valores '00000000-0000-4000-a000-0000000000s1' / '...s2' por los ids
-- de tu propio personal en la tabla staff_patient_assignments.

insert into public.sites (id, name, kind, address, is_active, organization_id)
values (
  '00000000-0000-4000-a000-000000000001',
  'Kura+ Piloto (sede semilla)',
  'clinica',
  'Sede de pruebas - datos sinteticos',
  true,
  (select org_id from seed_ctx)
);

-- staff sin profile_id (no vinculado a ningun usuario de auth.users): sirve
-- solo para poder asignar pacientes de prueba sin depender de que un
-- clinico real ya se haya registrado. Un admin puede reasignar despues.
insert into public.staff (id, profile_id, folio, full_name, role_title, primary_site_id, is_active, organization_id)
values (
  '00000000-0000-4000-a000-000000000002',
  null,
  'SEED-K0001',
  'Kurador de pruebas (semilla)',
  'Kurador',
  '00000000-0000-4000-a000-000000000001',
  true,
  (select org_id from seed_ctx)
);

-- -----------------------------------------------------------------------------
-- 2. PACIENTE A1 - Roberto Sanchez Lopez (pie diabetico, escenario A)
-- -----------------------------------------------------------------------------
-- Herida pequena (2.5x2.0cm=5cm2), sin necrosis, esfacelo minimo (5%),
-- ITB alto (0.90 -> sin isquemia), albumina normal (3.9), 1 comorbilidad
-- (diabetes mellitus, coherente con la etiologia). Cierre rapido esperado.

insert into public.patients (
  id, folio, full_name, birth_date, sex, primary_site_id, mobility,
  has_identified_caregiver, caregiver_name, caregiver_phone, fragile_patient,
  background_notes, is_active, organization_id
) values (
  '10000000-0000-4000-a000-000000000001',
  'SEED-PA2026-0001',
  'Roberto Sanchez Lopez',
  '1958-03-12',
  'M',
  '00000000-0000-4000-a000-000000000001',
  'ambulatorio',
  true,
  'Maria Sanchez (hija)',
  '555-0101',
  false,
  'PACIENTE SINTETICO (piloto). Diabetes mellitus tipo 2 de 12 anos de '
  'evolucion, control glucemico aceptable. Herida de pie diabetico de '
  'inicio reciente, sin signos de isquemia.',
  true,
  (select org_id from seed_ctx)
);

insert into public.staff_patient_assignments (id, staff_id, patient_id)
values (
  '10000000-0000-4000-a000-100000000001',
  '00000000-0000-4000-a000-000000000002',
  '10000000-0000-4000-a000-000000000001'
);

insert into public.patient_comorbidities (id, patient_id, code, status)
values (
  '10000000-0000-4000-a000-200000000001',
  '10000000-0000-4000-a000-000000000001',
  'diabetes_mellitus',
  'presente'
);

insert into public.wounds (
  id, patient_id, etiology, subtype, body_location_primary, onset_date,
  wagner_grade, is_active
) values (
  '10000000-0000-4000-a000-300000000001',
  '10000000-0000-4000-a000-000000000001',
  'pie_diabetico',
  'neuropatica',
  'pie_derecho_planta',
  current_date - interval '10 days',
  'g1',
  true
);

insert into public.consultations (
  id, patient_id, staff_id, site_id, visit_type, visit_date, vital_signs, is_draft
) values (
  '10000000-0000-4000-a000-400000000001',
  '10000000-0000-4000-a000-000000000001',
  '00000000-0000-4000-a000-000000000002',
  '00000000-0000-4000-a000-000000000001',
  'valoracion',
  current_date - interval '10 days',
  '{"ta":"128/82","fc":76,"temp":36.6,"glucosa_capilar":142}'::jsonb,
  false
);

insert into public.wound_assessments (
  id, consultation_id, wound_id, glucose_mg_dl, first_assessment_date, edema,
  pain, pain_type, pain_duration, pain_vas, exudate_type, exudate_amount,
  infection_criteria, odor, wound_edge, perilesional_skin
) values (
  '10000000-0000-4000-a000-500000000001',
  '10000000-0000-4000-a000-400000000001',
  '10000000-0000-4000-a000-300000000001',
  142,
  current_date - interval '10 days',
  'leve',
  true,
  'neuropatico',
  'intermitente',
  2,
  'seroso',
  'escaso',
  '{}',
  'ninguno',
  'definido',
  '{seca}'
);

insert into public.wound_measurements (
  id, wound_id, consultation_id, measured_at, length_cm, width_cm, area_cm2,
  depth_cm, tunneling, undermining, granulation_pct, slough_pct, necrosis_pct,
  epithelialization_pct, captured_before_debridement
) values (
  '10000000-0000-4000-a000-600000000001',
  '10000000-0000-4000-a000-300000000001',
  '10000000-0000-4000-a000-400000000001',
  current_date - interval '10 days',
  2.5, 2.0, 5.0,
  0.1, false, false,
  85, 5, 0, 10,
  true
);

insert into public.perfusion_nutrition_data (
  id, consultation_id, wound_id, abi_right, abi_left, is_lower_extremity, albumin_g_dl
) values (
  '10000000-0000-4000-a000-700000000001',
  '10000000-0000-4000-a000-400000000001',
  '10000000-0000-4000-a000-300000000001',
  0.90, 0.92, true, 3.9
);

-- Plan de tratamiento con "Utilizar protocolo Kura+" activado, sugerido por
-- el motor y aceptado sin ediciones (origin='kura_suggested' en todos).
insert into public.treatment_plans (
  id, consultation_id, wound_id, used_kura_protocol, final_description
) values (
  '10000000-0000-4000-a000-800000000001',
  '10000000-0000-4000-a000-400000000001',
  '10000000-0000-4000-a000-300000000001',
  true,
  E'Plan sugerido por Protocolo Kura+ (escenario A - Cierre rapido):\n'
  '- Limpieza de la herida: Solucion salina / Prontosan\n'
  '- Dispositivo de descarga: Calzado terapeutico / plantilla de descarga\n'
  '- Manejo neuropatico: Evaluacion de sensibilidad + control glucemico estrecho\n'
  '- Proteccion de la piel: Pelicula barrera / oxido de zinc'
);

insert into public.treatment_components (id, treatment_plan_id, method, product, origin, sort_order)
values
  ('10000000-0000-4000-a000-900000000001', '10000000-0000-4000-a000-800000000001', 'Limpieza de la herida', 'Solucion salina / Prontosan', 'kura_suggested', 0),
  ('10000000-0000-4000-a000-900000000002', '10000000-0000-4000-a000-800000000001', 'Dispositivo de descarga', 'Calzado terapeutico / plantilla de descarga', 'kura_suggested', 1),
  ('10000000-0000-4000-a000-900000000003', '10000000-0000-4000-a000-800000000001', 'Manejo neuropatico', 'Evaluacion de sensibilidad + control glucemico estrecho', 'kura_suggested', 2),
  ('10000000-0000-4000-a000-900000000004', '10000000-0000-4000-a000-800000000001', 'Proteccion de la piel', 'Pelicula barrera / oxido de zinc', 'kura_suggested', 3);

insert into public.kura_recommendations (
  id, consultation_id, wound_id, treatment_plan_id, model_version,
  adjustments_version, rules_version, prob_a, prob_b, prob_c,
  dominant_scenario, commercial_phenotype, regimen, interconsultas, alertas,
  debug_features, debug_raw_scores, clinician_decision, clinician_decision_at
) values (
  '10000000-0000-4000-a000-a00000000001',
  '10000000-0000-4000-a000-400000000001',
  '10000000-0000-4000-a000-300000000001',
  '10000000-0000-4000-a000-800000000001',
  'kura_model_v2',
  'kura_adjustments_v1',
  'kura_rules_v1',
  0.740061, 0.164546, 0.095397,
  'A',
  'A1 - Cierre Activo',
  '[
    {"metodo":"Limpieza de la herida","producto":"Solucion salina / Prontosan","justificacion":"Limpieza en cada cambio de aposito (regla base).","es_alerta":false},
    {"metodo":"Dispositivo de descarga","producto":"Calzado terapeutico / plantilla de descarga","justificacion":"Pie diabetico, grado Wagner G1.","es_alerta":false},
    {"metodo":"Manejo neuropatico","producto":"Evaluacion de sensibilidad + control glucemico estrecho","justificacion":"Pie diabetico: manejo neuropatico integral.","es_alerta":false},
    {"metodo":"Proteccion de la piel","producto":"Pelicula barrera / oxido de zinc","justificacion":"Piel perilesional en riesgo: seca.","es_alerta":false}
  ]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '{"logarea":1.791759,"necrosis_f":0,"esfacelo_f":5,"depth_f":0.1,"n_comorb_struct":1,"et_lpp":0,"et_vasc":0,"et_quir":0,"et_traum":0}'::jsonb,
  '{"A":0.084071,"B":-0.619465,"C":0.535395}'::jsonb,
  'aceptada',
  now() - interval '10 days'
);

-- Consulta de seguimiento (semana 4) con reduccion de area consistente con
-- escenario A (cierre rapido: reduccion >= 50% => confirmar_cierre).
insert into public.consultations (
  id, patient_id, staff_id, site_id, visit_type, visit_date, vital_signs, is_draft
) values (
  '10000000-0000-4000-a000-b00000000001',
  '10000000-0000-4000-a000-000000000001',
  '00000000-0000-4000-a000-000000000002',
  '00000000-0000-4000-a000-000000000001',
  'seguimiento',
  current_date - interval '10 days' + interval '28 days',
  '{"ta":"122/78","fc":74,"temp":36.5,"glucosa_capilar":118}'::jsonb,
  false
);

insert into public.wound_measurements (
  id, wound_id, consultation_id, measured_at, length_cm, width_cm, area_cm2,
  depth_cm, tunneling, undermining, granulation_pct, slough_pct, necrosis_pct,
  epithelialization_pct, captured_before_debridement
) values (
  '10000000-0000-4000-a000-600000000002',
  '10000000-0000-4000-a000-300000000001',
  '10000000-0000-4000-a000-b00000000001',
  current_date - interval '10 days' + interval '28 days',
  1.1, 0.9, 0.99,
  0.0, false, false,
  95, 0, 0, 5,
  true
);

insert into public.sheehan_checkpoints (
  id, wound_id, consultation_id, week_number, baseline_area_cm2, current_area_cm2,
  raw_reduction_pct, adjusted_reduction_pct, closure_threshold_pct, alert_threshold_pct,
  decision, penalties_applied
) values (
  '10000000-0000-4000-a000-c00000000001',
  '10000000-0000-4000-a000-300000000001',
  '10000000-0000-4000-a000-b00000000001',
  4,
  5.0, 0.99,
  80.2, 80.2, 50, 30,
  'confirmar_cierre',
  '{}'
);

-- -----------------------------------------------------------------------------
-- 3. PACIENTE A2 - Marisol Fuentes Reyes (traumatica, escenario A)
-- -----------------------------------------------------------------------------
-- Herida traumatica pequena (3.0x2.5cm=7.5cm2), sin comorbilidades, ITB
-- alto, albumina normal. Agente causal punzocortante, sin criterios de
-- infeccion. Cierre rapido esperado.

insert into public.patients (
  id, folio, full_name, birth_date, sex, primary_site_id, mobility,
  has_identified_caregiver, caregiver_name, caregiver_phone, fragile_patient,
  background_notes, is_active, organization_id
) values (
  '10000000-0000-4000-a000-000000000002',
  'SEED-PA2026-0002',
  'Marisol Fuentes Reyes',
  '1990-11-20',
  'F',
  '00000000-0000-4000-a000-000000000001',
  'ambulatorio',
  false,
  null,
  null,
  false,
  'PACIENTE SINTETICO (piloto). Sin antecedentes relevantes. Herida '
  'traumatica punzocortante en antebrazo, atendida el mismo dia del evento.',
  true,
  (select org_id from seed_ctx)
);

insert into public.staff_patient_assignments (id, staff_id, patient_id)
values (
  '10000000-0000-4000-a000-100000000002',
  '00000000-0000-4000-a000-000000000002',
  '10000000-0000-4000-a000-000000000002'
);

insert into public.wounds (
  id, patient_id, etiology, subtype, body_location_primary, onset_date,
  agente_causal, is_active
) values (
  '10000000-0000-4000-a000-300000000002',
  '10000000-0000-4000-a000-000000000002',
  'traumatica',
  'punzocortante_reciente',
  'antebrazo_izquierdo',
  current_date - interval '3 days',
  'punzocortante',
  true
);

insert into public.consultations (
  id, patient_id, staff_id, site_id, visit_type, visit_date, vital_signs, is_draft
) values (
  '10000000-0000-4000-a000-400000000002',
  '10000000-0000-4000-a000-000000000002',
  '00000000-0000-4000-a000-000000000002',
  '00000000-0000-4000-a000-000000000001',
  'valoracion',
  current_date - interval '3 days',
  '{"ta":"110/70","fc":72,"temp":36.4}'::jsonb,
  false
);

insert into public.wound_assessments (
  id, consultation_id, wound_id, first_assessment_date, edema, pain, pain_vas,
  exudate_type, exudate_amount, infection_criteria, odor, wound_edge, perilesional_skin
) values (
  '10000000-0000-4000-a000-500000000002',
  '10000000-0000-4000-a000-400000000002',
  '10000000-0000-4000-a000-300000000002',
  current_date - interval '3 days',
  'ninguno',
  true,
  3,
  'seroso',
  'escaso',
  '{}',
  'ninguno',
  'definido',
  '{normal}'
);

insert into public.wound_measurements (
  id, wound_id, consultation_id, measured_at, length_cm, width_cm, area_cm2,
  depth_cm, tunneling, undermining, granulation_pct, slough_pct, necrosis_pct,
  epithelialization_pct, captured_before_debridement
) values (
  '10000000-0000-4000-a000-600000000003',
  '10000000-0000-4000-a000-300000000002',
  '10000000-0000-4000-a000-400000000002',
  current_date - interval '3 days',
  3.0, 2.5, 7.5,
  0.15, false, false,
  80, 8, 0, 12,
  true
);

insert into public.perfusion_nutrition_data (
  id, consultation_id, wound_id, abi_right, abi_left, is_lower_extremity, albumin_g_dl
) values (
  '10000000-0000-4000-a000-700000000002',
  '10000000-0000-4000-a000-400000000002',
  '10000000-0000-4000-a000-300000000002',
  0.95, 0.95, false, 4.0
);

insert into public.treatment_plans (
  id, consultation_id, wound_id, used_kura_protocol, final_description
) values (
  '10000000-0000-4000-a000-800000000002',
  '10000000-0000-4000-a000-400000000002',
  '10000000-0000-4000-a000-300000000002',
  true,
  E'Plan sugerido por Protocolo Kura+ (escenario A - Cierre rapido):\n'
  '- Limpieza de la herida: Solucion salina / Prontosan\n'
  '- Manejo de herida punzocortante: Exploracion de estructuras profundas + cierre segun caso'
);

insert into public.treatment_components (id, treatment_plan_id, method, product, origin, sort_order)
values
  ('10000000-0000-4000-a000-900000000005', '10000000-0000-4000-a000-800000000002', 'Limpieza de la herida', 'Solucion salina / Prontosan', 'kura_suggested', 0),
  ('10000000-0000-4000-a000-900000000006', '10000000-0000-4000-a000-800000000002', 'Manejo de herida punzocortante', 'Exploracion de estructuras profundas + cierre segun caso', 'kura_suggested', 1);

insert into public.kura_recommendations (
  id, consultation_id, wound_id, treatment_plan_id, model_version,
  adjustments_version, rules_version, prob_a, prob_b, prob_c,
  dominant_scenario, commercial_phenotype, regimen, interconsultas, alertas,
  debug_features, debug_raw_scores, clinician_decision, clinician_decision_at
) values (
  '10000000-0000-4000-a000-a00000000002',
  '10000000-0000-4000-a000-400000000002',
  '10000000-0000-4000-a000-300000000002',
  '10000000-0000-4000-a000-800000000002',
  'kura_model_v2',
  'kura_adjustments_v1',
  'kura_rules_v1',
  0.547489, 0.386043, 0.066468,
  'A',
  'A1 - Cierre Activo',
  '[
    {"metodo":"Limpieza de la herida","producto":"Solucion salina / Prontosan","justificacion":"Limpieza en cada cambio de aposito (regla base).","es_alerta":false},
    {"metodo":"Manejo de herida punzocortante","producto":"Exploracion de estructuras profundas + cierre segun caso","justificacion":"Agente causal: punzocortante.","es_alerta":false}
  ]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '{"logarea":2.140066,"necrosis_f":0,"esfacelo_f":8,"depth_f":0.15,"n_comorb_struct":0,"et_lpp":0,"et_vasc":0,"et_quir":0,"et_traum":1}'::jsonb,
  '{"A":-0.280662,"B":0.169944,"C":0.110718}'::jsonb,
  'aceptada',
  now() - interval '3 days'
);

-- -----------------------------------------------------------------------------
-- 4. PACIENTE B1 - Fernando Castillo Reyna (traumatica, escenario B)
-- -----------------------------------------------------------------------------
-- Herida traumatica mediana (5.0x4.0cm=20cm2), sin comorbilidades, ITB
-- moderado (0.60, sin isquemia critica pero con perfusion reducida).
-- Cierre asistido prolongado esperado (4-6+ meses).

insert into public.patients (
  id, folio, full_name, birth_date, sex, primary_site_id, mobility,
  has_identified_caregiver, caregiver_name, caregiver_phone, fragile_patient,
  background_notes, is_active, organization_id
) values (
  '10000000-0000-4000-a000-000000000003',
  'SEED-PA2026-0003',
  'Fernando Castillo Reyna',
  '1975-06-02',
  'M',
  '00000000-0000-4000-a000-000000000001',
  'ambulatorio',
  false,
  null,
  null,
  false,
  'PACIENTE SINTETICO (piloto). Sin comorbilidades registradas. Herida '
  'traumatica por aplastamiento en pierna, con perfusion reducida (ITB '
  'moderado) que amerita seguimiento prolongado.',
  true,
  (select org_id from seed_ctx)
);

insert into public.staff_patient_assignments (id, staff_id, patient_id)
values (
  '10000000-0000-4000-a000-100000000003',
  '00000000-0000-4000-a000-000000000002',
  '10000000-0000-4000-a000-000000000003'
);

insert into public.wounds (
  id, patient_id, etiology, subtype, body_location_primary, onset_date,
  agente_causal, is_active
) values (
  '10000000-0000-4000-a000-300000000003',
  '10000000-0000-4000-a000-000000000003',
  'traumatica',
  'aplastamiento_subagudo',
  'pierna_izquierda_maleolo',
  current_date - interval '18 days',
  'aplastamiento',
  true
);

insert into public.consultations (
  id, patient_id, staff_id, site_id, visit_type, visit_date, vital_signs, is_draft
) values (
  '10000000-0000-4000-a000-400000000003',
  '10000000-0000-4000-a000-000000000003',
  '00000000-0000-4000-a000-000000000002',
  '00000000-0000-4000-a000-000000000001',
  'valoracion',
  current_date - interval '18 days',
  '{"ta":"130/85","fc":80,"temp":36.7}'::jsonb,
  false
);

insert into public.wound_assessments (
  id, consultation_id, wound_id, first_assessment_date, edema, pain, pain_vas,
  exudate_type, exudate_amount, infection_criteria, odor, wound_edge, perilesional_skin
) values (
  '10000000-0000-4000-a000-500000000003',
  '10000000-0000-4000-a000-400000000003',
  '10000000-0000-4000-a000-300000000003',
  current_date - interval '18 days',
  'moderado',
  true,
  5,
  'serosanguinolento',
  'moderado',
  '{}',
  'ninguno',
  'irregular',
  '{eritematosa}'
);

insert into public.wound_measurements (
  id, wound_id, consultation_id, measured_at, length_cm, width_cm, area_cm2,
  depth_cm, tunneling, undermining, granulation_pct, slough_pct, necrosis_pct,
  epithelialization_pct, captured_before_debridement
) values (
  '10000000-0000-4000-a000-600000000004',
  '10000000-0000-4000-a000-300000000003',
  '10000000-0000-4000-a000-400000000003',
  current_date - interval '18 days',
  5.0, 4.0, 20.0,
  0.2, false, false,
  60, 10, 0, 30,
  true
);

insert into public.perfusion_nutrition_data (
  id, consultation_id, wound_id, abi_right, abi_left, is_lower_extremity, albumin_g_dl
) values (
  '10000000-0000-4000-a000-700000000003',
  '10000000-0000-4000-a000-400000000003',
  '10000000-0000-4000-a000-300000000003',
  0.68, 0.60, true, 3.8
);

insert into public.treatment_plans (
  id, consultation_id, wound_id, used_kura_protocol, final_description
) values (
  '10000000-0000-4000-a000-800000000003',
  '10000000-0000-4000-a000-400000000003',
  '10000000-0000-4000-a000-300000000003',
  true,
  E'Plan sugerido por Protocolo Kura+ (escenario B - Cierre asistido prolongado):\n'
  '- Limpieza de la herida: Solucion salina / Prontosan\n'
  '- Desbridamiento: Cortante / combinado\n'
  '- Aposito: Espuma con borde adhesivo / alta absorcion\n'
  '- Manejo de herida por aplastamiento: Vigilancia de sindrome compartimental + manejo de tejidos'
);

insert into public.treatment_components (id, treatment_plan_id, method, product, origin, sort_order)
values
  ('10000000-0000-4000-a000-900000000007', '10000000-0000-4000-a000-800000000003', 'Limpieza de la herida', 'Solucion salina / Prontosan', 'kura_suggested', 0),
  ('10000000-0000-4000-a000-900000000008', '10000000-0000-4000-a000-800000000003', 'Desbridamiento', 'Cortante / combinado', 'kura_suggested', 1),
  ('10000000-0000-4000-a000-900000000009', '10000000-0000-4000-a000-800000000003', 'Aposito', 'Espuma con borde adhesivo / alta absorcion', 'kura_suggested', 2),
  ('10000000-0000-4000-a000-90000000000a', '10000000-0000-4000-a000-800000000003', 'Manejo de herida por aplastamiento', 'Vigilancia de sindrome compartimental + manejo de tejidos', 'kura_suggested', 3);

insert into public.kura_recommendations (
  id, consultation_id, wound_id, treatment_plan_id, model_version,
  adjustments_version, rules_version, prob_a, prob_b, prob_c,
  dominant_scenario, commercial_phenotype, regimen, interconsultas, alertas,
  debug_features, debug_raw_scores, clinician_decision, clinician_decision_at
) values (
  '10000000-0000-4000-a000-a00000000003',
  '10000000-0000-4000-a000-400000000003',
  '10000000-0000-4000-a000-300000000003',
  '10000000-0000-4000-a000-800000000003',
  'kura_model_v2',
  'kura_adjustments_v1',
  'kura_rules_v1',
  0.137385, 0.722206, 0.140408,
  'B',
  'A2/A3 - Integral',
  '[
    {"metodo":"Limpieza de la herida","producto":"Solucion salina / Prontosan","justificacion":"Limpieza en cada cambio de aposito (regla base).","es_alerta":false},
    {"metodo":"Desbridamiento","producto":"Cortante / combinado","justificacion":"Esfacelo + necrosis = 10% (>=15% no alcanzado, revisar umbral en captura real) y sin isquemia critica.","es_alerta":false},
    {"metodo":"Aposito","producto":"Espuma con borde adhesivo / alta absorcion","justificacion":"Exudado moderado: requiere aposito secundario absorbente.","es_alerta":false},
    {"metodo":"Manejo de herida por aplastamiento","producto":"Vigilancia de sindrome compartimental + manejo de tejidos","justificacion":"Agente causal: aplastamiento.","es_alerta":false}
  ]'::jsonb,
  '[
    {"especialidad":"Cirugia / Ortopedia","motivo":"Herida por aplastamiento: descartar sindrome compartimental.","es_urgente":true}
  ]'::jsonb,
  '[]'::jsonb,
  '{"logarea":3.044522,"necrosis_f":0,"esfacelo_f":10,"depth_f":0.2,"n_comorb_struct":0,"et_lpp":0,"et_vasc":0,"et_quir":0,"et_traum":1}'::jsonb,
  '{"A":-0.393762,"B":0.165759,"C":0.228003}'::jsonb,
  'aceptada',
  now() - interval '18 days'
);

-- Consulta de seguimiento (semana 4) con reduccion moderada, coherente con
-- escenario B (extender_observacion: reduccion entre 30% y 50%).
insert into public.consultations (
  id, patient_id, staff_id, site_id, visit_type, visit_date, vital_signs, is_draft
) values (
  '10000000-0000-4000-a000-b00000000003',
  '10000000-0000-4000-a000-000000000003',
  '00000000-0000-4000-a000-000000000002',
  '00000000-0000-4000-a000-000000000001',
  'seguimiento',
  current_date - interval '18 days' + interval '28 days',
  '{"ta":"128/82","fc":78,"temp":36.5}'::jsonb,
  false
);

insert into public.wound_measurements (
  id, wound_id, consultation_id, measured_at, length_cm, width_cm, area_cm2,
  depth_cm, tunneling, undermining, granulation_pct, slough_pct, necrosis_pct,
  epithelialization_pct, captured_before_debridement
) values (
  '10000000-0000-4000-a000-600000000005',
  '10000000-0000-4000-a000-300000000003',
  '10000000-0000-4000-a000-b00000000003',
  current_date - interval '18 days' + interval '28 days',
  3.8, 3.2, 12.16,
  0.15, false, false,
  75, 5, 0, 20,
  true
);

insert into public.sheehan_checkpoints (
  id, wound_id, consultation_id, week_number, baseline_area_cm2, current_area_cm2,
  raw_reduction_pct, adjusted_reduction_pct, closure_threshold_pct, alert_threshold_pct,
  decision, penalties_applied
) values (
  '10000000-0000-4000-a000-c00000000003',
  '10000000-0000-4000-a000-300000000003',
  '10000000-0000-4000-a000-b00000000003',
  4,
  20.0, 12.16,
  39.2, 39.2, 50, 30,
  'extender_observacion',
  '{}'
);

-- -----------------------------------------------------------------------------
-- 5. PACIENTE B2 - Herminia Torres Vazquez (LPP, escenario B)
-- -----------------------------------------------------------------------------
-- LPP en region sacra (paciente con movilidad reducida = comorbilidad
-- estructural), herida mediana (4.0x3.0cm=12cm2) con esfacelo 30% y
-- necrosis leve 5%, ITB moderado, albumina no evaluada. Cierre asistido
-- prolongado esperado.

insert into public.patients (
  id, folio, full_name, birth_date, sex, primary_site_id, mobility,
  has_identified_caregiver, caregiver_name, caregiver_phone, fragile_patient,
  background_notes, is_active, organization_id
) values (
  '10000000-0000-4000-a000-000000000004',
  'SEED-PA2026-0004',
  'Herminia Torres Vazquez',
  '1938-09-14',
  'F',
  '00000000-0000-4000-a000-000000000001',
  'encamado',
  true,
  'Josefina Torres (nieta)',
  '555-0104',
  true,
  'PACIENTE SINTETICO (piloto). Paciente fragil, encamada, con LPP sacra '
  'de evolucion subaguda. Movilidad reducida registrada como comorbilidad '
  'estructural para el motor.',
  true,
  (select org_id from seed_ctx)
);

insert into public.staff_patient_assignments (id, staff_id, patient_id)
values (
  '10000000-0000-4000-a000-100000000004',
  '00000000-0000-4000-a000-000000000002',
  '10000000-0000-4000-a000-000000000004'
);

insert into public.patient_comorbidities (id, patient_id, code, status)
values (
  '10000000-0000-4000-a000-200000000004',
  '10000000-0000-4000-a000-000000000004',
  'movilidad_reducida',
  'presente'
);

insert into public.wounds (
  id, patient_id, etiology, subtype, body_location_primary, onset_date, is_active
) values (
  '10000000-0000-4000-a000-300000000004',
  '10000000-0000-4000-a000-000000000004',
  'lpp',
  'categoria_iii',
  'sacro',
  current_date - interval '25 days',
  true
);

insert into public.consultations (
  id, patient_id, staff_id, site_id, visit_type, visit_date, vital_signs, is_draft
) values (
  '10000000-0000-4000-a000-400000000004',
  '10000000-0000-4000-a000-000000000004',
  '00000000-0000-4000-a000-000000000002',
  '00000000-0000-4000-a000-000000000001',
  'valoracion',
  current_date - interval '25 days',
  '{"ta":"118/76","fc":82,"temp":36.6}'::jsonb,
  false
);

insert into public.wound_assessments (
  id, consultation_id, wound_id, first_assessment_date, edema, pain, pain_vas,
  exudate_type, exudate_amount, infection_criteria, odor, wound_edge, perilesional_skin
) values (
  '10000000-0000-4000-a000-500000000004',
  '10000000-0000-4000-a000-400000000004',
  '10000000-0000-4000-a000-300000000004',
  current_date - interval '25 days',
  'leve',
  false,
  0,
  'serosanguinolento',
  'moderado',
  '{}',
  'leve',
  'irregular',
  '{macerada}'
);

insert into public.wound_measurements (
  id, wound_id, consultation_id, measured_at, length_cm, width_cm, area_cm2,
  depth_cm, tunneling, undermining, granulation_pct, slough_pct, necrosis_pct,
  epithelialization_pct, captured_before_debridement
) values (
  '10000000-0000-4000-a000-600000000006',
  '10000000-0000-4000-a000-300000000004',
  '10000000-0000-4000-a000-400000000004',
  current_date - interval '25 days',
  4.0, 3.0, 12.0,
  0.3, false, false,
  55, 30, 5, 10,
  true
);

insert into public.perfusion_nutrition_data (
  id, consultation_id, wound_id, abi_right, abi_left, is_lower_extremity, albumin_g_dl
) values (
  '10000000-0000-4000-a000-700000000004',
  '10000000-0000-4000-a000-400000000004',
  '10000000-0000-4000-a000-300000000004',
  0.65, 0.70, true, null
);

insert into public.treatment_plans (
  id, consultation_id, wound_id, used_kura_protocol, final_description
) values (
  '10000000-0000-4000-a000-800000000004',
  '10000000-0000-4000-a000-400000000004',
  '10000000-0000-4000-a000-300000000004',
  true,
  E'Plan sugerido por Protocolo Kura+ (escenario B - Cierre asistido prolongado):\n'
  '- Limpieza de la herida: Solucion salina / Prontosan\n'
  '- Desbridamiento: Autolitico / enzimatico / mecanico\n'
  '- Aposito: Espuma con borde adhesivo / alta absorcion\n'
  '- Proteccion de la piel: Pelicula barrera / oxido de zinc\n'
  '- Educacion al paciente/cuidador: Material educativo + demostracion practica'
);

insert into public.treatment_components (id, treatment_plan_id, method, product, origin, sort_order)
values
  ('10000000-0000-4000-a000-90000000000b', '10000000-0000-4000-a000-800000000004', 'Limpieza de la herida', 'Solucion salina / Prontosan', 'kura_suggested', 0),
  ('10000000-0000-4000-a000-90000000000c', '10000000-0000-4000-a000-800000000004', 'Desbridamiento', 'Autolitico / enzimatico / mecanico', 'kura_suggested', 1),
  ('10000000-0000-4000-a000-90000000000d', '10000000-0000-4000-a000-800000000004', 'Aposito', 'Espuma con borde adhesivo / alta absorcion', 'kura_suggested', 2),
  ('10000000-0000-4000-a000-90000000000e', '10000000-0000-4000-a000-800000000004', 'Proteccion de la piel', 'Pelicula barrera / oxido de zinc', 'kura_suggested', 3),
  ('10000000-0000-4000-a000-90000000000f', '10000000-0000-4000-a000-800000000004', 'Educacion al paciente/cuidador', 'Material educativo + demostracion practica', 'kura_suggested', 4);

insert into public.kura_recommendations (
  id, consultation_id, wound_id, treatment_plan_id, model_version,
  adjustments_version, rules_version, prob_a, prob_b, prob_c,
  dominant_scenario, commercial_phenotype, regimen, interconsultas, alertas,
  debug_features, debug_raw_scores, clinician_decision, clinician_decision_at
) values (
  '10000000-0000-4000-a000-a00000000004',
  '10000000-0000-4000-a000-400000000004',
  '10000000-0000-4000-a000-300000000004',
  '10000000-0000-4000-a000-800000000004',
  'kura_model_v2',
  'kura_adjustments_v1',
  'kura_rules_v1',
  0.141259, 0.513370, 0.345371,
  'B',
  'A2/A3 - Integral',
  '[
    {"metodo":"Limpieza de la herida","producto":"Solucion salina / Prontosan","justificacion":"Limpieza en cada cambio de aposito (regla base).","es_alerta":false},
    {"metodo":"Desbridamiento","producto":"Autolitico / enzimatico / mecanico","justificacion":"Esfacelo + necrosis = 35% (>=15%) y sin isquemia critica. Metodo segun entorno (clinica).","es_alerta":false},
    {"metodo":"Aposito","producto":"Espuma con borde adhesivo / alta absorcion","justificacion":"Exudado moderado: requiere aposito secundario absorbente.","es_alerta":false},
    {"metodo":"Proteccion de la piel","producto":"Pelicula barrera / oxido de zinc","justificacion":"Piel perilesional en riesgo: macerada.","es_alerta":false},
    {"metodo":"Educacion al paciente/cuidador","producto":"Material educativo + demostracion practica","justificacion":"cuidador identificado, etiologia LPP.","es_alerta":false}
  ]'::jsonb,
  '[]'::jsonb,
  '[]'::jsonb,
  '{"logarea":2.564949,"necrosis_f":5,"esfacelo_f":30,"depth_f":0.3,"n_comorb_struct":1,"et_lpp":1,"et_vasc":0,"et_quir":0,"et_traum":0}'::jsonb,
  '{"A":-0.194806,"B":-0.304408,"C":0.499214}'::jsonb,
  'aceptada',
  now() - interval '25 days'
);

-- -----------------------------------------------------------------------------
-- 6. PACIENTE C1 - Alicia Mendez Guerrero (vascular, escenario C, isquemia
--    CRITICA -- caso de seguridad para probar la alerta ABI<0.5)
-- -----------------------------------------------------------------------------
-- Ulcera vascular extensa (7.0x6.0cm=42cm2), necrosis 45%, ITB 0.32
-- (isquemia critica: el motor de reglas NUNCA debe sugerir desbridamiento
-- ni compresion, y debe generar interconsulta urgente a angiologia).
-- 2 comorbilidades (enfermedad arterial periferica + tabaquismo activo),
-- albumina baja (2.6). No cierre esperado / manejo de confort.

insert into public.patients (
  id, folio, full_name, birth_date, sex, primary_site_id, mobility,
  has_identified_caregiver, caregiver_name, caregiver_phone, fragile_patient,
  background_notes, is_active, organization_id
) values (
  '10000000-0000-4000-a000-000000000005',
  'SEED-PA2026-0005',
  'Alicia Mendez Guerrero',
  '1945-01-30',
  'F',
  '00000000-0000-4000-a000-000000000001',
  'silla_ruedas',
  true,
  'Ruben Mendez (hijo)',
  '555-0105',
  true,
  'PACIENTE SINTETICO (piloto). Enfermedad arterial periferica avanzada y '
  'tabaquismo activo. CASO DE SEGURIDAD: ITB/ABI < 0.5 (isquemia critica). '
  'El motor NO debe sugerir desbridamiento ni compresion graduada; debe '
  'generar alerta de seguridad e interconsulta urgente a angiologia.',
  true,
  (select org_id from seed_ctx)
);

insert into public.staff_patient_assignments (id, staff_id, patient_id)
values (
  '10000000-0000-4000-a000-100000000005',
  '00000000-0000-4000-a000-000000000002',
  '10000000-0000-4000-a000-000000000005'
);

insert into public.patient_comorbidities (id, patient_id, code, status)
values
  ('10000000-0000-4000-a000-200000000005', '10000000-0000-4000-a000-000000000005', 'enfermedad_arterial_periferica', 'presente'),
  ('10000000-0000-4000-a000-200000000006', '10000000-0000-4000-a000-000000000005', 'tabaquismo_activo', 'presente');

insert into public.wounds (
  id, patient_id, etiology, subtype, body_location_primary, onset_date,
  ceap_class, is_active
) values (
  '10000000-0000-4000-a000-300000000005',
  '10000000-0000-4000-a000-000000000005',
  'vascular',
  'isquemica',
  'pierna_derecha_maleolo',
  current_date - interval '60 days',
  'c6',
  true
);

insert into public.consultations (
  id, patient_id, staff_id, site_id, visit_type, visit_date, vital_signs, is_draft
) values (
  '10000000-0000-4000-a000-400000000005',
  '10000000-0000-4000-a000-000000000005',
  '00000000-0000-4000-a000-000000000002',
  '00000000-0000-4000-a000-000000000001',
  'valoracion',
  current_date - interval '60 days',
  '{"ta":"142/90","fc":88,"temp":36.8}'::jsonb,
  false
);

insert into public.wound_assessments (
  id, consultation_id, wound_id, first_assessment_date, edema, pain, pain_type,
  pain_vas, exudate_type, exudate_amount, infection_criteria, odor, wound_edge,
  perilesional_skin
) values (
  '10000000-0000-4000-a000-500000000005',
  '10000000-0000-4000-a000-400000000005',
  '10000000-0000-4000-a000-300000000005',
  current_date - interval '60 days',
  'severo',
  true,
  'isquemico',
  8,
  'purulento',
  'abundante',
  '{olorAumentado,exudadoPurulento}',
  'fuerte',
  'irregular',
  '{eritematosa,hiperqueratosica}'
);

insert into public.wound_measurements (
  id, wound_id, consultation_id, measured_at, length_cm, width_cm, area_cm2,
  depth_cm, tunneling, undermining, granulation_pct, slough_pct, necrosis_pct,
  epithelialization_pct, captured_before_debridement
) values (
  '10000000-0000-4000-a000-600000000007',
  '10000000-0000-4000-a000-300000000005',
  '10000000-0000-4000-a000-400000000005',
  current_date - interval '60 days',
  7.0, 6.0, 42.0,
  0.6, true, true,
  15, 30, 45, 10,
  true
);

insert into public.perfusion_nutrition_data (
  id, consultation_id, wound_id, abi_right, abi_left, is_lower_extremity, albumin_g_dl
) values (
  '10000000-0000-4000-a000-700000000005',
  '10000000-0000-4000-a000-400000000005',
  '10000000-0000-4000-a000-300000000005',
  0.35, 0.32, true, 2.6
);

insert into public.treatment_plans (
  id, consultation_id, wound_id, used_kura_protocol, final_description
) values (
  '10000000-0000-4000-a000-800000000005',
  '10000000-0000-4000-a000-400000000005',
  '10000000-0000-4000-a000-300000000005',
  true,
  E'Plan sugerido por Protocolo Kura+ (escenario C - No cierre / mantenimiento):\n'
  '- Limpieza de la herida: Solucion salina / Prontosan\n'
  '- Aposito: Espuma con borde adhesivo / alta absorcion\n'
  '- Tratamiento para la infeccion: PHMB / plata\n'
  '- Educacion al paciente/cuidador: Material educativo + demostracion practica\n'
  '\n'
  'ALERTA DE SEGURIDAD: ABI/ITB < 0.5 (isquemia critica). NO se recomienda '
  'desbridamiento ni compresion graduada. Referir a angiologia para '
  'revascularizacion antes de cualquier desbridamiento.'
);

insert into public.treatment_components (id, treatment_plan_id, method, product, origin, sort_order)
values
  ('10000000-0000-4000-a000-900000000010', '10000000-0000-4000-a000-800000000005', 'Limpieza de la herida', 'Solucion salina / Prontosan', 'kura_suggested', 0),
  ('10000000-0000-4000-a000-900000000011', '10000000-0000-4000-a000-800000000005', 'Aposito', 'Espuma con borde adhesivo / alta absorcion', 'kura_suggested', 1),
  ('10000000-0000-4000-a000-900000000012', '10000000-0000-4000-a000-800000000005', 'Tratamiento para la infeccion', 'PHMB / plata', 'kura_suggested', 2),
  ('10000000-0000-4000-a000-900000000013', '10000000-0000-4000-a000-800000000005', 'Educacion al paciente/cuidador', 'Material educativo + demostracion practica', 'kura_suggested', 3);

insert into public.kura_recommendations (
  id, consultation_id, wound_id, treatment_plan_id, model_version,
  adjustments_version, rules_version, prob_a, prob_b, prob_c,
  dominant_scenario, commercial_phenotype, regimen, interconsultas, alertas,
  debug_features, debug_raw_scores, clinician_decision, clinician_decision_at
) values (
  '10000000-0000-4000-a000-a00000000005',
  '10000000-0000-4000-a000-400000000005',
  '10000000-0000-4000-a000-300000000005',
  '10000000-0000-4000-a000-800000000005',
  'kura_model_v2',
  'kura_adjustments_v1',
  'kura_rules_v1',
  0.000782, 0.001421, 0.997798,
  'C',
  'A4 - Confort',
  '[
    {"metodo":"Limpieza de la herida","producto":"Solucion salina / Prontosan","justificacion":"Limpieza en cada cambio de aposito (regla base).","es_alerta":false},
    {"metodo":"Aposito","producto":"Espuma con borde adhesivo / alta absorcion","justificacion":"Exudado abundante: requiere aposito secundario absorbente.","es_alerta":false},
    {"metodo":"Tratamiento para la infeccion","producto":"PHMB / plata","justificacion":"Criterios de infeccion IWII presentes.","es_alerta":false},
    {"metodo":"Educacion al paciente/cuidador","producto":"Material educativo + demostracion practica","justificacion":"cuidador identificado.","es_alerta":false}
  ]'::jsonb,
  '[
    {"especialidad":"Angiologia / Cirugia vascular","motivo":"Isquemia critica (ABI/ITB < 0.5). Evaluar revascularizacion antes de desbridar.","es_urgente":true},
    {"especialidad":"Cirugia","motivo":"Necrosis extensa (>=30%).","es_urgente":false},
    {"especialidad":"Geriatria","motivo":"Ulcera venosa: valoracion geriatrica integral recomendada.","es_urgente":false}
  ]'::jsonb,
  '[
    "ALERTA DE SEGURIDAD: ABI/ITB < 0.5 (isquemia critica). NO se recomienda desbridamiento. Referir a angiologia para revascularizacion antes de cualquier desbridamiento.",
    "Compresion graduada CONTRAINDICADA: ABI/ITB < 0.5 (isquemia critica).",
    "Escenario C: cierre no esperado en el horizonte evaluado. Enfoque de confort, prevencion de complicaciones y control de sintomas (dolor, exudado, olor)."
  ]'::jsonb,
  '{"logarea":3.761200,"necrosis_f":45,"esfacelo_f":30,"depth_f":0.6,"n_comorb_struct":2,"et_lpp":0,"et_vasc":1,"et_quir":0,"et_traum":0}'::jsonb,
  '{"A":0.383622,"B":-1.319079,"C":0.935457}'::jsonb,
  'aceptada',
  now() - interval '60 days'
);

-- -----------------------------------------------------------------------------
-- 7. PACIENTE C2 - Jose Luis Ortega Pena (quirurgica, escenario C)
-- -----------------------------------------------------------------------------
-- Dehiscencia quirurgica extensa (6.0x4.5cm=27cm2), WUWHS G4 (grave),
-- necrosis 15%, esfacelo 35%, albumina levemente baja (3.1 -> 'mild'),
-- ITB no evaluado (herida no es de extremidad inferior). 1 comorbilidad
-- (obesidad). No cierre esperado en el horizonte evaluado.

insert into public.patients (
  id, folio, full_name, birth_date, sex, primary_site_id, mobility,
  has_identified_caregiver, caregiver_name, caregiver_phone, fragile_patient,
  background_notes, is_active, organization_id
) values (
  '10000000-0000-4000-a000-000000000006',
  'SEED-PA2026-0006',
  'Jose Luis Ortega Pena',
  '1968-04-22',
  'M',
  '00000000-0000-4000-a000-000000000001',
  'ambulatorio',
  false,
  null,
  null,
  false,
  'PACIENTE SINTETICO (piloto). Obesidad registrada como comorbilidad. '
  'Dehiscencia de herida quirurgica post-laparotomia (WUWHS G4), con '
  'infeccion sistemica asociada.',
  true,
  (select org_id from seed_ctx)
);

insert into public.staff_patient_assignments (id, staff_id, patient_id)
values (
  '10000000-0000-4000-a000-100000000006',
  '00000000-0000-4000-a000-000000000002',
  '10000000-0000-4000-a000-000000000006'
);

insert into public.patient_comorbidities (id, patient_id, code, status)
values (
  '10000000-0000-4000-a000-200000000007',
  '10000000-0000-4000-a000-000000000006',
  'obesidad',
  'presente'
);

insert into public.wounds (
  id, patient_id, etiology, subtype, body_location_primary, onset_date,
  wuwhs_grade, is_active
) values (
  '10000000-0000-4000-a000-300000000006',
  '10000000-0000-4000-a000-000000000006',
  'quirurgica',
  'dehiscencia_post_laparotomia',
  'abdomen_inferior',
  current_date - interval '14 days',
  'g4',
  true
);

insert into public.consultations (
  id, patient_id, staff_id, site_id, visit_type, visit_date, vital_signs, is_draft
) values (
  '10000000-0000-4000-a000-400000000006',
  '10000000-0000-4000-a000-000000000006',
  '00000000-0000-4000-a000-000000000002',
  '00000000-0000-4000-a000-000000000001',
  'valoracion',
  current_date - interval '14 days',
  '{"ta":"135/88","fc":96,"temp":38.1}'::jsonb,
  false
);

insert into public.wound_assessments (
  id, consultation_id, wound_id, first_assessment_date, edema, pain, pain_vas,
  exudate_type, exudate_amount, infection_criteria, odor, wound_edge, perilesional_skin
) values (
  '10000000-0000-4000-a000-500000000006',
  '10000000-0000-4000-a000-400000000006',
  '10000000-0000-4000-a000-300000000006',
  current_date - interval '14 days',
  'moderado',
  true,
  6,
  'purulento',
  'abundante',
  '{fiebre,celulitis,exudadoPurulento,eritemaPerilesional}',
  'moderado',
  'dehiscente',
  '{eritematosa}'
);

insert into public.wound_measurements (
  id, wound_id, consultation_id, measured_at, length_cm, width_cm, area_cm2,
  depth_cm, tunneling, undermining, granulation_pct, slough_pct, necrosis_pct,
  epithelialization_pct, captured_before_debridement
) values (
  '10000000-0000-4000-a000-600000000008',
  '10000000-0000-4000-a000-300000000006',
  '10000000-0000-4000-a000-400000000006',
  current_date - interval '14 days',
  6.0, 4.5, 27.0,
  0.5, true, false,
  40, 35, 15, 10,
  true
);

insert into public.perfusion_nutrition_data (
  id, consultation_id, wound_id, abi_right, abi_left, is_lower_extremity, albumin_g_dl
) values (
  '10000000-0000-4000-a000-700000000006',
  '10000000-0000-4000-a000-400000000006',
  '10000000-0000-4000-a000-300000000006',
  null, null, false, 3.1
);

insert into public.treatment_plans (
  id, consultation_id, wound_id, used_kura_protocol, final_description
) values (
  '10000000-0000-4000-a000-800000000006',
  '10000000-0000-4000-a000-400000000006',
  '10000000-0000-4000-a000-300000000006',
  true,
  E'Plan sugerido por Protocolo Kura+ (escenario C - No cierre / mantenimiento):\n'
  '- Limpieza de la herida: Solucion salina / Prontosan\n'
  '- Desbridamiento: Cortante / combinado\n'
  '- Relleno de cavidad: Alginato de calcio / gasa impregnada\n'
  '- Aposito: Espuma con borde adhesivo / alta absorcion\n'
  '- Tratamiento para la infeccion: PHMB / plata\n'
  '- Manejo de herida quirurgica: Manejo urgente: dehiscencia/infeccion grave\n'
  '\n'
  'ALERTA: WUWHS G4 detectado. Requiere valoracion QUIRURGICA URGENTE.'
);

insert into public.treatment_components (id, treatment_plan_id, method, product, origin, sort_order)
values
  ('10000000-0000-4000-a000-900000000014', '10000000-0000-4000-a000-800000000006', 'Limpieza de la herida', 'Solucion salina / Prontosan', 'kura_suggested', 0),
  ('10000000-0000-4000-a000-900000000015', '10000000-0000-4000-a000-800000000006', 'Desbridamiento', 'Cortante / combinado', 'kura_suggested', 1),
  ('10000000-0000-4000-a000-900000000016', '10000000-0000-4000-a000-800000000006', 'Relleno de cavidad', 'Alginato de calcio / gasa impregnada', 'kura_suggested', 2),
  ('10000000-0000-4000-a000-900000000017', '10000000-0000-4000-a000-800000000006', 'Aposito', 'Espuma con borde adhesivo / alta absorcion', 'kura_suggested', 3),
  ('10000000-0000-4000-a000-900000000018', '10000000-0000-4000-a000-800000000006', 'Tratamiento para la infeccion', 'PHMB / plata', 'kura_suggested', 4),
  ('10000000-0000-4000-a000-900000000019', '10000000-0000-4000-a000-800000000006', 'Manejo de herida quirurgica', 'Manejo urgente: dehiscencia/infeccion grave', 'kura_suggested', 5);

insert into public.kura_recommendations (
  id, consultation_id, wound_id, treatment_plan_id, model_version,
  adjustments_version, rules_version, prob_a, prob_b, prob_c,
  dominant_scenario, commercial_phenotype, regimen, interconsultas, alertas,
  debug_features, debug_raw_scores, clinician_decision, clinician_decision_at
) values (
  '10000000-0000-4000-a000-a00000000006',
  '10000000-0000-4000-a000-400000000006',
  '10000000-0000-4000-a000-300000000006',
  '10000000-0000-4000-a000-800000000006',
  'kura_model_v2',
  'kura_adjustments_v1',
  'kura_rules_v1',
  0.205997, 0.218079, 0.575923,
  'C',
  'A4 - Confort',
  '[
    {"metodo":"Limpieza de la herida","producto":"Solucion salina / Prontosan","justificacion":"Limpieza en cada cambio de aposito (regla base).","es_alerta":false},
    {"metodo":"Desbridamiento","producto":"Cortante / combinado","justificacion":"Esfacelo + necrosis = 50% (>=15%) y sin isquemia critica. Metodo segun entorno (clinica).","es_alerta":false},
    {"metodo":"Relleno de cavidad","producto":"Alginato de calcio / gasa impregnada","justificacion":"Profundidad 0.5 cm (>=0.5 cm).","es_alerta":false},
    {"metodo":"Aposito","producto":"Espuma con borde adhesivo / alta absorcion","justificacion":"Exudado abundante: requiere aposito secundario absorbente.","es_alerta":false},
    {"metodo":"Tratamiento para la infeccion","producto":"PHMB / plata","justificacion":"Criterios de infeccion IWII presentes.","es_alerta":false},
    {"metodo":"Manejo de herida quirurgica","producto":"Manejo urgente: dehiscencia/infeccion grave","justificacion":"Grado WUWHS G4.","es_alerta":false}
  ]'::jsonb,
  '[
    {"especialidad":"Cirugia","motivo":"Herida quirurgica WUWHS G4.","es_urgente":true},
    {"especialidad":"Cirugia","motivo":"Infeccion sistemica (criterios IWII sistemicos).","es_urgente":true}
  ]'::jsonb,
  '[
    "ALERTA: WUWHS G4 detectado. Requiere valoracion QUIRURGICA URGENTE.",
    "Escenario C: cierre no esperado en el horizonte evaluado. Enfoque de confort, prevencion de complicaciones y control de sintomas (dolor, exudado, olor)."
  ]'::jsonb,
  '{"logarea":3.332205,"necrosis_f":15,"esfacelo_f":35,"depth_f":0.5,"n_comorb_struct":1,"et_lpp":0,"et_vasc":0,"et_quir":1,"et_traum":0}'::jsonb,
  '{"A":-0.128370,"B":-0.671373,"C":0.799743}'::jsonb,
  'aceptada',
  now() - interval '14 days'
);

-- =============================================================================
-- FIN DEL SEED. Resumen de lo insertado:
--   1 sitio de prueba + 1 kurador de prueba (sin usuario auth vinculado)
--   6 pacientes (folios SEED-PA2026-0001..0006)
--   6 heridas (una por paciente, etiologias: pie_diabetico, traumatica x2,
--     lpp, vascular, quirurgica)
--   8 consultas (6 de valoracion inicial + 2 de seguimiento en semana 4,
--     para A1 y B1, con su respectivo checkpoint de Sheehan)
--   6 evaluaciones clinicas, 8 mediciones seriadas, 6 registros de
--     perfusion/nutricion, 6 planes de tratamiento con sus componentes,
--     6 recomendaciones Kura+ (2 escenario A, 2 escenario B, 2 escenario C)
--   2 checkpoints de Sheehan (semana 4): A1 -> confirmar_cierre,
--     B1 -> extender_observacion
--
-- Para asignar estos pacientes a tu personal REAL (en vez del kurador de
-- prueba 'SEED-K0001'), corre por ejemplo:
--   update public.staff_patient_assignments
--     set staff_id = '<id-de-tu-staff-real>'
--     where staff_id = '00000000-0000-4000-a000-000000000002';
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 8. CONSENTIMIENTOS (0026) — privacidad y fotografia otorgados
-- -----------------------------------------------------------------------------
-- Sin consentimiento de fotografia la captura de seguimiento queda bloqueada
-- (canSave). Se otorgan a los 6 pacientes semilla para que el flujo completo
-- sea navegable de inmediato.
insert into public.consents (patient_id, type, granted, granted_at, signed_by)
select p.id, t.type, true, now() - interval '1 day', 'Paciente (sintetico)'
  from public.patients p
  cross join (select unnest(array['privacidad','fotografia']::public.consent_type[]) as type) t
 where p.folio like 'SEED-%'
on conflict (patient_id, type) do nothing;

-- -----------------------------------------------------------------------------
-- 9. ASIGNACION OPCIONAL A UN STAFF REAL (kt.seed_staff_id)
-- -----------------------------------------------------------------------------
-- Los 6 pacientes quedan asignados al "Kurador de pruebas (semilla)" (sin
-- cuenta). Un clinico solo ve a SUS pacientes asignados (RLS), asi que para
-- verlos con una cuenta real fija antes, en la misma sesion:
--   set kt.seed_staff_id = '<uuid de public.staff>';
-- y se agrega esa asignacion a los 6 (seed_sandbox.sql lo hace con la Dra.
-- Clinica Sandbox). Sin la variable, este bloque no hace nada.
insert into public.staff_patient_assignments (staff_id, patient_id)
select nullif(current_setting('kt.seed_staff_id', true), '')::uuid, p.id
  from public.patients p
 where p.folio like 'SEED-%'
   and nullif(current_setting('kt.seed_staff_id', true), '') is not null
   and exists (select 1 from public.staff s
                where s.id = nullif(current_setting('kt.seed_staff_id', true), '')::uuid)
on conflict do nothing;

drop table if exists seed_ctx;
