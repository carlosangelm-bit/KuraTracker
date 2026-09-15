import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/design/tokens.dart';
import '../../core/widgets/kura_primary_fab.dart';
import '../../services/data_repository.dart';
import '../../services/photo_upload_service.dart';

/// Marca del centro para reportes (color + logo que salen en los PDF del paciente).
/// Salió de admin_home_screen.dart (cierre de «Admin del centro»), con el mismo patrón
/// que las etapas 1-3.
///
/// Es un CUERPO de sección, no una pantalla completa: NO se envuelve en KuraScreen ni
/// trae AppBar. AdminSectionsShell ya pinta el KuraContentHeader («Administración ›
/// Marca») y el KuraNavRail con la cuenta en el pie. Todo color sale de [BrandTokens].
class BrandingScreen extends StatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  const BrandingScreen(
      {super.key, required this.repo, required this.organizationId});

  @override
  State<BrandingScreen> createState() => _BrandingScreenState();
}

class _BrandingScreenState extends State<BrandingScreen> {
  // Vacío por defecto (antes '#7C3AED', el violeta de la clínica FIJO). El color
  // propuesto cuando el centro no tiene uno guardado se siembra en
  // didChangeDependencies con el brandPrimary del PROPIO tipo de centro (azul en un
  // hospital, rosa en cuidadores): la pantalla propone su propia marca, no la de otra.
  final _colorCtrl = TextEditingController();
  Uint8List? _logoBytes;
  String? _logoName;
  String? _existingLogoPath;
  bool _loaded = false;
  bool _saving = false;
  bool _brandSeeded = false;
  final _picker = ImagePicker();

  static String _hex(Color c) =>
      '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static const _swatches = [
    '#7C3AED', '#1B8A5A', '#2563EB', '#C0392B',
    '#E8A93A', '#0F766E', '#9D174D', '#334155',
  ];

  @override
  void initState() {
    super.initState();
    final orgId = widget.organizationId;
    if (orgId != null) {
      final matches = widget.repo.listOrganizations().where((o) => o.id == orgId);
      if (matches.isNotEmpty) {
        final o = matches.first;
        if ((o.brandPrimaryColor ?? '').isNotEmpty) _colorCtrl.text = o.brandPrimaryColor!;
        _existingLogoPath = o.brandLogoPath;
      }
    }
    _loaded = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sin color guardado: propone el de la marca del PROPIO centro (según el tema del
    // tipo de centro), no un violeta fijo. Se siembra una sola vez y solo si el campo
    // sigue vacío (un color guardado ya lo llenó en initState).
    if (!_brandSeeded && _colorCtrl.text.trim().isEmpty) {
      _colorCtrl.text = _hex(BrandTokens.of(context).brandPrimary);
    }
    _brandSeeded = true;
  }

  @override
  void dispose() {
    _colorCtrl.dispose();
    super.dispose();
  }

  Color? _parse(String hex) {
    var h = hex.trim().replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }

  Future<void> _pickLogo() async {
    try {
      final x = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 90, maxWidth: 800, maxHeight: 800);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      setState(() {
        _logoBytes = bytes;
        _logoName = x.name;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo cargar el logo: $e')));
      }
    }
  }

  Future<void> _save() async {
    final orgId = widget.organizationId;
    if (orgId == null) return;
    final color = _colorCtrl.text.trim();
    if (_parse(color) == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Color inválido. Usa formato #RRGGBB.')));
      return;
    }
    setState(() => _saving = true);
    try {
      String? logoPath = _existingLogoPath;
      if (_logoBytes != null) {
        logoPath = await PhotoUploadService.uploadOrgLogo(
            organizationId: orgId, bytes: _logoBytes!, fileName: _logoName ?? 'logo.png');
      }
      await widget.repo.setOrgBranding(orgId, primaryColor: color, logoPath: logoPath);
      if (mounted) {
        setState(() {
          _existingLogoPath = logoPath;
          _logoBytes = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Branding guardado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final t = BrandTokens.of(context);
    // El color PROPUESTO cuando no hay uno guardado es el de la marca del PROPIO centro
    // (azul en un hospital, rosa en cuidadores), no un morado fijo: este color sale en
    // los PDF del paciente, así que la pantalla propone su propia marca, no otra.
    final color = _parse(_colorCtrl.text) ?? t.brandPrimary;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, kuraListBottomInset(context)),
      children: [
        const Text('Marca del centro para reportes',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        Text('El logo y el color aparecen en los reportes PDF que se entregan al paciente.',
            style: TextStyle(fontSize: 12, color: t.textSecondary)),
        const SizedBox(height: 16),
        const Text('Color principal', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black12),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _colorCtrl,
              decoration: const InputDecoration(labelText: 'Hex (#RRGGBB)'),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _swatches.map((h) {
            final c = _parse(h)!;
            return GestureDetector(
              onTap: () => setState(() => _colorCtrl.text = h),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                    color: c, shape: BoxShape.circle, border: Border.all(color: Colors.black12)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 20),
        const Text('Logo', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _logoPreview(),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.image_outlined, size: 18),
          label: Text(_logoBytes != null || (_existingLogoPath ?? '').isNotEmpty
              ? 'Cambiar logo'
              : 'Cargar logo'),
          onPressed: _saving ? null : _pickLogo,
        ),
        const SizedBox(height: 24),
        const Text('Vista previa del encabezado', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _headerPreview(color),
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: t.brandPrimary),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando…' : 'Guardar branding'),
        ),
      ],
    );
  }

  Widget _logoPreview() {
    final t = BrandTokens.of(context);
    if (_logoBytes != null) {
      return ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_logoBytes!, height: 80));
    }
    if ((_existingLogoPath ?? '').isNotEmpty) {
      return FutureBuilder<String>(
        future: PhotoUploadService.resolveOrgLogoUrl(_existingLogoPath!),
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done || s.data == null) {
            return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
          }
          return Image.network(s.data!, height: 80, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined));
        },
      );
    }
    return Text('Sin logo (se usará el nombre del centro).',
        style: TextStyle(fontSize: 12, color: t.textSecondary));
  }

  Widget _headerPreview(Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 4)),
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        if (_logoBytes != null)
          Image.memory(_logoBytes!, height: 36)
        else if ((_existingLogoPath ?? '').isNotEmpty)
          FutureBuilder<String>(
            future: PhotoUploadService.resolveOrgLogoUrl(_existingLogoPath!),
            builder: (c, s) => (s.data != null)
                ? Image.network(s.data!, height: 36, errorBuilder: (_, __, ___) => const SizedBox.shrink())
                : const SizedBox(width: 36, height: 36),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Reporte de herida',
              style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 16)),
        ),
      ]),
    );
  }
}
