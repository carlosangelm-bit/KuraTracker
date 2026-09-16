-- =============================================================================
-- 0141_seed_protocol_catalog_kura_35.sql — Matriz del protocolo · ETAPA 5 (parte 2/2: siembra)
-- =============================================================================
-- Siembra las 35 reglas del catálogo Kura+ (Excel v4 cruzado con el motor; FUERA quedan 9 de
-- tratamiento avanzado y 3 de presión negativa). Global (protocol_catalog_rules NO tiene
-- organization_id): la misma matriz en todos los entornos. id determinista + upsert → re-correr
-- la siembra ACTUALIZA la prosa, no duplica.
--
-- Todas nacen SIN identidad (shopify null): son huérfanas con nombre. La prosa (name/brand/alt)
-- es lo que ve el clínico; la identidad se les ata después (product_catalog, hoja 2 sin validar).
-- Sin condiciones de medida (dimension 'none', cantidad fija 1): la matriz resuelve por
-- CATEGORÍA + CONTEXTO. sort_order = orden de la matriz. La verificación de que la siembra corrió
-- (un consumidor resuelve y DEVUELVE filas) vive en el arnés SQL, no aquí.
-- =============================================================================

insert into public.protocol_catalog_rules
  (id, category, context_kind, context_value, scale_label, trigger_label,
   name, brand, alt_name, alt_brand, etapa_clinica, notas,
   dimension, quantity_mode, quantity_value, sort_order, exudate_levels, zone_groups, infection)
values
  ('d1000000-0000-0000-0000-000000000000', 'proteccion_piel', 'etiologia', 'lpp', 'Braden — prevención', 'Riesgo bajo–alto', 'Linovera® (ácidos grasos hiperoxigenados)', 'B. Braun', null, null, 'Prevención y tratamiento – LPP estadio I / hidratación de piel', 'Única opción documentada. Indicado en prevención y como tratamiento de LPP estadio I.', 'none', 'fixed', 1, 0, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000001', 'aposito', 'etiologia', 'lpp', 'Braden — prevención', 'Zonas de presión (sacro, talón)', 'Mepilex® Border Sacrum / Border Heel (talón)', 'Mölnlycke', 'Askina® Heel', 'B. Braun', 'Prevención – protección de zonas de riesgo', 'Opción 1 de 2 de la etapa (fila desdoblada).', 'none', 'fixed', 1, 1, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000002', 'aposito', 'etiologia', 'lpp', 'Braden — prevención', 'Zonas de presión (otras localizaciones)', 'Mepilex® Border Flex', 'Mölnlycke', 'Askina® Heel', 'B. Braun', 'Prevención – protección de zonas de riesgo', 'Opción 2 de 2 de la etapa (fila desdoblada).', 'none', 'fixed', 1, 2, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000003', 'aposito', 'etiologia', 'lpp', 'NPIAP/EPUAP I–II', 'Piel intacta / exudado nulo-bajo. Lesión superficial.', 'Mepilex® Border Flex', 'Mölnlycke', 'Mepilex Border Flex Lite', 'Mölnlycke', 'Categoría/Estadio I–II', 'Se descarta Tegaderm', 'none', 'fixed', 1, 3, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000004', 'aposito', 'etiologia', 'lpp', 'NPIAP/EPUAP III–IV', 'Exudado moderado-alto', 'Mepilex® Border Flex', 'Mölnlycke', 'Askina® Foam Cavity (cavidad)', 'B. Braun', 'Categoría III–IV – control de exudado e infección', 'Escalamiento avanzado: 3M™ V.A.C.® (NPWT) en heridas complejas/muy exudativas.', 'none', 'fixed', 1, 4, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000005', 'antimicrobiano', 'etiologia', 'lpp', 'NPIAP/EPUAP III–IV', 'Infección / biofilm', 'Exufiber® Ag+ (fibra gelificante)', 'Mölnlycke', 'Acticoat™ Flex (plata nanocristalina)', 'Smith & Nephew', 'Categoría III–IV con infección/biofilm', 'Opción 1 de 2 de la etapa (fila desdoblada).', 'none', 'fixed', 1, 5, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000006', 'antimicrobiano', 'etiologia', 'lpp', 'NPIAP/EPUAP III–IV', 'Infección / biofilm', 'Durafiber Ag (hidrofibra)', 'Smith & Nephew', 'Acticoat™ Flex (plata nanocristalina)', 'Smith & Nephew', 'Categoría III–IV con infección/biofilm', 'Opción 2 de 2 de la etapa (fila desdoblada).', 'none', 'fixed', 1, 6, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000007', 'desbridamiento', 'etiologia', 'lpp', 'RESVECH / PUSH', 'Esfacelo / necrosis', 'Prontosan® Wound Gel X', 'B. Braun', 'Iodosorb™', 'Smith & Nephew', 'Lechos con esfacelo/necrosis', 'Opción 1 de 2 de la etapa (fila desdoblada).', 'none', 'fixed', 1, 7, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000008', 'desbridamiento', 'etiologia', 'lpp', 'RESVECH / PUSH', 'Esfacelo / necrosis', 'Intrasite', 'Smith & Nephew', 'Iodosorb™', 'Smith & Nephew', 'Lechos con esfacelo/necrosis', 'Opción 2 de 2 de la etapa (fila desdoblada).', 'none', 'fixed', 1, 8, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000009', 'proteccion_piel', 'piel', 'dai', 'GLOBIAD 1A/1B', 'Piel íntegra enrojecida', '3M™ Cavilon™ Película Protectora Sin Ardor', 'Solventum (3M)', null, null, 'Eritema persistente (1A/1B)', '', 'none', 'fixed', 1, 9, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-00000000000a', 'proteccion_piel', 'piel', 'dai', 'GLOBIAD 2A/2B', 'Pérdida de integridad cutánea', '3M™ Cavilon™ Crema Barrera Duradera', 'Solventum (3M)', null, null, 'Pérdida de piel (2A/2B)', 'Evaluar estado de la herida para uso de apósitos.', 'none', 'fixed', 1, 10, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-00000000000b', 'aposito', 'piel', 'dai', 'GLOBIAD', 'Zonas de riesgo', '3M™ Cavilon™ Película Protectora Sin Ardor', 'Solventum (3M)', null, null, 'Manejo de exudado en zona perineal', 'Opción 1 de 2 de la etapa (fila desdoblada).', 'none', 'fixed', 1, 11, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-00000000000c', 'aposito', 'piel', 'dai', 'GLOBIAD', 'Zonas de riesgo', 'Proshield', 'Smith & Nephew', null, null, 'Manejo de exudado en zona perineal', 'Opción 2 de 2 de la etapa (fila desdoblada).', 'none', 'fixed', 1, 12, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-00000000000d', 'aposito', 'etiologia', 'desgarro', 'ISTAP/STAR — Tipo 1 / 1a-1b', 'Colgajo viable', 'Mepitel® One', 'Mölnlycke', null, null, 'Reposicionamiento del colgajo', '', 'none', 'fixed', 1, 13, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-00000000000e', 'aposito', 'etiologia', 'desgarro', 'ISTAP/STAR', 'Fijación secundaria', 'Mepilex Border Flex', 'Mölnlycke', null, null, 'Fijación sin tensión', 'Películas transparentes contraindicadas en esta etapa.', 'none', 'fixed', 1, 14, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-00000000000f', 'aposito', 'etiologia', 'desgarro', 'ISTAP — Tipo 3', 'Lecho expuesto', 'Exufiber®', 'Mölnlycke', null, null, 'Pérdida total del colgajo (Tipo 3)', 'Complemento (cobertura secundaria): Mepilex® Border Flex (Mölnlycke).
Opción 1 de 2 de la etapa (fila desdoblada).', 'none', 'fixed', 1, 15, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000010', 'aposito', 'etiologia', 'desgarro', 'ISTAP — Tipo 3', 'Lecho expuesto', 'Melgisorb', 'Mölnlycke', null, null, 'Pérdida total del colgajo (Tipo 3)', 'Complemento (cobertura secundaria): Mepilex® Border Flex (Mölnlycke).
Opción 2 de 2 de la etapa (fila desdoblada).', 'none', 'fixed', 1, 16, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000011', 'aposito', 'evolucion', 'seguimiento', 'PUSH / RESVECH', 'Exudado ligero-moderado', 'Mepilex Border Flex', 'Mölnlycke', 'Allevyn™ Adhesive', 'Smith & Nephew', 'Exudado ligero-moderado, granulación', 'Complemento: Askina® Foam (B. Braun).', 'none', 'fixed', 1, 17, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000012', 'aposito', 'evolucion', 'seguimiento', 'PUSH / RESVECH', 'Exudado abundante', 'Exufiber®', 'Mölnlycke', 'Durafiber Ag', 'Smith & Nephew', 'Exudado abundante', 'Con infección: usar Exufiber® Ag+.', 'none', 'fixed', 1, 18, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000013', 'antimicrobiano', 'evolucion', 'seguimiento', 'PUSH / RESVECH', 'Colonización · infección local o sistémica', 'Acticoat™ Flex 3', 'Smith & Nephew', 'Askina® Calgitrol® Ag', 'B. Braun', 'Colonización / infección local (sútil u oculta) con esfacelo', 'Valorar nivel de exudado', 'none', 'fixed', 1, 19, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000014', 'limpieza', 'evolucion', 'seguimiento', 'PUSH / RESVECH', 'Todos los cambios', 'Prontosan® Solución de lavado', 'B. Braun', 'Granudacyn® (irrigación)', 'Mölnlycke', 'Limpieza previa a cada cambio de apósito', '', 'none', 'fixed', 1, 20, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000015', 'aposito', 'piel', 'mdrpi', 'MDRPI — prevención', 'Bajo sondas/mascarillas/tubos', 'Mepilex® Lite', 'Mölnlycke', null, null, 'Protección profiláctica bajo dispositivos', 'Liberador de presión', 'none', 'fixed', 1, 21, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000016', 'proteccion_piel', 'piel', 'mdrpi', 'MDRPI — fijación', 'Catéteres/vías IV', '3M™ Tegaderm™ I.V. 1633', 'Solventum (3M)', 'Askina® Soft Clear I.V.', 'B. Braun', 'Fijación segura de catéteres/vías IV', '', 'none', 'fixed', 1, 22, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000017', 'proteccion_piel', 'piel', 'marsi', 'MARSI — retirada', 'Retiro de adhesivos', '3M™ Cavilon™ (protección cutánea)', 'Solventum (3M)', 'ADAPT. Removedor de adhesivo', 'Hollister', 'Retirada atraumática de adhesivos', 'Estos dos productos en conjunto previenen MARSI', 'none', 'fixed', 1, 23, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000018', 'proteccion_piel', 'piel', 'marsi', 'MARSI — prevención mecánica', 'Retiro de adhesivos', '3M™ Cavilon™ (protección cutánea)', 'Solventum (3M)', 'ADAPT. Removedor de adhesivo', 'Hollister', 'Prevención de MARSI mecánica (tensión/fricción)', 'Estos dos productos en conjunto previenen MARSI', 'none', 'fixed', 1, 24, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000019', 'antimicrobiano', 'etiologia', 'pie_diabetico', 'Wagner 2–3', 'Profunda / infectada', 'Exufiber® Ag+', 'Mölnlycke', 'Acticoat™ Flex', 'Smith & Nephew', 'Grado 2 – úlcera profunda infectada', 'Endoform y Myriad
Opción 1 de 2 de la etapa (fila desdoblada).', 'none', 'fixed', 1, 25, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-00000000001a', 'aposito', 'etiologia', 'pie_diabetico', 'Wagner 2–3', 'Profunda / infectada', 'Mepilex Border Flex', 'Mölnlycke', 'Acticoat™ Flex', 'Smith & Nephew', 'Grado 2 – úlcera profunda infectada', 'Endoform y Myriad
Opción 2 de 2 de la etapa (fila desdoblada).', 'none', 'fixed', 1, 26, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-00000000001b', 'compresion', 'etiologia', 'insuf_venosa', 'ITB 0.6–0.9', 'Insuficiencia venosa · ITB 0.6–0.9', '3M™ Coban™ 2 Lite', 'Solventum (3M)', null, null, 'Compresión terapéutica (ITB 0.6–0.9)', 'Graduación según resultado del ITB.', 'none', 'fixed', 1, 27, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-00000000001c', 'compresion', 'etiologia', 'insuf_venosa', 'ITB 0.9–1.3', 'Insuficiencia venosa · ITB 0.9–1.3', '3M™ Coban™ 2', 'Solventum (3M)', null, null, 'Úlcera venosa activa (ITB 0.9–1.3)', 'Graduación según resultado del ITB.', 'none', 'fixed', 1, 28, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-00000000001d', 'aposito', 'etiologia', 'quemaduras', '1er grado', 'Superficial', 'Mepitel® One', 'Mölnlycke', null, null, '1er grado / superficial', '', 'none', 'fixed', 1, 29, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-00000000001e', 'antimicrobiano', 'etiologia', 'quemaduras', '2do grado superficial', 'Espesor parcial', 'Mepilex AG®', 'Mölnlycke', 'Prontosan Gel', 'B. Braun', '2do grado superficial', 'Endoform', 'none', 'fixed', 1, 30, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-00000000001f', 'aposito', 'etiologia', 'quemaduras', 'Zona donante', 'Área donante/exudativa', 'Mepitel®', 'Mölnlycke', null, null, 'Zona donante de injerto / área exudativa', 'Endoform', 'none', 'fixed', 1, 31, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000020', 'antimicrobiano', 'etiologia', 'quemaduras', 'Con infección', 'Riesgo/infección', 'Acticoat™ Flex', 'Smith & Nephew', 'Exufiber® Ag+', 'Mölnlycke', 'Con riesgo/signos de infección', 'Complemento B. Braun: Askina® Calgitrol®.', 'none', 'fixed', 1, 32, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000021', 'limpieza', 'etiologia', 'quemaduras', 'Limpieza', 'Todas', 'Prontosan® Wound Gel X', 'B. Braun', null, null, 'Limpieza de quemaduras 1er–3er grado', 'Incluye 3er grado superficiales.', 'none', 'fixed', 1, 33, '[]', '[]', 'any'),
  ('d1000000-0000-0000-0000-000000000022', 'aposito', 'etiologia', 'quirurgica', 'ASEPSIS — post-op', 'Incisión cerrada', 'Mepilex® Border Post-Op', 'Mölnlycke', 'Mepilex Ag® Border Post-Op', 'Mölnlycke', 'Cobertura postoperatoria estándar', 'Aplica también Prevena.', 'none', 'fixed', 1, 34, '[]', '[]', 'any')
on conflict (id) do update set
  category = excluded.category, context_kind = excluded.context_kind,
  context_value = excluded.context_value, scale_label = excluded.scale_label,
  trigger_label = excluded.trigger_label, name = excluded.name, brand = excluded.brand,
  alt_name = excluded.alt_name, alt_brand = excluded.alt_brand,
  etapa_clinica = excluded.etapa_clinica, notas = excluded.notas, sort_order = excluded.sort_order,
  updated_at = now();
