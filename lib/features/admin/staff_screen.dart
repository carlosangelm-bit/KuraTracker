import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/widgets/kura_primary_fab.dart';
import 'staff_avatar.dart';
import '../../models/app_user.dart';
import '../../models/site.dart';
import '../../models/staff.dart';
import '../../services/data_repository.dart';

/// Personal sanitario del centro (sección de Administración). Salió de
/// admin_home_screen.dart (etapa 2 de «Admin del centro — Usuarios, Personal, Sitios»),
/// con el mismo patrón que dejó [UsersScreen] en la etapa 1.
///
/// Es un CUERPO de sección, no una pantalla completa: NO se envuelve en KuraScreen ni
/// trae AppBar. AdminSectionsShell ya pinta el KuraContentHeader («Administración ›
/// Personal») y el KuraNavRail con la cuenta en el pie; el Scaffold aquí es solo para
/// hospedar el KuraPrimaryFab. Todo color sale de [BrandTokens] (respeta la marca del
/// centro: morado/azul/rosa), nunca del alias de marca fija.
///
/// Se reutiliza en dos contextos, como Usuarios:
///   - Panel de Administración (admin de centro): organizationId = su centro.
///   - Área de Plataforma (master): organizationId = centro elegido en el selector.
class StaffScreen extends StatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  const StaffScreen({super.key, required this.repo, required this.organizationId});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  Future<void> _openStaffForm({StaffMember? existing}) async {
    final sites = widget.repo.listSites(organizationId: widget.organizationId);
    // Candidatos para vincular profile_id: perfiles sin fila en staff aun,
    // mas -si estamos editando- el profile ya vinculado a este registro
    // (para no desaparecerlo de la lista al abrir el formulario).
    final candidates = [...widget.repo.listProfilesWithoutStaffLink()];
    if (existing?.profileId != null) {
      final current =
          widget.repo.listUsers().where((u) => u.id == existing!.profileId);
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
        organizationId: widget.organizationId,
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final staff = widget.repo.listStaff(organizationId: widget.organizationId);
    return Scaffold(
      body: staff.isEmpty
          ? const _StaffEmptyState(
              icon: Icons.medical_services_outlined,
              message: 'Aún no hay personal sanitario registrado.\n'
                  'Usa el botón "Nuevo" para dar de alta al primero.',
            )
          : ListView.separated(
              padding:
                  EdgeInsets.fromLTRB(16, 16, 16, kuraListBottomInset(context)),
              itemCount: staff.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _staffCard(staff[i]),
            ),
      floatingActionButton: KuraPrimaryFab(
        onPressed: () => _openStaffForm(),
        icon: Icons.person_add,
        label: 'Nuevo',
      ),
    );
  }

  Widget _staffCard(StaffMember s) {
    final t = BrandTokens.of(context);
    final site = s.primarySiteId == null
        ? null
        : widget.repo
            .listSites()
            .where((site) => site.id == s.primarySiteId)
            .firstOrNull;
    final noAccount = s.profileId == null;
    // El subtítulo concatena solo DATOS (folio · cargo · sede). El estado «sin cuenta»
    // no es un dato más: es una condición que pide acción y va como etiqueta (abajo).
    final subtitle = '${s.folio} · ${s.roleTitle}'
        '${site != null ? ' · ${site.name}' : ''}';
    return Card(
      child: ListTile(
        isThreeLine: noAccount,
        leading: StaffAvatar(member: s),
        title: Text(s.fullName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(subtitle),
            if (noAccount)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                // Mismo lenguaje visual que las etiquetas de rol de Usuarios; color de
                // estado (ámbar) porque no puede entrar a la app hasta vincularla.
                child: _tag('Sin cuenta', t.statusWarningText),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar',
              onPressed: () => _openStaffForm(existing: s),
            ),
            _activeSwitch(s),
          ],
        ),
      ),
    );
  }

  // El interruptor va CON rótulo, como en Usuarios y Sitios (un switch pelón no dice
  // qué activa). shrinkWrap para que rótulo + switch quepan en la fila del ListTile.
  Widget _activeSwitch(StaffMember s) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Activo', style: TextStyle(fontSize: 11)),
          Switch(
            value: s.isActive,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) async {
              await widget.repo.setStaffActive(s.id, v);
              if (mounted) setState(() {});
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

/// Estado vacío local (icono + mensaje), con [BrandTokens]. Local a propósito: el vacío
/// de Personal no lleva acción, a diferencia de KuraEmptyState.
class _StaffEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _StaffEmptyState({required this.icon, required this.message});

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

class _StaffFormDialog extends StatefulWidget {
  final DataRepository repo;
  final StaffMember? existing;
  final List<Site> sites;
  final List<AppUser> profileCandidates;
  final String? organizationId;

  const _StaffFormDialog({
    required this.repo,
    required this.existing,
    required this.sites,
    required this.profileCandidates,
    required this.organizationId,
  });

  @override
  State<_StaffFormDialog> createState() => _StaffFormDialogState();
}

class _StaffFormDialogState extends State<_StaffFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.existing?.fullName ?? '');
  late final TextEditingController _roleCtrl =
      TextEditingController(text: widget.existing?.roleTitle ?? 'Especialista');
  late final TextEditingController _cedulaCtrl =
      TextEditingController(text: widget.existing?.cedulaProfesional ?? '');
  late final TextEditingController _especialidadCtrl =
      TextEditingController(text: widget.existing?.especialidad ?? '');
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
    _especialidadCtrl.dispose();
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
      final especialidad = _especialidadCtrl.text.trim();
      if (widget.existing == null) {
        await widget.repo.createStaff(
          fullName: _nameCtrl.text.trim(),
          roleTitle:
              _roleCtrl.text.trim().isEmpty ? 'Especialista' : _roleCtrl.text.trim(),
          organizationId: widget.organizationId,
          primarySiteId: _siteId,
          profileId: _profileId,
          cedulaProfesional: cedula.isEmpty ? null : cedula,
          especialidad: especialidad.isEmpty ? null : especialidad,
        );
      } else {
        await widget.repo.updateStaff(
          widget.existing!.id,
          fullName: _nameCtrl.text.trim(),
          roleTitle:
              _roleCtrl.text.trim().isEmpty ? 'Especialista' : _roleCtrl.text.trim(),
          primarySiteId: _siteId,
          clearPrimarySiteId: _siteId == null,
          profileId: _profileId,
          clearProfileId: _profileId == null,
          cedulaProfesional: cedula.isEmpty ? null : cedula,
          clearCedulaProfesional: cedula.isEmpty,
          especialidad: especialidad.isEmpty ? null : especialidad,
          clearEspecialidad: especialidad.isEmpty,
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
      title: Text(isEdit ? 'Editar personal sanitario' : 'Nuevo personal sanitario'),
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
                  decoration: const InputDecoration(labelText: 'Nombre completo'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _roleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cargo',
                    hintText: 'Especialista, Médico, Enfermera…',
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
                TextFormField(
                  controller: _especialidadCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Especialidad',
                    hintText: 'Aparece en la firma de la nota (NOM-024/004)',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: _siteId,
                  decoration: const InputDecoration(labelText: 'Sitio principal'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('Sin asignar')),
                    ...widget.sites.map(
                      (s) => DropdownMenuItem<String?>(
                          value: s.id, child: Text(s.name)),
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
                        child: Text('${u.fullName} · ${u.email}',
                            overflow: TextOverflow.ellipsis),
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
                      style: TextStyle(fontSize: 11, color: t.textSecondary),
                    ),
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
