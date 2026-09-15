import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/widgets/kura_primary_fab.dart';
import '../../models/site.dart';
import '../../services/data_repository.dart';

/// Sitios del centro (sección de Administración). Salió de admin_home_screen.dart
/// (etapa 3 de «Admin del centro — Usuarios, Personal, Sitios»), con el mismo patrón
/// que dejaron [UsersScreen] y [StaffScreen].
///
/// Es un CUERPO de sección, no una pantalla completa: NO se envuelve en KuraScreen ni
/// trae AppBar. AdminSectionsShell ya pinta el KuraContentHeader («Administración ›
/// Sitios») y el KuraNavRail con la cuenta en el pie; el Scaffold aquí es solo para
/// hospedar el KuraPrimaryFab. Todo color sale de [BrandTokens] (respeta la marca del
/// centro), nunca del alias de marca fija.
///
/// El candado comercial se conserva tal cual: el PRIMER sitio va incluido; del segundo
/// en adelante exige el módulo Administración (avanzado), y sin él el FAB cambia a
/// candado y abre el mensaje de venta.
///
/// Desactivar un sitio pasa por la guardia de [DataRepository.setSiteActive] (y su
/// trigger 0134): puede rechazarse (único activo / personal asignado / inventario). El
/// mensaje se muestra con [_showRepoError], igual que Usuarios y Personal.
class SitesScreen extends StatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  const SitesScreen({super.key, required this.repo, required this.organizationId});

  @override
  State<SitesScreen> createState() => _SitesScreenState();
}

class _SitesScreenState extends State<SitesScreen> {
  /// Muestra el mensaje de un rechazo del repositorio (candado comercial o guardia de
  /// desactivación). Están redactados para decir qué hacer; morían silenciosos en el
  /// interruptor.
  void _showRepoError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', ''))));
  }

  Future<void> _openSiteForm({Site? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SiteFormDialog(
        repo: widget.repo,
        existing: existing,
        organizationId: widget.organizationId,
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sites = widget.repo.listSites(organizationId: widget.organizationId);
    // El PRIMER sitio va incluido; del segundo en adelante requiere el módulo
    // Administración (avanzado). Editar/activar los existentes no se gatea.
    final canAddSite =
        sites.isEmpty || widget.repo.premiumAdminFor(widget.organizationId);
    return Scaffold(
      body: sites.isEmpty
          ? const _SitesEmptyState(
              icon: Icons.location_on_outlined,
              message: 'Aún no hay sitios registrados.\n'
                  'Usa el botón "Nuevo" para dar de alta el primero '
                  '(clínica, domicilio, hospital...).',
            )
          : ListView.separated(
              padding:
                  EdgeInsets.fromLTRB(16, 16, 16, kuraListBottomInset(context)),
              itemCount: sites.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _siteCard(sites[i]),
            ),
      floatingActionButton: KuraPrimaryFab(
        onPressed: canAddSite
            ? () => _openSiteForm()
            : () => _showAdminModuleUpsell(context),
        icon: canAddSite ? Icons.add_location_alt_outlined : Icons.lock_outline,
        label: 'Nuevo',
      ),
    );
  }

  Widget _siteCard(Site s) {
    final t = BrandTokens.of(context);
    final hasAddress = s.address != null && s.address!.isNotEmpty;
    return Card(
      child: ListTile(
        isThreeLine: hasAddress,
        leading: Icon(Icons.location_on_outlined, color: t.brandPrimary),
        title: Text(s.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 2),
            // El TIPO de sitio sale del texto corrido a una etiqueta, con el mismo
            // lenguaje visual que las de Usuarios y Personal.
            _tag(_kindLabel(s.kind), t.brandPrimary),
            if (hasAddress)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(s.address!,
                    style: TextStyle(fontSize: 13, color: t.textSecondary)),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar',
              onPressed: () => _openSiteForm(existing: s),
            ),
            _activeSwitch(s),
          ],
        ),
      ),
    );
  }

  // Interruptor CON rótulo, como en Usuarios y Personal. La desactivación puede
  // rechazarse (guardia de setSiteActive); el mensaje va por _showRepoError.
  Widget _activeSwitch(Site s) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Activo', style: TextStyle(fontSize: 11)),
          Switch(
            value: s.isActive,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) async {
              try {
                await widget.repo.setSiteActive(s.id, v);
                if (mounted) setState(() {});
              } catch (e) {
                _showRepoError(e);
              }
            },
          ),
        ],
      );

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

String _kindLabel(String kind) {
  switch (kind) {
    case 'clinica':
      return 'Clínica';
    case 'domicilio':
      return 'Domicilio';
    case 'hospital':
      return 'Hospital';
    default:
      return 'Otro';
  }
}

/// Mensaje de venta del módulo Administración (avanzado) cuando el centro intenta un
/// segundo sitio sin el add-on. Mismo texto que en admin_home_screen.dart.
void _showAdminModuleUpsell(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
          'Esta función es parte del módulo Administración avanzada. Solicítalo '
          'a tu administrador de plataforma para habilitarla.')));
}

/// Estado vacío local (icono + mensaje), con [BrandTokens]. Local a propósito: el vacío
/// de Sitios no lleva acción, a diferencia de KuraEmptyState.
class _SitesEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _SitesEmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: t.textDisabled),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SiteFormDialog extends StatefulWidget {
  final DataRepository repo;
  final Site? existing;
  final String? organizationId;
  const _SiteFormDialog({
    required this.repo,
    required this.existing,
    required this.organizationId,
  });

  @override
  State<_SiteFormDialog> createState() => _SiteFormDialogState();
}

class _SiteFormDialogState extends State<_SiteFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _addressCtrl =
      TextEditingController(text: widget.existing?.address ?? '');
  late String _kind = widget.existing?.kind ?? 'clinica';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final address = _addressCtrl.text.trim();
      if (widget.existing == null) {
        await widget.repo.createSite(Site(
          id: '',
          name: _nameCtrl.text.trim(),
          kind: _kind,
          address: address.isEmpty ? null : address,
          organizationId: widget.organizationId,
        ));
      } else {
        await widget.repo.updateSite(
          widget.existing!.id,
          name: _nameCtrl.text.trim(),
          kind: _kind,
          address: address.isEmpty ? null : address,
          clearAddress: address.isEmpty,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = 'No se pudo guardar: $e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Editar sitio' : 'Nuevo sitio'),
      content: SizedBox(
        // Responsivo: en pantallas angostas llena el ancho disponible (lo acota
        // el AlertDialog) en vez de forzar 420px y desbordar en movil.
        width: MediaQuery.sizeOf(context).width < 500 ? double.maxFinite : 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre del sitio'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _kind,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: const [
                    DropdownMenuItem(value: 'clinica', child: Text('Clínica')),
                    DropdownMenuItem(value: 'domicilio', child: Text('Domicilio')),
                    DropdownMenuItem(value: 'hospital', child: Text('Hospital')),
                    DropdownMenuItem(value: 'otro', child: Text('Otro')),
                  ],
                  onChanged: (v) => setState(() => _kind = v ?? 'clinica'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Dirección (opcional)'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: t.statusDanger)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: t.brandPrimary),
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
