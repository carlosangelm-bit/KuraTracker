-- 0038_wound_drain_suture_count.sql
--
-- Feedback clínico (María): en heridas quirúrgicas se registra, además del
-- TIPO de drenaje/sutura (0028), el NÚMERO de drenajes y el número de puntos/
-- grapas sobre la herida. Se agregan dos columnas opcionales a wounds.

alter table public.wounds
  add column if not exists drenaje_num int,   -- nº de drenajes
  add column if not exists sutura_num int;     -- nº de puntos / grapas

comment on column public.wounds.drenaje_num is
  'Número de drenajes presentes sobre la herida quirúrgica (María 2026-07).';
comment on column public.wounds.sutura_num is
  'Número de puntos/grapas presentes sobre la herida quirúrgica (María 2026-07).';
