import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/layout/responsive.dart';
import '../../core/providers/session_provider.dart';
import '../../core/utils/caregiver_login.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../core/widgets/kura_primary_fab.dart';
import '../../models/app_user.dart';
import '../../models/note_option_catalog.dart';
import '../../models/site.dart';
import '../../models/staff.dart';
import '../../services/csv_download.dart';
import '../../services/data_repository.dart';
import '../../services/photo_upload_service.dart';

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
  late final TabController _tabController = TabController(length: 5, vsync: this)
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
    // organizationId del admin en sesion: se pasa explicitamente a cada tab
    // para que las altas (staff/sitio/concepto de catalogo) queden
    // correctamente acotadas al centro del admin (columnas not null en
    // Supabase, ver 0011_organizations.sql), en vez de derivarlo de forma
    // implicita dentro de cada dialogo.
    final organizationId = ref.watch(sessionProvider).user?.organizationId;
    // Id del usuario en sesion: la pestana de Usuarios lo usa para impedir que
    // el admin se cambie el rol o se desactive a si mismo (auto-bloqueo).
    final currentUserId = ref.watch(sessionProvider).user?.id;
    // Desktop: secciones como rail lateral (maestro) + contenido (detalle);
    // móvil conserva el TabBar horizontal.
    final wide = MediaQuery.of(context).size.width >= Breakpoints.twoPane;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
        actions: const [UserMenuButton()],
        bottom: wide
            ? null
            : TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Usuarios'),
                  Tab(text: 'Personal sanitario'),
                  Tab(text: 'Sitios'),
                  Tab(text: 'Configuración'),
                  Tab(text: 'Marca'),
                ],
                onTap: (i) => setState(() => _tab = i),
              ),
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final Widget tab = switch (_tab) {
            1 => StaffTab(repo: repo, organizationId: organizationId),
            2 => SitesTab(repo: repo, organizationId: organizationId),
            3 => NoteCatalogTab(repo: repo, organizationId: organizationId),
            4 => BrandingTab(repo: repo, organizationId: organizationId),
            _ => UsersTab(
                repo: repo,
                organizationId: organizationId,
                currentUserId: currentUserId,
              ),
          };
          // Móvil: contenido acotado; desktop: rail de secciones + contenido.
          if (!wide) return PageMaxWidth(maxWidth: 1100, child: tab);
          return Row(
            children: [
              SectionRail(
                selectedIndex: _tab,
                onSelected: (i) => setState(() {
                  _tab = i;
                  _tabController.index = i;
                }),
                destinations: const [
                  (Icons.people_outline, 'Usuarios'),
                  (Icons.medical_services_outlined, 'Personal'),
                  (Icons.location_on_outlined, 'Sitios'),
                  (Icons.settings_outlined, 'Config.'),
                  (Icons.palette_outlined, 'Marca'),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: tab),
            ],
          );
        },
      ),
    );
  }
}

/// Pestaña de gestión de usuarios y roles. Se reutiliza en dos contextos:
///   - Panel de Administración (admin de centro): organizationId = su centro.
///   - Área de Plataforma (master): organizationId = centro elegido en el
///     selector (por eso ve/gestiona usuarios de cualquier centro, uno a la vez).
/// Permite crear usuarios CON login (via Edge Function admin-create-user),
/// cambiar su rol (admin <-> personal sanitario) y activar/desactivar. El
/// usuario en sesión ([currentUserId]) no puede cambiarse el rol ni
/// desactivarse a sí mismo, para evitar dejarse fuera del sistema.
class UsersTab extends StatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  final String? currentUserId;
  const UsersTab({
    super.key,
    required this.repo,
    required this.organizationId,
    required this.currentUserId,
  });

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  Future<void> _openCreateForm() async {
    final orgId = widget.organizationId;
    if (orgId == null) return;
    final created = await showDialog<CreatedUser>(
      context: context,
      builder: (_) => _UserFormDialog(repo: widget.repo, organizationId: orgId),
    );
    if (created == null || !mounted) return;
    setState(() {});
    await _showCredentials(created);
  }

  /// Muestra el correo y la contraseña temporal para que el admin la
  /// comparta con la persona (necesario mientras no haya SMTP configurado).
  Future<void> _showCredentials(CreatedUser user) async {
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Usuario creado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Se creó la cuenta de ${user.email} (${user.role.label}).'),
            const SizedBox(height: 12),
            if (user.tempPassword != null) ...[
              const Text(
                'Contraseña temporal (compártela con la persona; podrá '
                'cambiarla más adelante):',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: KuraColors.chipBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        user.tempPassword!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Copiar',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: user.tempPassword!));
                        ScaffoldMessenger.of(dialogCtx).showSnackBar(
                          const SnackBar(content: Text('Contraseña copiada')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ] else
              const Text(
                'Cuenta de demostración (este entorno no tiene login real).',
                style: TextStyle(fontSize: 12),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeRole(AppUser u, AppRole newRole) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Cambiar rol'),
        content: Text('¿Cambiar a ${u.fullName} a "${newRole.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(backgroundColor: KuraColors.primary),
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repo.setUserRole(u.id, newRole);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cambiar el rol: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = widget.repo
        .listUsers()
        .where((u) =>
            widget.organizationId == null || u.organizationId == widget.organizationId)
        .toList();
    return Scaffold(
      body: users.isEmpty
          ? const _EmptyState(
              icon: Icons.people_outline,
              message: 'Aún no hay usuarios en este centro.\n'
                  'Usa el botón "Nuevo usuario" para dar de alta al primero.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final u = users[i];
                final isSelf = u.id == widget.currentUserId;
                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: KuraColors.primary.withOpacity(0.12),
                      child: Icon(
                        u.role == AppRole.admin
                            ? Icons.admin_panel_settings
                            : Icons.medical_services,
                        color: KuraColors.primary,
                      ),
                    ),
                    title: Text('${u.fullName}${isSelf ? ' (tú)' : ''}'),
                    subtitle: Text('${u.email} · ${u.role.label}'
                        '${u.staffId == null ? '' : ' · vinculado a personal sanitario'}'),
                    trailing: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Column(
                          children: [
                            const Text('Activo', style: TextStyle(fontSize: 10)),
                            Switch(
                              value: u.isActive,
                              activeColor: KuraColors.primary,
                              onChanged: isSelf
                                  ? null
                                  : (v) async {
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
                        // Cambio de rol: oculto para uno mismo (evita
                        // auto-bloqueo) y para perfiles master (no se degradan
                        // desde esta pantalla).
                        if (!isSelf && u.role != AppRole.master)
                          PopupMenuButton<AppRole>(
                            tooltip: 'Cambiar rol',
                            icon: const Icon(Icons.manage_accounts_outlined),
                            onSelected: (r) => _changeRole(u, r),
                            itemBuilder: (_) => [
                              if (u.role != AppRole.admin)
                                const PopupMenuItem(
                                  value: AppRole.admin,
                                  child: Text('Hacer administrador'),
                                ),
                              if (u.role != AppRole.clinico)
                                const PopupMenuItem(
                                  value: AppRole.clinico,
                                  child: Text('Hacer personal sanitario'),
                                ),
                              if (u.role != AppRole.enfermeria)
                                const PopupMenuItem(
                                  value: AppRole.enfermeria,
                                  child: Text('Hacer enfermería'),
                                ),
                              if (u.role != AppRole.cuidador)
                                const PopupMenuItem(
                                  value: AppRole.cuidador,
                                  child: Text('Hacer cuidador'),
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
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Nuevo usuario'),
        onPressed: widget.organizationId == null ? null : _openCreateForm,
      ),
    );
  }
}

/// Formulario de alta de usuario con login. Devuelve el [CreatedUser] via
/// Navigator.pop para que la pestaña muestre la contraseña temporal.
class _UserFormDialog extends StatefulWidget {
  final DataRepository repo;
  final String organizationId;
  const _UserFormDialog({required this.repo, required this.organizationId});

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cedulaCtrl = TextEditingController();
  final _claveCtrl = TextEditingController();
  AppRole _role = AppRole.clinico;
  String? _siteId;
  bool _saving = false;
  String? _error;

  bool get _isCaregiver => _role == AppRole.cuidador;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _cedulaCtrl.dispose();
    _claveCtrl.dispose();
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
      final phone = _phoneCtrl.text.trim();
      // Cuidador: login por teléfono + clave. El identificador real es un correo
      // SINTÉTICO derivado del teléfono (mismo cálculo que en el login).
      final email = _isCaregiver
          ? CaregiverLogin.syntheticEmail(phone)
          : _emailCtrl.text.trim();
      if (_isCaregiver && email == null) {
        setState(() {
          _error = 'Teléfono inválido (mínimo 8 dígitos).';
          _saving = false;
        });
        return;
      }
      final created = await widget.repo.createUserWithLogin(
        email: email!,
        fullName: _nameCtrl.text.trim(),
        role: _role,
        organizationId: widget.organizationId,
        phone: phone.isEmpty ? null : phone,
        cedulaProfesional: cedula.isEmpty ? null : cedula,
        primarySiteId: _role == AppRole.clinico ? _siteId : null,
        password: _isCaregiver ? _claveCtrl.text : null,
      );
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sites = widget.repo.listSites(organizationId: widget.organizationId);
    return AlertDialog(
      title: const Text('Nuevo usuario'),
      content: SizedBox(
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
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AppRole>(
                  value: _role,
                  decoration: const InputDecoration(labelText: 'Rol'),
                  items: const [
                    DropdownMenuItem(
                      value: AppRole.clinico,
                      child: Text('Personal sanitario'),
                    ),
                    DropdownMenuItem(
                      value: AppRole.admin,
                      child: Text('Administrador'),
                    ),
                    DropdownMenuItem(
                      value: AppRole.enfermeria,
                      child: Text('Enfermería'),
                    ),
                    DropdownMenuItem(
                      value: AppRole.cuidador,
                      child: Text('Cuidador'),
                    ),
                  ],
                  onChanged: (r) => setState(() => _role = r ?? AppRole.clinico),
                ),
                const SizedBox(height: 12),
                // Cuidador: entra con TELÉFONO + CLAVE (sin correo). El resto,
                // con correo.
                if (_isCaregiver) ...[
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono (para iniciar sesión)',
                      hintText: 'El cuidador entra con este teléfono',
                    ),
                    validator: (v) {
                      if (!_isCaregiver) return null;
                      if (CaregiverLogin.syntheticEmail((v ?? '').trim()) == null) {
                        return 'Teléfono inválido (mínimo 8 dígitos)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _claveCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Clave para el cuidador',
                      hintText: 'Compártela con el cuidador (mín. 6 caracteres)',
                    ),
                    validator: (v) {
                      if (!_isCaregiver) return null;
                      if ((v ?? '').length < CaregiverLogin.minClaveLength) {
                        return 'Mínimo ${CaregiverLogin.minClaveLength} caracteres';
                      }
                      return null;
                    },
                  ),
                ] else ...[
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo (para iniciar sesión)',
                    ),
                    validator: (v) {
                      if (_isCaregiver) return null;
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Requerido';
                      if (!t.contains('@') || !t.contains('.')) {
                        return 'Correo inválido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration:
                        const InputDecoration(labelText: 'Teléfono (opcional)'),
                  ),
                ],
                if (_role == AppRole.clinico) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cedulaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Cédula profesional (opcional)',
                      hintText: 'Requerida para firmar notas de seguimiento',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    value: _siteId,
                    decoration: const InputDecoration(labelText: 'Sitio principal'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Sin asignar'),
                      ),
                      ...sites.map(
                        (s) => DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                      ),
                    ],
                    onChanged: (v) => setState(() => _siteId = v),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Se creará una cuenta de acceso. Si el correo (SMTP) no está '
                  'configurado en el servidor, se generará una contraseña '
                  'temporal para compartir con la persona.',
                  style: TextStyle(fontSize: 11, color: KuraColors.darkText.withOpacity(0.5)),
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
          onPressed: _saving ? null : () => Navigator.pop(context),
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
              : const Text('Crear usuario'),
        ),
      ],
    );
  }
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
                            : s.fullName.trim().isEmpty
                                ? '?'
                                : s.fullName.trim().substring(0, 1).toUpperCase(),
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
      TextEditingController(text: widget.existing?.roleTitle ?? 'Kurador');
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
          roleTitle: _roleCtrl.text.trim().isEmpty ? 'Kurador' : _roleCtrl.text.trim(),
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
          roleTitle: _roleCtrl.text.trim().isEmpty ? 'Kurador' : _roleCtrl.text.trim(),
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
      floatingActionButton: KuraPrimaryFab(
        onPressed: () => _openSiteForm(),
        icon: Icons.add_location_alt_outlined,
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
  bool _importing = false;
  bool _loadingDefaults = false;

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
    setState(() => _loadingDefaults = true);
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
      if (mounted) setState(() => _loadingDefaults = false);
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

    setState(() => _importing = true);
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
      if (mounted) setState(() => _importing = false);
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
    final options = widget.repo.listAllNoteOptions(_selectedField, organizationId: widget.organizationId);
    return Scaffold(
      // ListView (no Column): toda la pantalla desplaza como una sola lista.
      // En movil el encabezado fijo era mas alto que el body disponible (dos
      // AppBar apiladas + TabBar + NavigationBar), asi que desbordaba: los
      // ChoiceChip de seccion quedaban recortados ("menus no navegables") y la
      // lista se quedaba con ~0px ("el slider/Switch no funciona").
      body: ListView(
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
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _loadingDefaults ? null : _loadDefaultCatalog,
                      icon: _loadingDefaults
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.playlist_add_check_outlined, size: 18),
                      label: Text(_loadingDefaults ? 'Cargando…' : 'Cargar catálogo base'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _downloadTemplate,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Descargar plantilla CSV'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _importing ? null : _uploadCsv,
                      icon: _importing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_outlined, size: 18),
                      label: Text(_importing ? 'Importando…' : 'Cargar CSV'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '"Cargar catálogo base" agrega, en las 4 secciones, los '
                  'conceptos más comunes (curados por Kura+) que aún no '
                  'existan en este centro -- útil para arrancar rápido un '
                  'centro nuevo sin configurar todo desde cero; no duplica '
                  'ni pisa lo que ya tengas. La plantilla CSV incluye las 4 '
                  'secciones (tipo de atención, descripción, material, '
                  'evolución) con el catálogo actual del centro; al cargarla '
                  'se agregan conceptos nuevos y se actualiza el estado '
                  'activo/inactivo de los existentes. También puedes seguir '
                  'agregando uno por uno abajo.',
                  style: TextStyle(fontSize: 11, color: KuraColors.darkText.withOpacity(0.5)),
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
          options.isEmpty
                ? const _EmptyState(
                    icon: Icons.list_alt_outlined,
                    message: 'Sin conceptos configurados aún para este campo.',
                  )
                : ListView.separated(
                    // shrinkWrap + NeverScrollable: esta lista NO scrollea sola;
                    // el scroll lo lleva el ListView externo (toda la pantalla).
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final o = options[i];
                      return Card(
                        color: o.isActive ? null : KuraColors.chipBg,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Text(
                                        o.label,
                                        style: TextStyle(
                                          decoration: o.isActive ? null : TextDecoration.lineThrough,
                                          color: o.isActive
                                              ? null
                                              : KuraColors.darkText.withOpacity(0.5),
                                        ),
                                      ),
                                    ),
                                    // Etiqueta kura_tag (puente hacia el motor Protocolo
                                    // Kura+): opcional, "Sin etiqueta" permitido y por
                                    // defecto -- ver 0013_note_option_catalog_kura_tag.sql.
                                    DropdownButton<KuraTag?>(
                                      value: o.kuraTag,
                                      isDense: true,
                                      underline: const SizedBox.shrink(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: KuraColors.darkText.withOpacity(0.7),
                                      ),
                                      items: [
                                        const DropdownMenuItem<KuraTag?>(
                                          value: null,
                                          child: Text('Sin etiqueta'),
                                        ),
                                        ...KuraTag.values.map(
                                          (t) => DropdownMenuItem<KuraTag?>(
                                            value: t,
                                            child: Text(t.label),
                                          ),
                                        ),
                                      ],
                                      onChanged: (t) => _setKuraTag(o, t),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: KuraColors.danger,
                                ),
                                tooltip: 'Borrar concepto',
                                onPressed: () => _deleteOption(o),
                              ),
                              Switch(
                                value: o.isActive,
                                activeColor: KuraColors.primary,
                                onChanged: (_) => _toggleActive(o),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
        ],
      ),
      floatingActionButton: KuraPrimaryFab(
        onPressed: _addOption,
        icon: Icons.add,
        label: 'Nuevo concepto',
      ),
    );
  }
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
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
