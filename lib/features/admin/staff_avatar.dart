import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/name_format.dart';
import '../../models/staff.dart';

/// Avatar de un integrante: SIEMPRE las iniciales del nombre ([avatarInitial]). Nunca
/// del folio: `s.folio.substring(1, 3)` daba los mismos dos dígitos del año a todo el
/// personal (K2026-0001 → "20") y, sobre un folio corto/vacío, lanzaba un RangeError
/// que tumbó la pantalla del master. El folio ya sale en el subtítulo.
///
/// Vive en su propio archivo (sin arrastrar el resto de la pantalla) para poder probar
/// su conducta en local, sin google_fonts.
class StaffAvatar extends StatelessWidget {
  final StaffMember member;
  const StaffAvatar({super.key, required this.member});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return CircleAvatar(
      backgroundColor: t.chipBg,
      child: Text(
        avatarInitial(member.fullName),
        style: TextStyle(color: t.brandPrimary, fontWeight: FontWeight.w700),
      ),
    );
  }
}
