import 'package:flutter/material.dart';

import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../models/app_user.dart';

/// La COMPRA de insumos (tienda, inventario, reabasto, mapeo) es del ADMIN del
/// centro y del master. Enfermería y clínico NO compran. Registrar el CONSUMO
/// clínico de un insumo (/insumos/consumo) sí es parte del trabajo clínico y no
/// se restringe aquí. (Brief 30-ago-2026: "solo el admin del centro compra".)
bool canPurchaseSupplies(AppUser? user) =>
    user?.role == AppRole.admin || (user?.isMaster ?? false);

/// Guarda EN PANTALLA para las rutas de compra (además del bloqueo del router):
/// en una app web con rutas por URL, el candado del router no basta.
Widget purchaseDeniedScaffold(String title) => Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: const [UserMenuButton()],
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'La compra de insumos es del administrador del centro.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
