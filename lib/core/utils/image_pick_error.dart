/// Mensaje accionable cuando falla la selección/carga de una foto.
///
/// Causa más común en la clínica: fotos tomadas con iPhone que quedan en
/// formato HEIC/HEIF, que el navegador (sobre todo en escritorio) no puede
/// decodificar al subirlas desde la app web. En vez de un fallo silencioso, se
/// le dice al usuario qué pasó y cómo resolverlo.
String imagePickErrorMessage(Object error) {
  return 'No se pudo cargar la imagen. Si la tomaste con un iPhone puede estar '
      'en formato HEIC: cámbiala a JPG (en el iPhone: Ajustes › Cámara › '
      'Formatos › "Más compatible") o elige/comparte la foto como JPG e '
      'inténtalo de nuevo.';
}

/// Devuelve un nombre de archivo con extensión .jpg (para fotos ya convertidas
/// a JPEG en la app, cuyo nombre original podría ser p. ej. IMG_1234.HEIC).
String jpgFileName(String? original, String fallback) {
  final base = (original == null || original.trim().isEmpty)
      ? fallback
      : original.trim();
  final dot = base.lastIndexOf('.');
  final stem = dot > 0 ? base.substring(0, dot) : base;
  return '$stem.jpg';
}
