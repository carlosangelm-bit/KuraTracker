import 'dart:io';

import 'package:kuratracker/engine/params/clinical_params.dart';

/// Carga los parámetros clínicos desde los archivos de assets usando dart:io
/// (los tests de Dart puro no tienen rootBundle). Registra la instancia global
/// para que el motor y KuraEngineInput los consulten. Llamar en `setUpAll`.
void loadClinicalParamsForTest() {
  ClinicalParams.register(ClinicalParams.fromJsonStrings(
    thresholdsJson:
        File('assets/engine/clinical/thresholds.json').readAsStringSync(),
    archetypesJson:
        File('assets/engine/clinical/archetypes.json').readAsStringSync(),
  ));
}
