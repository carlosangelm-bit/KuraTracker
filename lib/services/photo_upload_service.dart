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
  static const String _intakeBucket = 'intake-photos';

  /// Sube una foto de admisión (agenda manual) al bucket privado
  /// `intake-photos` y devuelve el valor a persistir en
  /// `manual_appointments.photo_path`. La ruta empieza por `organization_id`
  /// para que la RLS de storage (0023) autorice a admin/clínico del centro.
  /// En modo demo local (sin Supabase) devuelve un data URL base64
  /// autocontenido, mostrable con Image.network sin backend.
  static Future<String> uploadIntakePhoto({
    required String organizationId,
    required Uint8List bytes,
    required String fileName,
    String contentType = 'image/jpeg',
  }) async {
    if (!AppConfig.isSupabaseConfigured) {
      return 'data:$contentType;base64,${base64Encode(bytes)}';
    }
    final safeFileName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$organizationId/${DateTime.now().millisecondsSinceEpoch}_$safeFileName';
    await Supabase.instance.client.storage.from(_intakeBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return path;
  }

  static const String _brandingBucket = 'org-branding';

  /// Sube el logo del centro al bucket org-branding y devuelve el valor a
  /// guardar en organizations.brand_logo_path (ruta o data URL en demo).
  static Future<String> uploadOrgLogo({
    required String organizationId,
    required Uint8List bytes,
    required String fileName,
    String contentType = 'image/png',
  }) async {
    if (!AppConfig.isSupabaseConfigured) {
      return 'data:$contentType;base64,${base64Encode(bytes)}';
    }
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$organizationId/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await Supabase.instance.client.storage.from(_brandingBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return path;
  }

  /// Resuelve una URL mostrable para el logo del centro (o data URL en demo).
  static Future<String> resolveOrgLogoUrl(String path) async {
    if (path.startsWith('data:') ||
        path.startsWith('http://') ||
        path.startsWith('https://')) {
      return path;
    }
    return Supabase.instance.client.storage
        .from(_brandingBucket)
        .createSignedUrl(path, 3600);
  }

  /// Resuelve una URL mostrable para un `photo_path` de intake-photos (o un
  /// data URL/URL ya autocontenida en demo).
  static Future<String> resolveIntakePhotoUrl(String path) async {
    if (path.startsWith('data:') ||
        path.startsWith('http://') ||
        path.startsWith('https://')) {
      return path;
    }
    return Supabase.instance.client.storage
        .from(_intakeBucket)
        .createSignedUrl(path, 3600);
  }

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

  /// Bytes ORIGINALES de una foto de herida, para exportarla a un archivo (no
  /// se reescala: es la evidencia clínica real). En demo el storage_path es un
  /// data URL base64 autocontenido; en prod es una ruta del bucket privado y se
  /// baja con `download(path)` (una petición por imagen, justo antes de
  /// escribirla — sin problema de expiración de signed URLs). Lanza si falla,
  /// para que el llamador la registre como faltante y continúe.
  static Future<Uint8List> downloadWoundPhotoBytes(String storagePath) async {
    if (storagePath.startsWith('data:')) {
      final comma = storagePath.indexOf(',');
      return base64Decode(storagePath.substring(comma + 1));
    }
    return Supabase.instance.client.storage
        .from(_bucket)
        .download(storagePath);
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
