import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';

import '../../engine/models/kura_engine_enums.dart';
import '../../models/consultation.dart' show VisitTypeLabel;
import '../../models/patient.dart';
import '../../models/wound.dart';
import '../data_repository.dart';
import '../photo_upload_service.dart';

/// Un archivo del árbol de exportación (ruta relativa + bytes).
class ExportedFile {
  final String path;
  final List<int> bytes;
  const ExportedFile(this.path, this.bytes);
}

/// Resultado de construir el árbol de UN paciente.
class PatientExportResult {
  final List<ExportedFile> files;
  final int photoCount; // fotos escritas ok
  final int photoMissing; // fotos que fallaron
  final List<String> missingPhotos; // rutas relativas de las que faltaron
  const PatientExportResult({
    required this.files,
    required this.photoCount,
    required this.photoMissing,
    required this.missingPhotos,
  });
}

/// Construye el "paquete de salida" como CARPETAS DE ARCHIVOS (reemplaza el
/// expediente en PDF): CSVs + fotos originales, organizados por
/// paciente/herida/fecha. Nunca sostiene el entregable completo en memoria más
/// allá de lo necesario; cada foto se baja justo antes de escribirla y una que
/// falle no aborta la entrega (se registra como faltante).
class RecordExportService {
  static const _bom = '﻿'; // Excel respeta acentos con BOM UTF-8.
  static const _csv = ListToCsvConverter();

  /// Sanea un componente de ruta: quita caracteres inválidos en sistemas de
  /// archivos y recorta la longitud. Un folio con un carácter raro no debe
  /// romper la exportación.
  static String sanitize(String s, {int maxLen = 80}) {
    var out = s.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
    if (out.isEmpty) out = '_';
    return out.length > maxLen ? out.substring(0, maxLen) : out;
  }

  static List<int> _csvBytes(List<List<dynamic>> rows) =>
      utf8.encode(_bom + _csv.convert(rows));

  static String _d(DateTime dt) => dt.toIso8601String().substring(0, 10);

  // ---- CSVs por paciente (mismas columnas que las exportaciones globales) ----

  static List<int> _patientDataCsv(DataRepository repo, Patient p) {
    final rows = <List<dynamic>>[
      ['campo', 'valor'],
      ['folio', p.folio],
      ['nombre', p.fullName],
      ['fecha_nacimiento', p.birthDate == null ? '' : _d(p.birthDate!)],
      ['edad', p.age ?? ''],
      ['sexo', p.sex ?? ''],
      ['curp', p.curp ?? ''],
      ['domicilio', p.address ?? ''],
      ['ocupacion', p.occupation ?? ''],
      ['responsable', p.responsibleName ?? ''],
      ['peso_kg', p.weightKg ?? ''],
      ['talla_cm', p.heightCm ?? ''],
    ];
    for (final d in repo.listDiagnoses(p.id)) {
      rows.add([
        'diagnostico',
        '${d.name}${d.isPrimary ? ' (principal)' : ''} [${d.code}]'
      ]);
    }
    for (final c in repo
        .listComorbidities(p.id)
        .where((c) => c.status == ComorbilidadEstado.presente)) {
      rows.add(['comorbilidad', c.code.label]);
    }
    return _csvBytes(rows);
  }

  static List<int> _patientMeasurementsCsv(DataRepository repo, Patient p) {
    final rows = <List<dynamic>>[
      [
        'herida_id', 'etiologia', 'fecha', 'largo_cm', 'ancho_cm', 'area_cm2',
        'profundidad_cm'
      ],
    ];
    for (final w in repo.listWoundsForPatient(p.id)) {
      for (final m in repo.listMeasurementsForWound(w.id)) {
        rows.add([
          w.id, w.etiology.name, _d(m.measuredAt), m.lengthCm, m.widthCm,
          m.areaCm2, m.depthCm
        ]);
      }
    }
    return _csvBytes(rows);
  }

  static List<int> _woundMeasurementsCsv(DataRepository repo, Wound w) {
    final rows = <List<dynamic>>[
      ['fecha', 'largo_cm', 'ancho_cm', 'area_cm2', 'profundidad_cm'],
    ];
    for (final m in repo.listMeasurementsForWound(w.id)) {
      rows.add(
          [_d(m.measuredAt), m.lengthCm, m.widthCm, m.areaCm2, m.depthCm]);
    }
    return _csvBytes(rows);
  }

  static List<int> _patientConsultationsCsv(DataRepository repo, Patient p) {
    final staffById = {for (final s in repo.listStaff()) s.id: s};
    final rows = <List<dynamic>>[
      [
        'fecha', 'tipo_visita', 'autor', 'cedula', 'especialidad', 'es_borrador',
        'tipo_cuidado', 'procedimiento', 'materiales_usados', 'evolucion',
        'resumen'
      ],
    ];
    final cs = repo.listConsultationsForPatient(p.id)
      ..sort((a, b) => a.visitDate.compareTo(b.visitDate));
    for (final c in cs) {
      final staff = staffById[c.staffId];
      final autor = (c.followUpSignedBy?.isNotEmpty ?? false)
          ? c.followUpSignedBy!
          : (staff?.fullName ?? '');
      rows.add([
        _d(c.visitDate),
        c.visitType.label,
        autor,
        c.followUpSignedLicense ?? staff?.cedulaProfesional ?? '',
        c.followUpSignedSpecialty ?? staff?.especialidad ?? '',
        c.isDraft ? 'sí' : 'no',
        c.followUpCareType ?? '',
        c.followUpProcedureDesc ?? '',
        c.followUpMaterialsUsed ?? '',
        c.followUpEvolution ?? '',
        c.visitSummary ?? '',
      ]);
    }
    return _csvBytes(rows);
  }

  /// Árbol de archivos de UN paciente bajo `<prefix><folio>/…`. Baja las fotos
  /// (una falla no aborta: se registra como faltante y continúa).
  static Future<PatientExportResult> buildPatientFiles(
    DataRepository repo,
    Patient p, {
    String prefix = '',
  }) async {
    final root = '$prefix${sanitize(p.folio)}';
    final files = <ExportedFile>[
      ExportedFile('$root/datos.csv', _patientDataCsv(repo, p)),
      ExportedFile('$root/mediciones.csv', _patientMeasurementsCsv(repo, p)),
      ExportedFile('$root/consultas.csv', _patientConsultationsCsv(repo, p)),
    ];
    var photoCount = 0;
    var photoMissing = 0;
    final missing = <String>[];
    for (final w in repo.listWoundsForPatient(p.id)) {
      final wdir =
          '$root/heridas/${sanitize(w.id)}_${sanitize(w.etiology.name)}';
      files.add(
          ExportedFile('$wdir/mediciones.csv', _woundMeasurementsCsv(repo, w)));
      final photos = repo.listPhotosForWound(w.id)
        ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
      for (final ph in photos) {
        // Nombre con la FECHA al inicio: cualquier explorador ordena la serie
        // evolutiva cronológicamente (el detalle que sustituye al PDF).
        final shortId = ph.id.length <= 8 ? ph.id : ph.id.substring(0, 8);
        final relPath = '$wdir/fotos/${_d(ph.takenAt)}_${sanitize(shortId)}.jpg';
        try {
          final bytes =
              await PhotoUploadService.downloadWoundPhotoBytes(ph.storagePath);
          files.add(ExportedFile(relPath, bytes));
          photoCount++;
        } catch (_) {
          photoMissing++;
          missing.add(relPath);
        }
      }
    }
    return PatientExportResult(
      files: files,
      photoCount: photoCount,
      photoMissing: photoMissing,
      missingPhotos: missing,
    );
  }

  /// Manifiesto de un export de UN paciente: qué se exportó + fotos faltantes.
  static List<int> patientManifestCsv(Patient p, PatientExportResult r) {
    final rows = <List<dynamic>>[
      ['tipo', 'ruta', 'estado'],
      ['paciente', p.folio, p.fullName],
    ];
    for (final f in r.files) {
      rows.add(['archivo', f.path, 'ok']);
    }
    for (final m in r.missingPhotos) {
      rows.add(['foto', m, 'FALTANTE']);
    }
    rows.add([
      'resumen',
      'fotos ok=${r.photoCount} faltantes=${r.photoMissing}',
      ''
    ]);
    return _csvBytes(rows);
  }

  /// Empaqueta archivos en un ZIP (en memoria; suficiente para un paciente).
  static Uint8List zip(List<ExportedFile> files) {
    final archive = Archive();
    for (final f in files) {
      archive.addFile(ArchiveFile(f.path, f.bytes.length, f.bytes));
    }
    final out = ZipEncoder().encode(archive);
    return Uint8List.fromList(out ?? const []);
  }
}
