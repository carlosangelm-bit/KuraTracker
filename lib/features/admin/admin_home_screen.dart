import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/design/tokens.dart';
import '../../core/design/tints.dart';
import '../../core/widgets/kura_data_table.dart';
import '../../core/widgets/kura_action_bar.dart';
import '../../core/widgets/kura_module_lock.dart';
import '../../core/widgets/kura_empty_state.dart';
import '../../core/widgets/kura_error_state.dart';
import '../../core/widgets/dashed_border_box.dart';
import '../../core/name_format.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show KuraAccountMenu;
import '../../core/widgets/kura_primary_fab.dart';
import '../../core/nav/kura_nav_rail.dart';
import '../../core/nav/kura_nav_destinations.dart';
import 'license_panel.dart';
import 'users_screen.dart';
import '../../models/app_user.dart';
import '../../models/module_key.dart';
import '../../models/note_option_catalog.dart';
import '../../models/site.dart';
import '../../models/staff.dart';
import '../../services/csv_download.dart';
import '../../services/data_repository.dart';
import '../../services/photo_upload_service.dart';

/// Panel de administración: gestión de personal sanitario, sitios y
/// activación de usuarios / función premium (sección 4).
/// SHELL de las secciones de Administración: pinta el riel único (KuraNavRail) y, en
/// colapsado, el menú del encabezado; el cuerpo de la sección llega como [child].
/// Vive en un ShellRoute ANIDADO, así que cambiar de sección NO reconstruye el riel —
/// solo cambia el child. Se ve como cambiar de panel, no como cargar otra página.
class AdminSectionsShell extends ConsumerStatefulWidget {
  final Widget child;
  final String currentRoute; // /admin/<section>
  const AdminSectionsShell(
      {super.key, required this.child, required this.currentRoute});

  @override
  ConsumerState<AdminSectionsShell> createState() =>
      _AdminSectionsShellState();
}

class _AdminSectionsShellState extends ConsumerState<AdminSectionsShell> {
  // Colapso MANUAL del riel. null = seguir el ancho (auto); true/false = elección
  // del usuario. Vive en el State del shell, que persiste en el ShellRoute, así que
  // la elección sobrevive a los cambios de sección.
  bool? _userCollapsed;

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final currentRoute = widget.currentRoute;
    // Guarda de rol (2ª capa; el redirect del router es la 1ª). En web una URL
    // no es candado: solo admin del centro y master ven Administración. Un
    // clinico que llegue aquí por cualquier ruta no ve nada administrativo.
    final sessionUser = ref.watch(sessionProvider).user;
    if (sessionUser != null && !sessionUser.isAdmin && !sessionUser.isMaster) {
      return const Scaffold(
        body: Center(child: Text('No tienes acceso a esta sección.')),
      );
    }
    // Riel abierto ≥1200 px por defecto (§2.1/§2.2); el botón de colapsar/expandir
    // manda por encima del ancho una vez que el usuario lo toca.
    final autoCollapsed = MediaQuery.of(context).size.width < 1200;
    final collapsed = _userCollapsed ?? autoCollapsed;
    // UN solo riel: la MISMA declaración de la app, con los destinos clínicos de
    // primer nivel y Administración anidando sus seis secciones.
    final modules = ref.watch(enabledModulesProvider);
    final navs = kuraNavDestinations(
      moduleEnabled: (k) => modules.any((m) => m.dbValue == k),
      isAdmin: true,
      isMaster: false,
      // Tipo de centro activo: define la rama de agenda (hospital → Rondas).
      centerType: ref.watch(sessionProvider).activeCenterType,
    );
    final admin = navs.firstWhere((d) => d.route == '/admin');

    // SIN AppBar: el encabezado vive DENTRO del área de contenido (canvas). El nombre
    // de la sección sale una sola vez, ahí. En angosto ese mismo encabezado lleva el
    // menú Sección › Subsección ▾. Administración no tiene acciones (la identidad se
    // eliminó: el pie del riel ya dice quién eres y en qué centro).
    final content = Column(
      children: [
        KuraContentHeader(
          section: admin,
          currentRoute: currentRoute,
          collapsed: collapsed,
        ),
        const Divider(height: 1),
        Expanded(child: child),
      ],
    );
    return Scaffold(
      body: Row(
        children: [
          KuraNavRail(
            destinations: navs,
            currentRoute: currentRoute,
            collapsed: collapsed,
            brandName: 'KuraTracker',
            userName: sessionUser?.fullName,
            centerName: 'Administración',
            onToggleCollapse: () =>
                setState(() => _userCollapsed = !collapsed),
            // El pie del riel es el menú de cuenta (cerrar sesión, etc.): al quitar
            // el AppBar se fue el UserMenuButton, así que la identidad ES el control.
            accountMenuBuilder: (ctx, child) => KuraAccountMenu(child: child),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ],
      ),
    );
  }
}

/// El CUERPO de una sección de Administración (solo el panel, sin riel). Lo construye
/// cada ruta de sección con NoTransitionPage — cambiar de sección no navega, cambia el
/// panel dentro del mismo shell.
class AdminSectionBody extends ConsumerWidget {
  final String section;
  const AdminSectionBody({super.key, required this.section});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final sessionUser = ref.watch(sessionProvider).user;
    // organizationId/currentUserId del admin en sesión, acotan las altas al centro.
    final organizationId = sessionUser?.organizationId;
    final currentUserId = sessionUser?.id;
    return repoAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: KuraErrorState(
            title: 'No pudimos cargar la administración',
            reassurance:
                'Puede ser tu conexión. Tus datos están a salvo: nada se '
                'perdió ni se guardó a medias.',
            detail: '$e',
            onRetry: () => ref.invalidate(dataRepositoryProvider),
          ),
        ),
      ),
      data: (repo) {
        switch (section) {
          case 'personal':
            return StaffTab(repo: repo, organizationId: organizationId);
          case 'sitios':
            return SitesTab(repo: repo, organizationId: organizationId);
          case 'configuracion':
            return NoteCatalogTab(repo: repo, organizationId: organizationId);
          case 'marca':
            return repo.premiumAdminFor(organizationId)
                ? BrandingTab(repo: repo, organizationId: organizationId)
                : const _AdminModuleLocked('La personalización de marca');
          case 'licencias':
            return LicensePanel(
                repo: repo, organizationId: organizationId, user: sessionUser);
          default:
            return UsersScreen(
                repo: repo,
                organizationId: organizationId,
                currentUserId: currentUserId);
        }
      },
    );
  }
}

/// Candado del módulo Administración (AVANZADO). Las funciones administrativas
/// BÁSICAS van incluidas con la licencia clínica; solo lo avanzado (config del
/// protocolo, sitios extra, marca, 3 cupos admin dedicados) se cobra. Mismo criterio
/// que _PremiumLocked de Insumos: el mensaje dice qué falta y abre el camino de compra.
/// NO se gatean, a propósito: la pestaña Licencias (la compra vive ahí), el catálogo
/// base / escalas / fuente de recomendaciones, el Registro de divulgaciones ni la
/// exportación del expediente (custodia NOM-004/LFPDPPP no depende del pago).
void _showAdminModuleUpsell(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
          'Esta función es parte del módulo Administración avanzada. Solicítalo '
          'a tu administrador de plataforma para habilitarla.')));
}

/// Pantalla completa detrás del módulo Administración (avanzado): reemplaza el
/// contenido de una pestaña cuando el centro no lo tiene (p. ej. Marca).
class _AdminModuleLocked extends StatelessWidget {
  final String feature;
  const _AdminModuleLocked(this.feature);
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.workspace_premium_outlined,
                  color: KuraColors.warning),
              const SizedBox(height: 8),
              Text(
                '$feature es parte del módulo Administración avanzada.\n'
                'Solicítalo a tu administrador de plataforma para habilitarlo.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

class StaffTab extends StatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  const StaffTab({required this.repo, required this.organizationId});

  @override
  State<StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<StaffTab> {
  Future<void> _openStaffForm({StaffMember? existing}) async {
    final sites = widget.repo.listSites(organizationId: widget.organizationId);
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
          ? const _EmptyState(
              icon: Icons.medical_services_outlined,
              message: 'Aún no hay personal sanitario registrado.\n'
                  'Usa el botón "Nuevo" para dar de alta al primero.',
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(16, 16, 16, kuraListBottomInset(context)),
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
                      // Bug encontrado en verificacion E2E de Plataforma
                      // (master, tarea 9): el folio de un staff de alta
                      // administrativa (p.ej. el admin de un centro nuevo,
                      // ver ensureAdminStaffId()/DemoSeed Vitalis) puede ser
                      // '' (no sigue el patron K<year>-NNNN), y
                      // .substring(1,3) sobre '' lanza RangeError y tira
                      // toda la pantalla. Se usa un fallback seguro con las
                      // iniciales del nombre cuando el folio es muy corto.
                      child: Text(
                        s.folio.length >= 3
                            ? s.folio.substring(1, 3)
                            : avatarInitial(s.fullName),
                      ),
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
      floatingActionButton: KuraPrimaryFab(
        onPressed: () => _openStaffForm(),
        icon: Icons.person_add,
        label: 'Nuevo',
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
          roleTitle: _roleCtrl.text.trim().isEmpty ? 'Especialista' : _roleCtrl.text.trim(),
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
          roleTitle: _roleCtrl.text.trim().isEmpty ? 'Especialista' : _roleCtrl.text.trim(),
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

class SitesTab extends StatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  const SitesTab({required this.repo, required this.organizationId});

  @override
  State<SitesTab> createState() => _SitesTabState();
}

class _SitesTabState extends State<SitesTab> {
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
          ? const _EmptyState(
              icon: Icons.location_on_outlined,
              message: 'Aún no hay sitios registrados.\n'
                  'Usa el botón "Nuevo" para dar de alta el primero '
                  '(clínica, domicilio, hospital...).',
            )
          : ListView.separated(
              padding: EdgeInsets.fromLTRB(16, 16, 16, kuraListBottomInset(context)),
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
      floatingActionButton: KuraPrimaryFab(
        onPressed: canAddSite
            ? () => _openSiteForm()
            : () => _showAdminModuleUpsell(context),
        icon: canAddSite ? Icons.add_location_alt_outlined : Icons.lock_outline,
        label: 'Nuevo',
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
class NoteCatalogTab extends StatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  const NoteCatalogTab({required this.repo, required this.organizationId});

  @override
  State<NoteCatalogTab> createState() => _NoteCatalogTabState();
}

class _NoteCatalogTabState extends State<NoteCatalogTab> {
  NoteOptionField _selectedField = NoteOptionField.careType;
  String _search = '';

  /// Carga el catalogo base curado (mismo contenido que la precarga de
  /// 0010_note_option_catalog.sql) para este centro. Pensado sobre todo
  /// para un centro nuevo, recien creado desde Plataforma por el master,
  /// que arranca con las 4 secciones completamente vacias (createOrganization()
  /// deliberadamente NO siembra catalogo, ver DataRepository) -- este boton
  /// evita tener que dar de alta uno por uno los conceptos mas comunes.
  /// Es un merge, no un reemplazo: solo agrega lo que falte, nunca duplica
  /// ni pisa conceptos ya personalizados o desactivados por el admin.
  Future<void> _loadDefaultCatalog() async {
    final organizationId = widget.organizationId;
    if (organizationId == null) return;
    try {
      final summary = await widget.repo.seedDefaultNoteOptions(organizationId: organizationId);
      if (mounted) {
        setState(() {});
        final msg = summary.added > 0
            ? 'Se agregaron ${summary.added} conceptos base al catálogo.'
            : 'El catálogo base ya estaba cargado; no se agregó nada nuevo.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cargar el catálogo base: $e')),
        );
      }
    } finally {
      if (mounted) setState(() {});
    }
  }

  // Alternativa manual (preservada tal cual, sin rehacer): "Nuevo concepto"
  // sigue siendo la unica accion del FAB.
  Future<void> _addOption() async {
    final label = await _promptForLabel(context, title: 'Nuevo concepto');
    if (label == null || label.trim().isEmpty) return;
    try {
      await widget.repo.createNoteOption(
        field: _selectedField,
        label: label.trim(),
        organizationId: widget.organizationId,
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo agregar: $e')),
        );
      }
    }
  }

  /// Descarga la plantilla CSV (columnas seccion,concepto,activo) con el
  /// catalogo ACTUAL del centro (las 4 secciones), para que el admin la
  /// edite en Excel/Sheets y luego la vuelva a cargar.
  Future<void> _downloadTemplate() async {
    final rows = <List<String>>[
      ['seccion', 'concepto', 'activo'],
    ];
    for (final field in NoteOptionField.values) {
      for (final o in widget.repo.listAllNoteOptions(field, organizationId: widget.organizationId)) {
        rows.add([field.csvSeccion, o.label, o.isActive ? 'true' : 'false']);
      }
    }
    final csvContent = const ListToCsvConverter().convert(rows);
    try {
      await downloadCsv('catalogo_notas_seguimiento.csv', csvContent);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo descargar la plantilla: $e')),
        );
      }
    }
  }

  /// Carga un CSV (mismas columnas de la plantilla) y hace merge en bloque
  /// de las 4 secciones via DataRepository.bulkImportNoteOptions.
  Future<void> _uploadCsv() async {
    final organizationId = widget.organizationId;
    if (organizationId == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    try {
      final content = String.fromCharCodes(bytes);
      final rawRows = const CsvToListConverter(eol: '\n').convert(content);
      if (rawRows.isEmpty) {
        throw StateError('El archivo está vacío.');
      }
      // Se descarta el encabezado (fila 0); se acepta el orden
      // seccion,concepto,activo tal cual lo produce _downloadTemplate().
      final dataRows = rawRows.skip(1);
      final parsed = <NoteOptionImportRow>[];
      for (final r in dataRows) {
        if (r.isEmpty || r.every((c) => c.toString().trim().isEmpty)) continue;
        final seccion = r.isNotEmpty ? r[0].toString() : '';
        final concepto = r.length > 1 ? r[1].toString() : '';
        final activoRaw = r.length > 2 ? r[2].toString().trim().toLowerCase() : 'true';
        final activo = activoRaw == 'true' || activoRaw == '1' || activoRaw == 'si' || activoRaw == 'sí';
        parsed.add(NoteOptionImportRow(seccion: seccion, concepto: concepto, activo: activo));
      }

      final summary = await widget.repo.bulkImportNoteOptions(
        parsed,
        organizationId: organizationId,
      );

      if (mounted) {
        setState(() {});
        await showDialog<void>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('Resumen de importación'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Agregados: ${summary.added}'),
                Text('Actualizados: ${summary.updated}'),
                Text('Omitidos: ${summary.skipped}'),
                if (summary.errors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Detalle:', style: TextStyle(fontWeight: FontWeight.w600)),
                  ...summary.errors.take(10).map((e) => Text('• $e', style: const TextStyle(fontSize: 12))),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo importar el CSV: $e')),
        );
      }
    } finally {
      if (mounted) setState(() {});
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

  /// Cambia la etiqueta kura_tag de un concepto (dropdown "Sin etiqueta" +
  /// las 9 categorias del motor Protocolo Kura+, ver
  /// 0013_note_option_catalog_kura_tag.sql). Es el puente que permite, mas
  /// adelante, que el toggle premium de la nota de seguimiento pre-marque
  /// este concepto cuando su etiqueta coincida con el regimen sugerido.
  Future<void> _setKuraTag(NoteOptionCatalogItem item, KuraTag? tag) async {
    try {
      await widget.repo.setNoteOptionKuraTag(item.id, tag);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar la etiqueta: $e')),
        );
      }
    }
  }

  /// Borra un concepto del catalogo, previa confirmacion. Borrar solo
  /// quita el concepto de las opciones futuras (chips al capturar una
  /// nota); las notas de seguimiento ya guardadas conservan el texto
  /// del concepto tal cual, no una referencia a esta fila, asi que el
  /// historial no se ve afectado.
  //
  // IMPORTANTE (bug #8, pantalla en blanco): el dialogo de confirmacion
  // usa builder: (dialogCtx) => ... y Navigator.pop(dialogCtx, ...) -- el
  // context propio del dialogo, no el context externo de NoteCatalogTab.
  // La app usa ShellRoute (navegador anidado): reutilizar el context
  // externo en el pop cierra la ruta de fondo en vez del dialogo, dejando
  // la pantalla en blanco sin ninguna excepcion de Dart capturable.
  Future<void> _deleteOption(NoteOptionCatalogItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Borrar concepto'),
        content: const Text(
          '¿Borrar este concepto? No afecta las notas ya guardadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(backgroundColor: KuraColors.danger),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.repo.deleteNoteOption(item.id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo borrar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final adminLocked = !widget.repo.premiumAdminFor(widget.organizationId);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
        children: [
          Text(
            'Configuración del centro',
            style: TextStyle(
                fontSize: AppType.display,
                fontWeight: AppType.extrabold,
                letterSpacing: -0.02 * AppType.display,
                color: t.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Lo que tu equipo ve al capturar, los protocolos que sigue y la '
            'constancia de lo que sale del expediente.',
            style: TextStyle(fontSize: AppType.body, color: t.textSecondary),
          ),
          const SizedBox(height: 26),
          _grupo1(t, adminLocked),
          const SizedBox(height: 26),
          _grupo2(t, adminLocked),
          const SizedBox(height: 26),
          _grupo3(t),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Grupo 1 — Catálogo de la nota de seguimiento
  // -------------------------------------------------------------------------
  Widget _grupo1(BrandTokens t, bool adminLocked) {
    final all = widget.repo
        .listAllNoteOptions(_selectedField, organizationId: widget.organizationId);
    final q = _search.trim().toLowerCase();
    final options =
        q.isEmpty ? all : all.where((o) => o.label.toLowerCase().contains(q)).toList();
    final taggable = _selectedField.availableTags.isNotEmpty;

    return _groupCard(
      t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catálogo de la nota de seguimiento',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: AppType.bold,
                          letterSpacing: -0.01 * 19,
                          color: t.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Los conceptos que tu personal clínico ve como opciones al '
                      'registrar una nota. Se configura una vez para todo el centro.',
                      style: TextStyle(fontSize: 13, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              _primaryPill(t, 'Nuevo concepto', _addOption),
              const SizedBox(width: 10),
              _herramientasMenu(t, adminLocked),
            ],
          ),
          const SizedBox(height: 20),
          KuraActionBar(
            searchHint: 'Buscar concepto',
            onSearchChanged: (v) => setState(() => _search = v),
            filters: [
              for (final f in NoteOptionField.values)
                KuraFilter(
                  label: f.label,
                  count: widget.repo
                      .listAllNoteOptions(f, organizationId: widget.organizationId)
                      .length,
                  selected: f == _selectedField,
                  onTap: () => setState(() => _selectedField = f),
                ),
            ],
            showingText: 'Mostrando ${options.length} de ${all.length}',
          ),
          const SizedBox(height: 16),
          if (options.isEmpty)
            KuraEmptyState(
              icon: Icons.list_alt_outlined,
              title: q.isEmpty ? 'Sin conceptos en esta sección' : 'Sin coincidencias',
              message: q.isEmpty
                  ? 'Agrega el primer concepto de "${_selectedField.label}", o carga el catálogo base curado por Kura+.'
                  : 'Ningún concepto coincide con "$_search".',
              primaryLabel: 'Nuevo concepto',
              onPrimary: _addOption,
              secondaryLabel: q.isEmpty ? 'Cargar catálogo base' : null,
              onSecondary: q.isEmpty ? _loadDefaultCatalog : null,
            )
          else
            KuraDataTable(
              columns: [
                KuraColumn(
                    label: 'Concepto',
                    fraction: taggable ? 0.44 : 0.71,
                    sortable: true),
                if (taggable)
                  const KuraColumn(
                      label: 'Paso del Protocolo Kura+', fraction: 0.27),
                const KuraColumn(label: 'Estado', fraction: 0.15, sortable: true),
                const KuraColumn(label: 'Acciones', fraction: 0.14, numeric: true),
              ],
              rows: [
                for (final o in options)
                  KuraRow(
                    id: o.id,
                    cells: [
                      KuraCell.custom(
                        sortValue: o.label.toLowerCase(),
                        build: (t) => Text(
                          o.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: AppType.semibold,
                            color: o.isActive ? t.textPrimary : t.textDisabled,
                            decoration:
                                o.isActive ? null : TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                      if (taggable)
                        (o.kuraTag != null &&
                                _selectedField.availableTags.contains(o.kuraTag)
                            ? KuraCell.pill(o.kuraTag!.label)
                            : KuraCell.custom(
                                sortValue: '',
                                build: (t) => Text('Sin asignar',
                                    style: TextStyle(
                                        fontSize: 12, color: t.textDisabled)),
                              )),
                      KuraCell.custom(
                        sortValue: o.isActive ? 1 : 0,
                        build: (t) => Text(
                          o.isActive ? 'Activo' : 'Inactivo',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: AppType.bold,
                              color:
                                  o.isActive ? t.statusSuccess : t.textDisabled),
                        ),
                      ),
                      KuraCell.custom(
                        // FittedBox: en la columna angosta (14%) "Editar · Desactivar"
                        // se encoge en vez de desbordar.
                        build: (t) => Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _rowAction(t, 'Editar', () => _editDialog(o)),
                                Text(' · ',
                                    style: TextStyle(
                                        fontSize: 12, color: t.textDisabled)),
                                _rowAction(
                                    t,
                                    o.isActive ? 'Desactivar' : 'Activar',
                                    () => _toggleActive(o)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          const SizedBox(height: 10),
          _footnote(t),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Grupo 2 — Tu propio protocolo (el módulo pagado)
  // -------------------------------------------------------------------------
  Widget _grupo2(BrandTokens t, bool adminLocked) {
    return _groupCard(
      t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tu propio protocolo',
              style: TextStyle(
                  fontSize: 19, fontWeight: AppType.bold, color: t.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Escribe los pasos que sigue tu centro y qué producto usa en cada '
            'uno, en vez de usar el protocolo curado por Kura+.',
            style: TextStyle(fontSize: 13, color: t.textSecondary),
          ),
          const SizedBox(height: 20),
          // Banda de bloqueo: se pinta sola solo si el módulo NO está contratado.
          KuraModuleLock.band(
            repo: widget.repo,
            organizationId: widget.organizationId ?? '',
            moduleKey: 'admin',
            moduleName: 'Estas seis funciones son del módulo Administración avanzada',
            description:
                'Incluye además 3 usuarios administrativos, varias sedes y tu '
                'marca en los reportes. IVA incluido.',
          ),
          if (adminLocked) const SizedBox(height: 16),
          _reja(t, [
            _CfgTile(
              icon: Icons.auto_awesome,
              name: 'Protocolo Kura+',
              desc: 'Qué conceptos van en cada paso',
              locked: adminLocked,
              onOpen: () => context.go('/admin/protocolo-kura'),
            ),
            _CfgTile(
              icon: Icons.inventory_2_outlined,
              name: 'Productos del protocolo',
              desc: 'Qué insumo y cuánto, por paso',
              locked: adminLocked,
              onOpen: () => context.go('/admin/productos-protocolo'),
            ),
            _CfgTile(
              icon: Icons.upload_outlined,
              name: 'Cargar catálogo por CSV',
              desc: 'Sube tus conceptos en bloque',
              locked: adminLocked,
              onOpen: _uploadCsv,
            ),
            _CfgTile(
              icon: Icons.event_repeat_outlined,
              name: 'Tipo de cita para sesiones',
              desc: 'Integración con Acuity',
              locked: adminLocked,
              onOpen: () => context.go('/admin/tipo-cita-sesiones'),
            ),
            _CfgTile(
              icon: Icons.medical_information_outlined,
              name: 'Tipos de consulta',
              desc: 'Valoración o seguimiento, en Acuity',
              locked: adminLocked,
              onOpen: () => context.go('/admin/tipos-consulta'),
            ),
            _CfgTile(
              icon: Icons.cleaning_services_outlined,
              name: 'Depurar expedientes',
              desc: 'Archivar en bloque contra tu padrón',
              locked: adminLocked,
              onOpen: () => context.go('/admin/depurar-expedientes'),
            ),
          ]),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Grupo 3 — Expediente y cumplimiento (nunca se gatea)
  // -------------------------------------------------------------------------
  Widget _grupo3(BrandTokens t) {
    return _groupCard(
      t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Expediente y cumplimiento',
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: AppType.bold,
                            color: t.textPrimary)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Lo que la ley te exige poder hacer con tu expediente. Nunca '
                      'depende de un módulo ni de que el pago esté al día.',
                      style: TextStyle(fontSize: 13, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Tints.status(t.statusSuccess, t.surface, 0.12),
                  borderRadius: AppRadii.pillR,
                ),
                child: Text('Siempre incluido',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: AppType.bold,
                        color: t.statusSuccess)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _reja(t, [
            _CfgTile(
              icon: Icons.fact_check_outlined,
              name: 'Registro de divulgaciones',
              desc: 'Constancia de cada salida de datos',
              locked: false,
              onOpen: () => context.go('/admin/divulgaciones'),
            ),
            _CfgTile(
              icon: Icons.rule_folder_outlined,
              name: 'Escalas del protocolo',
              desc: 'Cuáles participan en tu centro',
              locked: false,
              onOpen: () => context.go('/admin/escalas-protocolo'),
            ),
            _CfgTile(
              icon: Icons.menu_book_outlined,
              name: 'Fuente de recomendaciones',
              desc: 'De dónde sale cada sugerencia',
              locked: false,
              onOpen: () => context.go('/admin/fuente-recomendaciones'),
            ),
            _CfgTile(
              icon: Icons.download_outlined,
              name: 'Descargar plantilla CSV',
              desc: 'Tu catálogo actual, en hoja',
              locked: false,
              onOpen: _downloadTemplate,
            ),
            _CfgTile(
              icon: Icons.playlist_add_check_outlined,
              name: 'Cargar catálogo base',
              desc: 'Los conceptos curados por Kura+',
              locked: false,
              onOpen: _loadDefaultCatalog,
            ),
            _CfgTile(
              icon: Icons.download_outlined,
              name: 'Exportar el expediente',
              desc: 'Completo, cuando lo necesites',
              locked: false,
              onOpen: () => context.go('/import-export'),
            ),
          ]),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Helpers de presentación
  // -------------------------------------------------------------------------
  Widget _groupCard(BrandTokens t, {required Widget child}) => Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: AppRadii.mdR,
          border: Border.all(color: t.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
        child: child,
      );

  Widget _primaryPill(BrandTokens t, String label, VoidCallback onTap) => Material(
        color: t.brandPrimary,
        borderRadius: AppRadii.pillR,
        child: InkWell(
          borderRadius: AppRadii.pillR,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: AppType.bold, color: t.onBrand)),
          ),
        ),
      );

  Widget _herramientasMenu(BrandTokens t, bool adminLocked) =>
      PopupMenuButton<int>(
        tooltip: 'Herramientas',
        onSelected: (i) {
          switch (i) {
            case 0:
              _loadDefaultCatalog();
            case 1:
              _downloadTemplate();
            case 2:
              adminLocked ? _openAdminSection() : _uploadCsv();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 0, child: Text('Cargar catálogo base')),
          const PopupMenuItem(value: 1, child: Text('Descargar plantilla CSV')),
          PopupMenuItem(
            value: 2,
            child: Row(
              children: [
                if (adminLocked) ...[
                  Icon(Icons.lock_outline, size: 16, color: t.textDisabled),
                  const SizedBox(width: 6),
                ],
                const Flexible(child: Text('Cargar CSV')),
              ],
            ),
          ),
        ],
        child: Container(
          decoration:
              BoxDecoration(color: t.chipBg, borderRadius: AppRadii.pillR),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Herramientas',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: AppType.bold,
                      color: t.brandPrimary)),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down, size: 13, color: t.brandPrimary),
            ],
          ),
        ),
      );

  Widget _rowAction(BrandTokens t, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: AppRadii.smR,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(label,
              style: TextStyle(fontSize: 12, color: t.textSecondary)),
        ),
      );

  Widget _footnote(BrandTokens t) => Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 11, height: 1.5, color: t.textDisabled),
          children: [
            const TextSpan(text: 'Desactivar oculta el concepto de las notas '
                'nuevas y '),
            TextSpan(
                text: 'no toca',
                style: TextStyle(
                    color: t.textSecondary, fontWeight: AppType.bold)),
            const TextSpan(
                text: ' las notas ya guardadas. El paso del protocolo es lo que '
                    'conecta cada concepto con las sugerencias de Kura+.'),
          ],
        ),
      );

  // Reja responsiva de 3 columnas (2 / 1 en anchos menores).
  Widget _reja(
    BrandTokens t,
    List<_CfgTile> tiles,
  ) =>
      LayoutBuilder(
        builder: (ctx, c) {
          final cols = c.maxWidth >= 720 ? 3 : (c.maxWidth >= 440 ? 2 : 1);
          const gap = 12.0;
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final tile in tiles)
                SizedBox(width: w, child: _tile(t, tile)),
            ],
          );
        },
      );

  Widget _tile(
    BrandTokens t,
    _CfgTile tile,
  ) {
    final locked = tile.locked;
    final inner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.chipBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(tile.icon,
                size: 18, color: locked ? t.textDisabled : t.brandPrimary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tile.name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: AppType.bold,
                        color: locked ? t.textSecondary : t.textPrimary)),
                const SizedBox(height: 2),
                Text(tile.desc,
                    style: TextStyle(
                        fontSize: 11, height: 1.45, color: t.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
    if (locked) {
      return InkWell(
        borderRadius: AppRadii.mdR,
        onTap: _openAdminSection,
        child: DashedBorderBox(
          color: t.border,
          radius: AppRadii.md,
          fill: Tints.brand(t, 0.02),
          child: inner,
        ),
      );
    }
    return Material(
      color: t.surface,
      borderRadius: AppRadii.mdR,
      child: InkWell(
        borderRadius: AppRadii.mdR,
        onTap: tile.onOpen,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppRadii.mdR,
            border: Border.all(color: t.border),
          ),
          child: inner,
        ),
      ),
    );
  }

  // Sección completa del módulo Administración (densidad c), en diálogo. La abre la
  // acción bloqueada y las tarjetas gateadas de la reja del grupo 2.
  void _openAdminSection() {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final t = BrandTokens.of(dialogCtx);
        return Dialog(
          backgroundColor: t.surface,
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.mdR),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: KuraModuleLock.section(
              repo: widget.repo,
              organizationId: widget.organizationId ?? '',
              moduleKey: 'admin',
              moduleName: 'Administración avanzada',
              description:
                  'Escribe los pasos que sigue tu centro y qué producto usa en '
                  'cada uno, en vez del protocolo curado por Kura+.',
            ),
          ),
        );
      },
    );
  }

  // "Editar" de una fila: la etiqueta del paso (si el campo la usa) y borrar.
  Future<void> _editDialog(NoteOptionCatalogItem item) async {
    final taggable = _selectedField.availableTags.isNotEmpty;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        var sel = _selectedField.availableTags.contains(item.kuraTag)
            ? item.kuraTag
            : null;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(item.label),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (taggable) ...[
                  const Text('Paso del Protocolo Kura+',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  DropdownButton<KuraTag?>(
                    value: sel,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<KuraTag?>(
                          value: null, child: Text('Sin asignar')),
                      ..._selectedField.availableTags.map(
                        (tg) => DropdownMenuItem<KuraTag?>(
                            value: tg, child: Text(tg.label)),
                      ),
                    ],
                    onChanged: (v) {
                      setLocal(() => sel = v);
                      _setKuraTag(item, v);
                    },
                  ),
                  const SizedBox(height: 8),
                ] else
                  const Text('Este campo no usa paso del protocolo.',
                      style: TextStyle(fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _deleteOption(item);
                },
                child: const Text('Borrar concepto'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Listo'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CfgTile {
  final IconData icon;
  final String name;
  final String desc;
  final bool locked;
  final VoidCallback onOpen;
  const _CfgTile({
    required this.icon,
    required this.name,
    required this.desc,
    required this.locked,
    required this.onOpen,
  });
}

Future<String?> _promptForLabel(BuildContext context, {required String title}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Texto del concepto'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogCtx, ctrl.text),
          style: FilledButton.styleFrom(backgroundColor: KuraColors.primary),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}

/// Configuración de marca del centro para los reportes PDF: color principal +
/// logo. Se usa en Administración (admin) y Plataforma (master, por centro).
class BrandingTab extends StatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  const BrandingTab({super.key, required this.repo, required this.organizationId});

  @override
  State<BrandingTab> createState() => _BrandingTabState();
}

class _BrandingTabState extends State<BrandingTab> {
  final _colorCtrl = TextEditingController(text: '#7C3AED');
  Uint8List? _logoBytes;
  String? _logoName;
  String? _existingLogoPath;
  bool _loaded = false;
  bool _saving = false;
  final _picker = ImagePicker();

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
    final color = _parse(_colorCtrl.text) ?? KuraColors.primary;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, kuraListBottomInset(context)),
      children: [
        const Text('Marca del centro para reportes',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 4),
        Text('El logo y el color aparecen en los reportes PDF que se entregan al paciente.',
            style: TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.6))),
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
          style: FilledButton.styleFrom(backgroundColor: KuraColors.primary),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Guardando…' : 'Guardar branding'),
        ),
      ],
    );
  }

  Widget _logoPreview() {
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
        style: TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.5)));
  }

  Widget _headerPreview(Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 4)),
        color: color.withOpacity(0.06),
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
