import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Un paso del recorrido guiado: a dónde navegar + qué explicar.
class TourStep {
  /// Ruta a la que la app navega al llegar a este paso. Null = quedarse donde
  /// está.
  final String? route;
  final String title;
  final String body;

  const TourStep({this.route, required this.title, required this.body});
}

/// Estado del recorrido guiado (solo demo).
class TourState {
  final bool running;
  final int index;
  final List<TourStep> steps;

  const TourState({
    this.running = false,
    this.index = 0,
    this.steps = const [],
  });

  TourStep? get current =>
      running && index >= 0 && index < steps.length ? steps[index] : null;
  int get total => steps.length;
  bool get isFirst => index == 0;
  bool get isLast => index >= steps.length - 1;

  TourState copyWith({bool? running, int? index, List<TourStep>? steps}) =>
      TourState(
        running: running ?? this.running,
        index: index ?? this.index,
        steps: steps ?? this.steps,
      );
}

class TourController extends StateNotifier<TourState> {
  TourController() : super(const TourState());

  void start(List<TourStep> steps) {
    if (steps.isEmpty) return;
    state = TourState(running: true, index: 0, steps: steps);
  }

  void next() {
    if (!state.running) return;
    if (state.isLast) {
      stop();
    } else {
      state = state.copyWith(index: state.index + 1);
    }
  }

  void prev() {
    if (!state.running || state.isFirst) return;
    state = state.copyWith(index: state.index - 1);
  }

  void stop() => state = const TourState();
}

final tourProvider =
    StateNotifierProvider<TourController, TourState>((ref) => TourController());
