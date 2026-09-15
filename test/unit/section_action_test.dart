// La guardia de montaje de publishSectionAction (§6/§10.8): la devolución post-frame
// hace `ref.read` SOLO si el widget sigue montado. Si la sección se destruye en el mismo
// cuadro (un redirect del router, /admin → /admin/usuarios), sin la guardia el `ref`
// desechado lanzaría «Cannot use ref after the widget was disposed» — pantalla roja.
// Local: section_action no arrastra google_fonts.
//
// Se prueba con un ConsumerState real que publica DENTRO de build() (como los llamantes
// reales: ahí el post-frame se agenda para el fin del cuadro en curso y sí corre), con una
// bandera [mounted] falseable: cuando dice `false`, la guardia corta ANTES del ref.read.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/nav/section_action.dart';

const _action = SectionAction(sectionKey: 'y', label: 'Y', icon: Icons.add);

class _Host extends ConsumerStatefulWidget {
  const _Host();
  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  bool _mountedFlag = false; // arranca "desmontado" para ejercer la guardia primero
  void setFlag(bool m) => setState(() => _mountedFlag = m);
  @override
  Widget build(BuildContext context) {
    // En build el framework está EN un cuadro: el post-frame corre al final de él.
    publishSectionAction(ref, _action, mounted: () => _mountedFlag);
    return const SizedBox();
  }
}

void main() {
  testWidgets('publishSectionAction: mounted=false corta antes del ref.read',
      (t) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: _Host()),
    ));

    // Primer build con la bandera en false: la guardia corta, el provider no se toca.
    expect(t.takeException(), isNull);
    expect(container.read(sectionActionProvider), isNull,
        reason: 'con mounted=false la guardia corta antes de publicar');

    // Rebuild con la bandera en true: ahora sí publica.
    t.state<_HostState>(find.byType(_Host)).setFlag(true);
    await t.pump();
    expect(container.read(sectionActionProvider)?.sectionKey, 'y');
  });
}
