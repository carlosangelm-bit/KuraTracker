-- 0027_followup_signature.sql
--
-- FIRMA DIGITAL del profesional en las notas de seguimiento (Protocolo
-- "Expedientes clínicos"). Complementa la firma de solo lectura ya existente
-- (follow_up_signed_by + follow_up_signed_license/cédula, ver 0008): se añade
-- la firma digital trazada por el profesional y su marca de tiempo.
--
-- La firma se guarda como vector (JSON de trazos de puntos normalizados) en
-- follow_up_signature, generado por el pad de firma de la app (sin dependencia
-- de imágenes/binarios). follow_up_signed_at registra cuándo se firmó.

alter table public.consultations
  add column if not exists follow_up_signature text;
alter table public.consultations
  add column if not exists follow_up_signed_at timestamptz;

comment on column public.consultations.follow_up_signature is
  'Firma digital del profesional (JSON de trazos del pad de firma) en la nota '
  'de seguimiento. NULL = sin firmar. Acompaña a follow_up_signed_by/'
  'follow_up_signed_license (nombre + cédula).';
comment on column public.consultations.follow_up_signed_at is
  'Fecha/hora en que el profesional firmó digitalmente la nota de seguimiento.';
