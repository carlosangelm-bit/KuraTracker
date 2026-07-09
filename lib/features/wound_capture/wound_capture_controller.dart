import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/kura_protocol_engine.dart';
import '../../engine/models/kura_engine_output.dart';
import 'wound_capture_form_state.dart';

/// Controlador de estado del flujo de captura, indexado por una clave de
/// borrador (normalmente el consultationId). Mantiene el estado del
/// formulario y la ultima recomendacion del motor calculada en vivo, para
/// que tanto la pantalla de captura como la de tratamiento compartan el
/// mismo estado sin tener que serializarlo en la URL.
class WoundCaptureController extends StateNotifier<WoundCaptureFormState> {
  WoundCaptureController() : super(WoundCaptureFormState());

  KuraEngineOutput? liveOutput;
  bool engineLoading = false;

  void touch() {
    // Fuerza rebuild de listeners (el estado interno es mutable por
    // simplicidad; en una refactorizacion futura se recomienda
    // inmutabilidad total con copyWith).
    state = state;
  }

  Future<void> recomputePrognosis() async {
    if (!state.hasMinimumDataForPrognosis) {
      liveOutput = null;
      touch();
      return;
    }
    engineLoading = true;
    touch();
    try {
      final engine = await KuraProtocolEngine.load();
      liveOutput = engine.run(state.toEngineInput());
    } finally {
      engineLoading = false;
      touch();
    }
  }
}

final woundCaptureControllerProvider = StateNotifierProvider.family<
    WoundCaptureController, WoundCaptureFormState, String>(
  (ref, draftKey) => WoundCaptureController(),
);
