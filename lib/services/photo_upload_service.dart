import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';

/// Sube y resuelve evidencia fotografica de heridas.
///
/// BACKEND SUPABASE (produccion): sube los bytes al bucket privado
/// `wound-evidence` respetando la convencion de ruta obligatoria para que
/// las policies RLS de storage.objects autoricen la operacion (ver
/// supabase/migrations/0004_storage_buckets.sql):
///   {wound_id}/{consultation_id}/{filename}
/// El bucket es privado, asi que para MOSTRAR una foto se necesita una
/// signed URL de corta duracion (`createSignedUrl`), nunca una URL publica.
///
/// MODO DEMO LOCAL (sin credenciales de Supabase): no existe un bucket de
/// storage real. Para que el flujo de seguimiento sea probable end-to-end
/// tambien en demo, la imagen se codifica como data URL (base64) y esa
/// misma cadena se persiste directamente en `wound_photos.storage_path` —
/// es autocontenida y se puede mostrar con Image.network sin backend.
class PhotoUploadService {
  PhotoUploadService._();

  static const String _bucket = 'wound-evidence';

  /// Sube una foto de seguimiento y retorna el valor a persistir en
  /// `wound_photos.storage_path`.
  static Future<String> uploadWoundPhoto({
    required String woundId,
    required String consultationId,
    required Uint8List bytes,
    required String fileName,
    String contentType = 'image/jpeg',
  }) async {
    if (!AppConfig.isSupabaseConfigured) {
      final b64 = base64Encode(bytes);
      return 'data:$contentType;base64,$b64';
    }

    // Convencion de ruta obligatoria para las policies de
    // wound_evidence_insert/select/delete: el primer segmento debe ser el
    // wound_id (storage.foldername(name))[1]).
    final safeFileName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        '$woundId/$consultationId/${DateTime.now().millisecondsSinceEpoch}_$safeFileName';

    await Supabase.instance.client.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );

    return path;
  }

  /// Resuelve una URL mostrable (Image.network) para un `storage_path`
  /// guardado en `wound_photos`. Si ya es una URL/data URL autocontenida
  /// (modo demo local), se retorna tal cual. Si es una ruta real de
  /// Supabase Storage (bucket privado), genera una signed URL de 1 hora.
  static Future<String> resolveDisplayUrl(String storagePath) async {
    if (storagePath.startsWith('data:') ||
        storagePath.startsWith('http://') ||
        storagePath.startsWith('https://')) {
      return storagePath;
    }
    return Supabase.instance.client.storage
        .from(_bucket)
        .createSignedUrl(storagePath, 3600);
  }
}
