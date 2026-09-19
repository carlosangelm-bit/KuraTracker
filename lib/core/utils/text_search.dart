/// Normalización de texto para BÚSQUEDA en español: minúsculas y SIN acentos, para que
/// "apos" encuentre "Apósito" (en español, ignorar acentos no es un lujo). Misma tabla que
/// `ekare_import_screen` usa para empatar nombres; aquí queda como la utilidad canónica para
/// que los buscadores no reinventen (ni olviden) el plegado de acentos.
String foldAccents(String s) {
  s = s.toLowerCase();
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñ';
  const to = 'aaaaaeeeeiiiiooooouuuun';
  final b = StringBuffer();
  for (final ch in s.runes) {
    final c = String.fromCharCode(ch);
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  return b.toString();
}

/// ¿[haystack] contiene [needle] ignorando mayúsculas y acentos? Vacío = coincide (sin filtro).
bool matchesSearch(String haystack, String needle) {
  final q = foldAccents(needle.trim());
  return q.isEmpty || foldAccents(haystack).contains(q);
}
