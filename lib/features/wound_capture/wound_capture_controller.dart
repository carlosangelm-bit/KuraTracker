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

  /// CAUSA RAIZ del bug "los widgets tap-based no responden" (ChoiceChip de
  /// Tipo de herida, SwitchListTile de Dolor/extremidad inferior, etc.):
  /// state_notifier decide si notificar a los listeners comparando la
  /// referencia del estado anterior vs la nueva via `identical(old, current)`
  /// (ver updateShouldNotify en el paquete state_notifier). Como
  /// [WoundCaptureFormState] es deliberadamente mutable y `touch()` hace
  /// `state = state` (misma referencia de objeto), `identical(old, current)`
  /// siempre es true y la notificacion NUNCA se dispara -> ref.watch() en
  /// WoundCaptureScreen jamas reconstruye el widget, aunque el campo mutable
  /// (formState.etiologia, formState.pain, etc.) SI cambio correctamente en
  /// memoria. Por eso el tap "no responde" visualmente (ChoiceChip/Switch no
  /// repintan su estado seleccionado) pero los TextFormField "si funcionan":
  /// estos ya muestran su propio valor localmente vía TextEditingController
  /// interno, sin depender de un rebuild del padre para reflejar el tecleo.
  /// No es hit-testing/pointer-offset (los taps SI llegan al onSelected/
  /// onChanged correcto, confirmado con Playwright inspeccionando el modelo
  /// tras el tap); es una notificacion de estado que nunca se propaga.
  @override
  bool updateShouldNotify(
    WoundCaptureFormState old,
    WoundCaptureFormState current,
  ) =>
      true;

  void touch() {
    // Fuerza rebuild de listeners (el estado interno es mutable por
    // simplicidad; en una refactorizacion futura se recomienda
    // inmutabilidad total con copyWith). El override de updateShouldNotify
    // arriba es lo que realmente garantiza que esta reasignacion notifique,
    // pese a ser la misma referencia de objeto.
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
