// Lógica del recorrido guiado (demo): avance/retroceso/fin y armado de pasos
// por rol (los flujos clínicos incluyen valoración + seguimiento cuando hay
// una herida demo).
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/features/tour/tour_controller.dart';
import 'package:kuratracker/features/tour/tour_steps.dart';
import 'package:kuratracker/models/app_user.dart';

void main() {
  group('TourController', () {
    const steps = [
      TourStep(route: '/', title: 'a', body: 'a'),
      TourStep(route: '/patients', title: 'b', body: 'b'),
      TourStep(title: 'c', body: 'c'),
    ];

    test('start arranca en el paso 0 y running', () {
      final c = TourController();
      c.start(steps);
      expect(c.state.running, isTrue);
      expect(c.state.index, 0);
      expect(c.state.current?.route, '/');
      expect(c.state.total, 3);
    });

    test('start con lista vacía no arranca', () {
      final c = TourController();
      c.start(const []);
      expect(c.state.running, isFalse);
    });

    test('next avanza y al final termina; prev no baja de 0', () {
      final c = TourController()..start(steps);
      c.prev();
      expect(c.state.index, 0); // no baja de 0
      c.next();
      expect(c.state.index, 1);
      c.prev();
      expect(c.state.index, 0);
      c.next();
      c.next(); // en el último
      expect(c.state.isLast, isTrue);
      c.next(); // termina
      expect(c.state.running, isFalse);
    });
  });

  group('tourStepsFor', () {
    test('clínico CON herida incluye valoración y seguimiento', () {
      final steps =
          tourStepsFor(AppRole.clinico, patientId: 'p1', woundId: 'w1');
      final routes = steps.map((s) => s.route).toList();
      expect(routes, contains('/patients/p1/wound/w1/capture'));
      expect(routes, contains('/patients/p1/wound/w1/follow-up/new'));
      expect(routes.first, '/');
    });

    test('clínico SIN herida omite los pasos de herida', () {
      final steps = tourStepsFor(AppRole.clinico);
      final routes = steps.map((s) => s.route).join(' ');
      expect(routes.contains('/capture'), isFalse);
      expect(routes.contains('/follow-up'), isFalse);
    });

    test('master recorre solo la Plataforma', () {
      final steps = tourStepsFor(AppRole.master);
      expect(steps.first.route, '/platform');
      expect(steps.every((s) => s.route != '/patients'), isTrue);
    });

    test('cada rol produce al menos un paso', () {
      for (final r in AppRole.values) {
        expect(tourStepsFor(r), isNotEmpty, reason: 'rol $r');
      }
    });
  });
}
