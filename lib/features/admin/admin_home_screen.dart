import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../models/app_user.dart';
import '../../models/note_option_catalog.dart';
import '../../models/site.dart';
import '../../models/staff.dart';
import '../../services/data_repository.dart';

/// Panel de administración: gestión de personal sanitario, sitios y
/// activación de usuarios / función premium (sección 4).
class AdminHomeScreen extends ConsumerStatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  ConsumerState<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends ConsumerState<AdminHomeScreen>
    with SingleTickerProviderStateMixin {
  int _tab = 0;
  // TabController propio y explícito: NO depende de DefaultTabController.
  //
  // Bug previo: `TabBar` vivía en `AppBar.bottom` mientras `DefaultTabController`
  // envolvía solo el `body`. En el árbol de widgets, TabBar y DefaultTabController
  // quedaban como HERMANOS (AppBar y body son ambos hijos directos de Scaffold),
  // no en relación ancestro/descendiente. Por eso `DefaultTabController.maybeOf(context)`
  // -llamado internamente por TabBar- devolvía null. En debug esto lanza un
  // FlutterError controlado por assert(); en release (el build real desplegado)
  // el assert se elimina y el controller interno de TabBar queda null, causando
  // luego "Null check operator used on a null value" dentro del propio framework
  // de Flutter (_TabBarState), no en código de esta pantalla. Ocurría siempre,
  // con datos vacíos o no: no dependía de que el admin tuviera o no fila en `staff`.
  late final TabController _tabController = TabController(length: 4, vsync: this)
    ..addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index != _tab) {
        setState(() => _tab = _tabController.index);
      }
    });

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Usuarios'),
            Tab(text: 'Personal sanitario'),
            Tab(text: 'Sitios'),
            Tab(text: 'Configuración'),
          ],
          onTap: (i) => setState(() => _tab = i),
        ),
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          switch (_tab) {
            case 1:
              return _StaffTab(repo: repo);
            case 2:
              return _SitesTab(repo: repo);
            case 3:
              return _NoteCatalogTab(repo: repo);
            default:
              return _UsersTab(repo: repo);
          }
        },
      ),
    );
  }
}

class _UsersTab extends StatefulWidget {
  final DataRepository repo;
  const _UsersTab({required this.repo});

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  @override
  Widget build(BuildContext context) {
    final users = widget.repo.listUsers();
    if (users.isEmpty) {
      return const _EmptyState(
        icon: Icons.people_outline,
        message: 'Aún no hay usuarios registrados.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final u = users[i];
        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: KuraColors.primary.withOpacity(0.12),
              child: Icon(
                u.role == AppRole.admin ? Icons.admin_panel_settings : Icons.medical_services,
                color: KuraColors.primary,
              ),
            ),
            title: Text(u.fullName),
            subtitle: Text('${u.email} · ${u.role.label}'
                '${u.staffId == null ? '' : ' · vinculado a personal sanitario'}'),
            trailing: Wrap(
              spacing: 12,
              children: [
                Column(
                  children: [
                    const Text('Activo', style: TextStyle(fontSize: 10)),
                    Switch(
                      value: u.isActive,
                      activeColor: KuraColors.primary,
                      onChanged: (v) async {
                        await widget.repo.setUserActive(u.id, v);
                        setState(() {});
                      },
                    ),
                  ],
                ),
                Column(
                  children: [
                    const Text('Premium', style: TextStyle(fontSize: 10)),
                    Switch(
                      value: u.premiumEnabled,
                      activeColor: KuraColors.success,
                      onChanged: (v) async {
                        await widget.repo.setUserPremium(u.id, v);
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StaffTab extends StatefulWidget {
  final DataRepository repo;
  const _StaffTab({required this.repo});

  @override
  State<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<_StaffTab> {
  Future<void> _openStaffForm({StaffMember? existing}) async {
    final sites = widget.repo.listSites();
    // Candidatos para vincular profile_id: perfiles sin fila en staff aun,
    // mas -si estamos editando- el profile ya vinculado a este registro
    // (para no desaparecerlo de la lista al abrir el formulario).
    final candidates = [...widget.repo.listProfilesWithoutStaffLink()];
    if (existing?.profileId != null) {
      final current = widget.repo.listUsers().where((u) => u.id == existing!.profileId);
      if (current.isNotEmpty && candidates.every((c) => c.id != current.first.id)) {
        candidates.add(current.first);
      }
    }

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _StaffFormDialog(
        repo: widget.repo,
        existing: existing,
        sites: sites,
        profileCandidates: candidates,
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final staff = widget.repo.listStaff();
    return Scaffold(
      body: staff.isEmpty
          ? const _EmptyState(
              icon: Icons.medical_services_outlined,
              message: 'Aún no hay personal sanitario registrado.\n'
                  'Usa el botón "Nuevo" para dar de alta al primero.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: staff.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final s = staff[i];
                final site = s.primarySiteId == null
                    ? null
                    : widget.repo
                        .listSites()
                        .where((site) => site.id == s.primarySiteId)
                        .firstOrNull;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: KuraColors.primary.withOpacity(0.12),
                      child: Text(s.folio.substring(1, 3)),
                    ),
                    title: Text(s.fullName),
                    subtitle: Text(
                      '${s.folio} · ${s.roleTitle}'
                      '${site != null ? ' · ${site.name}' : ''}'
                      '${s.profileId == null ? ' · sin cuenta vinculada' : ''}',
                    ),
                    trailing: Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Editar',
                          onPressed: () => _openStaffForm(existing: s),
                        ),
                        Switch(
                          value: s.isActive,
                          activeColor: KuraColors.primary,
                          onChanged: (v) async {
                            await widget.repo.setStaffActive(s.id, v);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: KuraColors.primary,
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo'),
        onPressed: () => _openStaffForm(),
      ),
    );
  }
}

class _StaffFormDialog extends StatefulWidget {
  final DataRepository repo;
  final StaffMember? existing;
  final List<Site> sites;
  final List<AppUser> profileCandidates;

  const _StaffFormDialog({
    required this.repo,
    required this.existing,
    required this.sites,
    required this.profileCandidates,
  });

  @override
  State<_StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends State<_StaffFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.existing?.fullName ?? '');
  late final TextEditingController _roleCtrl =
      TextEditingController(text: widget.existing?.roleTitle ?? 'Kurador');
  late final TextEditingController _cedulaCtrl =
      TextEditingController(text: widget.existing?.cedulaProfesional ?? '');
  String? _siteId;
  String? _profileId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _siteId = widget.existing?.primarySiteId;
    _profileId = widget.existing?.profileId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    _cedulaCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final cedula = _cedulaCtrl.text.trim();
      if (widget.existing == null) {
        await widget.repo.createStaff(
          fullName: _nameCtrl.text.trim(),
          roleTitle: _roleCtrl.text.trim().isEmpty ? 'Kurador' : _roleCtrl.text.trim(),
          primarySiteId: _siteId,
          profileId: _profileId,
          cedulaProfesional: cedula.isEmpty ? null : cedula,
        );
      } else {
        await widget.repo.updateStaff(
          widget.existing!.id,
          fullName: _nameCtrl.text.trim(),
          roleTitle: _roleCtrl.text.trim().isEmpty ? 'Kurador' : _roleCtrl.text.trim(),
          primarySiteId: _siteId,
          clearPrimarySiteId: _siteId == null,
          profileId: _profileId,
          clearProfileId: _profileId == null,
          cedulaProfesional: cedula.isEmpty ? null : cedula,
          clearCedulaProfesional: cedula.isEmpty,
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
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Editar personal sanitario' : 'Nuevo personal sanitario'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nombre completo'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _roleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cargo',
                    hintText: 'Kurador, Médico, Enfermera...',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cedulaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cédula profesional',
                    hintText: 'Requerida para firmar notas de seguimiento',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: _siteId,
                  decoration: const InputDecoration(labelText: 'Sitio principal'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Sin asignar')),
                    ...widget.sites.map(
                      (s) => DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                    ),
                  ],
                  onChanged: (v) => setState(() => _siteId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: _profileId,
                  decoration: const InputDecoration(
                    labelText: 'Cuenta de usuario vinculada',
                    helperText:
                        'Vincula este registro a una cuenta ya existente para que\n'
                        'esa persona pueda operar (crear consultas) como este\n'
                        'personal sanitario al iniciar sesión.',
                    helperMaxLines: 3,
                  ),
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Sin vincular (solo registro administrativo)'),
                    ),
                    ...widget.profileCandidates.map(
                      (u) => DropdownMenuItem<String?>(
                        value: u.id,
                        child: Text('${u.fullName} · ${u.email}', overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _profileId = v),
                ),
                if (widget.profileCandidates.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'No hay cuentas de usuario disponibles para vincular '
                      '(todas ya tienen personal sanitario asociado).',
                      style: TextStyle(fontSize: 11, color: KuraColors.darkText.withOpacity(0.5)),
                    ),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: KuraColors.danger)),
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
          style: FilledButton.styleFrom(backgroundColor: KuraColors.primary),
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

class _SitesTab extends StatefulWidget {
  final DataRepository repo;
  const _SitesTab({required this.repo});

  @override
  State<_SitesTab> createState() => _SitesTabState();
}

class _SitesTabState extends State<_SitesTab> {
  Future<void> _openSiteForm({Site? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SiteFormDialog(repo: widget.repo, existing: existing),
    );
    if (saved == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sites = widget.repo.listSites();
    return Scaffold(
      body: sites.isEmpty
          ? const _EmptyState(
              icon: Icons.location_on_outlined,
              message: 'Aún no hay sitios registrados.\n'
                  'Usa el botón "Nuevo" para dar de alta el primero '
                  '(clínica, domicilio, hospital...).',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: sites.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final s = sites[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.location_on_outlined, color: KuraColors.primary),
                    title: Text(s.name),
                    subtitle: Text('${_kindLabel(s.kind)}${s.address != null ? ' · ${s.address}' : ''}'),
                    trailing: Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Editar',
                          onPressed: () => _openSiteForm(existing: s),
                        ),
                        Column(
                          children: [
                            const Text('Activo', style: TextStyle(fontSize: 10)),
                            Switch(
                              value: s.isActive,
                              activeColor: KuraColors.primary,
                              onChanged: (v) async {
                                await widget.repo.setSiteActive(s.id, v);
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: KuraColors.primary,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Nuevo'),
        onPressed: () => _openSiteForm(),
      ),
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

class _SiteFormDialog extends StatefulWidget {
  final DataRepository repo;
  final Site? existing;
  const _SiteFormDialog({required this.repo, required this.existing});

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
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'Editar sitio' : 'Nuevo sitio'),
      content: SizedBox(
        width: 420,
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
                  decoration: const InputDecoration(labelText: 'Dirección (opcional)'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: KuraColors.danger)),
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
          style: FilledButton.styleFrom(backgroundColor: KuraColors.primary),
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Guardar'),
        ),
      ],
    );
  }
}

/// Pantalla de Configuración (dentro del panel de Administración): el
/// admin gestiona por campo los conceptos del catálogo de la nota de
/// seguimiento (note_option_catalog, ver 0010_note_option_catalog.sql).
/// Agregar/editar/desactivar aquí es lo único que persiste conceptos al
/// catálogo del centro; el personal clínico solo los selecciona como
/// chips al capturar una nota (ver follow_up_capture_screen.dart).
class _NoteCatalogTab extends StatefulWidget {
  final DataRepository repo;
  const _NoteCatalogTab({required this.repo});

  @override
  State<_NoteCatalogTab> createState() => _NoteCatalogTabState();
}

class _NoteCatalogTabState extends State<_NoteCatalogTab> {
  NoteOptionField _selectedField = NoteOptionField.careType;

  Future<void> _addOption() async {
    final label = await _promptForLabel(context, title: 'Nuevo concepto');
    if (label == null || label.trim().isEmpty) return;
    try {
      await widget.repo.createNoteOption(field: _selectedField, label: label.trim());
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo agregar: $e')),
        );
      }
    }
  }

  Future<void> _toggleActive(NoteOptionCatalogItem item) async {
    try {
      await widget.repo.setNoteOptionActive(item.id, !item.isActive);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.repo.listAllNoteOptions(_selectedField);
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Catálogo de la nota de seguimiento',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'Estos conceptos son los que el personal clínico ve como '
                  'chips al registrar una nota de seguimiento. Configúralos '
                  'una vez para todo el centro; desactivar no borra el '
                  'historial de notas que ya los usaron.',
                  style: TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: NoteOptionField.values.map((f) {
                    final selected = f == _selectedField;
                    return ChoiceChip(
                      label: Text(f.label),
                      selected: selected,
                      selectedColor: KuraColors.primary.withOpacity(0.15),
                      onSelected: (_) => setState(() => _selectedField = f),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: options.isEmpty
                ? const _EmptyState(
                    icon: Icons.list_alt_outlined,
                    message: 'Sin conceptos configurados aún para este campo.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final o = options[i];
                      return Card(
                        color: o.isActive ? null : KuraColors.chipBg,
                        child: ListTile(
                          title: Text(
                            o.label,
                            style: TextStyle(
                              decoration: o.isActive ? null : TextDecoration.lineThrough,
                              color: o.isActive
                                  ? null
                                  : KuraColors.darkText.withOpacity(0.5),
                            ),
                          ),
                          trailing: Switch(
                            value: o.isActive,
                            activeColor: KuraColors.primary,
                            onChanged: (_) => _toggleActive(o),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: KuraColors.primary,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo concepto'),
        onPressed: _addOption,
      ),
    );
  }
}

Future<String?> _promptForLabel(BuildContext context, {required String title}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Texto del concepto'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text),
          style: FilledButton.styleFrom(backgroundColor: KuraColors.primary),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: KuraColors.darkText.withOpacity(0.25)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: KuraColors.darkText.withOpacity(0.5)),
            ),
          ],
        ),
      ),
    );
  }
}
