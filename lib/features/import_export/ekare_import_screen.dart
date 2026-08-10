import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/wound.dart';

/// Importador del export de mediciones de eKare (KT-3): carga uno o varios CSV
/// y crea pacientes → heridas → historial de mediciones. Dedup por nombre+fecha
/// de nacimiento (no re-crea pacientes existentes). La PII vive solo en runtime
/// (no se commitea nada).
class EkareImportScreen extends ConsumerStatefulWidget {
  const EkareImportScreen({super.key});
  @override
  ConsumerState<EkareImportScreen> createState() => _EkareImportScreenState();
}

class _ImpMeasure {
  final DateTime date;
  final double l, w, a, depth, volume, red, yellow, black;
  _ImpMeasure(this.date, this.l, this.w, this.a, this.depth, this.volume,
      this.red, this.yellow, this.black);
}

class _ImpWound {
  final String uid;
  final String primaryType;
  final String location;
  final String? secondaryLocation;
  final DateTime? onset;
  final measures = <_ImpMeasure>[];
  _ImpWound(this.uid, this.primaryType, this.location, this.secondaryLocation,
      this.onset);
}

class _ImpPatient {
  final String key; // MRN o nombre+dob
  final String firstName, lastName;
  final DateTime? dob;
  final String? sex;
  final wounds = <String, _ImpWound>{};
  _ImpPatient(this.key, this.firstName, this.lastName, this.dob, this.sex);
  String get fullName => '$firstName $lastName'.trim();
}

class _EkareImportScreenState extends ConsumerState<EkareImportScreen> {
  final Map<String, _ImpPatient> _patients = {};
  final _files = <String>[];
  bool _busy = false;
  String? _result;

  static double _num(dynamic v) {
    final s = v?.toString().trim() ?? '';
    if (s.isEmpty || s == '-') return 0;
    return double.tryParse(s.replaceAll(',', '.')) ?? 0;
  }

  static DateTime? _date(dynamic v) {
    final s = v?.toString().trim() ?? '';
    final p = s.split('/');
    if (p.length != 3) return null;
    final d = int.tryParse(p[0]), m = int.tryParse(p[1]), y = int.tryParse(p[2]);
    if (d == null || m == null || y == null) return null;
    return DateTime(y, m, d);
  }

  Etiologia _etiology(String primaryType) {
    switch (primaryType.toLowerCase()) {
      case 'pressure injury':
        return Etiologia.lpp;
      case 'lymphovascular':
        return Etiologia.vascular;
      case 'surgical':
        return Etiologia.quirurgica;
      case 'trauma':
        return Etiologia.traumatica;
      case 'diabetic':
        return Etiologia.pieDiabetico;
      default:
        return Etiologia.otra; // Thermal, Other, etc.
    }
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
      allowMultiple: true,
    );
    if (result == null) return;
    for (final f in result.files) {
      final bytes = f.bytes;
      if (bytes == null) continue;
      _files.add(f.name);
      _parse(utf8.decode(bytes, allowMalformed: true));
    }
    setState(() => _result = null);
  }

  void _parse(String content) {
    // Quita BOM y normaliza saltos de línea.
    final clean = content.replaceFirst('﻿', '').replaceAll('\r\n', '\n');
    final rows =
        const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
            .convert(clean);
    if (rows.isEmpty) return;
    final header = rows.first.map((e) => e.toString().trim()).toList();
    int col(String name) => header.indexOf(name);
    final iFn = col('First name'),
        iLn = col('Last name'),
        iMrn = col('MRN'),
        iDob = col('DOB'),
        iSex = col('Sex'),
        iUid = col('Wound UID'),
        iType = col('Primary Wound Type'),
        iLoc = col('Wound location'),
        iSecLoc = col('Secondary location'),
        iOnset = col('Onset Date'),
        iDate = col('Date'),
        iL = col('L(cm)'),
        iW = col('W(cm)'),
        iA = col('A(cm^2)'),
        iDmax = col('D(max)'),
        iVol = col('Volume'),
        iRed = col('Red'),
        iYellow = col('Yellow'),
        iBlack = col('Black');
    if (iFn < 0 || iUid < 0 || iDate < 0) return; // no es el formato eKare

    String at(List row, int i) =>
        (i >= 0 && i < row.length) ? row[i].toString().trim() : '';

    for (final row in rows.skip(1)) {
      if (row.isEmpty) continue;
      final mrn = at(row, iMrn);
      final fn = at(row, iFn), ln = at(row, iLn);
      final dob = _date(at(row, iDob));
      if (fn.isEmpty && ln.isEmpty) continue;
      final pKey = mrn.isNotEmpty
          ? 'mrn:$mrn'
          : '${fn.toLowerCase()}|${ln.toLowerCase()}|${dob?.toIso8601String() ?? ''}';
      final patient = _patients.putIfAbsent(
          pKey, () => _ImpPatient(pKey, fn, ln, dob, at(row, iSex)));

      final uid = at(row, iUid);
      if (uid.isEmpty) continue;
      final wound = patient.wounds.putIfAbsent(
        uid,
        () => _ImpWound(uid, at(row, iType), at(row, iLoc),
            at(row, iSecLoc).isEmpty ? null : at(row, iSecLoc), _date(at(row, iOnset))),
      );

      final date = _date(at(row, iDate));
      final a = _num(at(row, iA)),
          l = _num(at(row, iL)),
          w = _num(at(row, iW));
      // Salta filas sin medición real (área y dimensiones en cero).
      if (date == null || (a == 0 && l == 0 && w == 0)) continue;
      wound.measures.add(_ImpMeasure(
        date, l, w, a, _num(at(row, iDmax)), _num(at(row, iVol)),
        _num(at(row, iRed)), _num(at(row, iYellow)), _num(at(row, iBlack)),
      ));
    }
  }

  int get _woundCount =>
      _patients.values.fold(0, (n, p) => n + p.wounds.length);
  int get _measureCount => _patients.values
      .fold(0, (n, p) => n + p.wounds.values.fold(0, (m, w) => m + w.measures.length));

  Future<void> _import() async {
    final repo = ref.read(dataRepositoryProvider).valueOrNull;
    final orgId = ref.read(sessionProvider).user?.organizationId;
    if (repo == null || orgId == null) return;
    setState(() => _busy = true);
    var created = 0, skipped = 0, wounds = 0, measures = 0, measureErrors = 0;
    try {
      // Índice de pacientes existentes por nombre+dob para dedup.
      final existing = <String>{
        for (final p in repo.listAllPatients().where((p) => p.organizationId == orgId))
          '${p.fullName.toLowerCase()}|${p.birthDate?.toIso8601String() ?? ''}'
      };
      for (final p in _patients.values) {
        final dedupKey =
            '${p.fullName.toLowerCase()}|${p.dob?.toIso8601String() ?? ''}';
        if (existing.contains(dedupKey)) {
          skipped++;
          continue;
        }
        final patient = await repo.createPatient(
          fullName: p.fullName,
          organizationId: orgId,
          birthDate: p.dob,
          sex: p.sex == 'Female' ? 'F' : (p.sex == 'Male' ? 'M' : 'otro'),
        );
        created++;
        existing.add(dedupKey);
        for (final w in p.wounds.values) {
          final wound = await repo.createWound({
            'patient_id': patient.id,
            'etiology': _etiology(w.primaryType).dbValue,
            'body_location_primary':
                w.location.isEmpty ? 'no_especificado' : w.location,
            'body_location_secondary': w.secondaryLocation,
            'onset_date': w.onset?.toIso8601String().substring(0, 10),
          });
          wounds++;
          for (final m in w.measures) {
            // Composición del lecho: eKare da Red/Yellow/Black en %. La BD exige
            // granulación+esfacelo+necrosis+epitelización ≤ 100.01; por redondeo
            // eKare a veces suma 100.1 → se normaliza a 100 si se pasa.
            var r = m.red, y = m.yellow, b = m.black;
            final tot = r + y + b;
            if (tot > 100.01 && tot > 0) {
              final f = 100 / tot;
              r *= f;
              y *= f;
              b *= f;
            }
            try {
              await repo.createMeasurement({
                'wound_id': wound.id,
                'consultation_id': null,
                'measured_at': m.date.toIso8601String(),
                'length_cm': m.l,
                'width_cm': m.w,
                'area_cm2': m.a,
                'depth_cm': m.depth,
                'volume_cm3': m.volume > 0 ? m.volume : null,
                'granulation_pct': r,
                'slough_pct': y,
                'necrosis_pct': b,
              });
              measures++;
            } catch (_) {
              measureErrors++;
            }
          }
        }
      }
      setState(() {
        _result = 'Importados: $created pacientes, $wounds heridas, $measures '
            'mediciones. Omitidos (ya existían): $skipped.'
            '${measureErrors > 0 ? ' Mediciones con error (omitidas): $measureErrors.' : ''}';
        _patients.clear();
        _files.clear();
      });
    } catch (e) {
      setState(() => _result = 'Error: $e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importar de eKare')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Carga el/los CSV de mediciones exportados de eKare. Se crearán '
                'pacientes, heridas y su historial de mediciones. Los pacientes '
                'que ya existan (mismo nombre y fecha de nacimiento) se omiten.',
                style: TextStyle(
                    fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Seleccionar CSV (uno o varios)'),
                onPressed: _busy ? null : _pick,
              ),
              if (_files.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Archivos: ${_files.join(', ')}',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Listo para importar',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text('Pacientes: ${_patients.length}'),
                        Text('Heridas: $_woundCount'),
                        Text('Mediciones: $_measureCount'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(_busy ? 'Importando…' : 'Importar'),
                  onPressed: (_busy || _patients.isEmpty) ? null : _import,
                ),
              ],
              if (_result != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: KuraColors.success.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_result!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
