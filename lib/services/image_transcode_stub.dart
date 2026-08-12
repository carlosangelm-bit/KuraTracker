import 'dart:typed_data';

/// Stub para plataformas nativas: no hay conversión en el navegador. El
/// llamador debe tratar `null` como "no se convirtió" y usar los bytes
/// originales (en nativo, image_picker ya entrega un formato utilizable).
Future<Uint8List?> transcodeImageToJpeg(
  Uint8List bytes, {
  String? name,
  int maxDim = 1600,
  double quality = 0.85,
}) async =>
    null;
