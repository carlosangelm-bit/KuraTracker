/// Inicial para el avatar, SALTANDO títulos (Dr./Dra./Lic./Enf./Mtro./Ing.…):
/// "Dra. Ana Martínez" → "A", no "D". Toma la inicial de la primera palabra que
/// no sea un título; si no queda ninguna, "?".
///
/// Vive en core (no en el shell) para que TODOS los avatares —barra, drawer,
/// personal, pacientes— saquen la inicial igual, sin que un sitio quede con la
/// lógica vieja.
String avatarInitial(String fullName) {
  const titulos = {
    'dr', 'dra', 'lic', 'licda', 'enf', 'mtro', 'mtra', 'ing', 'sr', 'sra',
    'srta', 'prof', 'q', 'qfb', 'md',
  };
  for (final w in fullName.trim().split(RegExp(r'\s+'))) {
    final limpio = w.replaceAll('.', '').toLowerCase();
    if (limpio.isEmpty || titulos.contains(limpio)) continue;
    return w[0].toUpperCase();
  }
  return '?';
}
