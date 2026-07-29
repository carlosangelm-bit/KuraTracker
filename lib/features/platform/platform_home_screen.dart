import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/layout/responsive.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton, centerTypeColor;
import '../../core/widgets/kura_primary_fab.dart';
import '../../models/app_user.dart';
import '../../models/center_type.dart';
import '../../models/module_key.dart';
import '../../models/organization.dart';
import '../../models/site.dart';
import '../../models/user_center_membership.dart';
import '../../services/data_repository.dart';
import '../admin/admin_home_screen.dart'
    show UsersTab, StaffTab, SitesTab, NoteCatalogTab, BrandingTab;

/// Area de "Plataforma": pantalla exclusiva del rol `master`
/// (administrador de plataforma, ver 0012_master_role.sql). A diferencia
/// de [AdminHomeScreen] (acotado siempre a la organizacion del admin en
/// sesion), aqui el master primero elige un centro en el selector y
/// TODAS las pestanas de gestion (Personal/Sitios/Catalogo) quedan
/// parametrizadas por ese centro elegido -- son los MISMOS widgets
/// [StaffTab]/[SitesTab]/[NoteCatalogTab] que usa el panel de
/// Administracion de un admin normal, reutilizados aqui sin duplicar
/// CRUD, solo con un `organizationId` distinto en cada caso.
///
/// Regla de oro: esta pantalla y sus tabs SOLO tocan estructura
/// (organizations/sites/staff/note_option_catalog). Ningun dato clinico
/// de paciente es accesible desde aqui ni desde el DataRepository que
/// consume (listAllPatients/etc. no se llaman en ningun punto de este
/// archivo).
class PlatformHomeScreen extends ConsumerStatefulWidget {
  const PlatformHomeScreen({super.key});

  @override
  ConsumerState<PlatformHomeScreen> createState() => _PlatformHomeScreenState();
}

class _PlatformHomeScreenState extends ConsumerState<PlatformHomeScreen>
    with SingleTickerProviderStateMixin {
  int _tab = 0;
  // Mismo patron de TabController explicito que AdminHomeScreen (ver
  // comentario extenso alli sobre por que NO se usa
  // DefaultTabController: TabBar en AppBar.bottom queda como hermano,
  // no ancestro/descendiente, de un DefaultTabController que solo
  // envuelve el body).
  late final TabController _tabController = TabController(length: 7, vsync: this)
    ..addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index != _tab) {
        setState(() => _tab = _tabController.index);
      }
    });

  // Organizacion (centro) actualmente seleccionada en el selector. Vive
  // en el estado de esta pantalla (no en DataRepository ni en la
  // sesion): es una eleccion de navegacion efimera del master, no un
  // dato persistente ni parte de su perfil.
  String? _selectedOrgId;

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openCreateOrganizationDialog(DataRepository repo) async {
    final createdId = await showDialog<String>(
      context: context,
      // builder: (dialogCtx) => ... / Navigator.pop(dialogCtx, ...): el
      // context propio del dialogo, nunca el externo de esta pantalla
      // (ver bug "pantalla en blanco" ya corregido en admin_home_screen
      // / ShellRoute anidado -- misma convencion aplicada aqui).
      builder: (dialogCtx) => _OrganizationFormDialog(repo: repo),
    );
    if (createdId != null && mounted) {
      setState(() => _selectedOrgId = createdId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);

    // Desktop: secciones como rail lateral (maestro) + contenido (detalle);
    // móvil conserva el TabBar horizontal.
    final wide = MediaQuery.of(context).size.width >= Breakpoints.twoPane;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plataforma'),
        actions: const [UserMenuButton()],
        bottom: wide
            ? null
            : TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'Organizaciones'),
                  Tab(text: 'Usuarios'),
                  Tab(text: 'Personal sanitario'),
                  Tab(text: 'Sitios'),
                  Tab(text: 'Catálogo'),
                  Tab(text: 'Marca'),
                  Tab(text: 'Módulos'),
                ],
                onTap: (i) => setState(() => _tab = i),
              ),
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final organizations = repo.listOrganizations();
          // Si la organizacion previamente seleccionada ya no existe
          // (p.ej. se elimino), o aun no hay ninguna seleccionada pero
          // ya hay organizaciones creadas, se cae al primer centro de
          // la lista para que las pestanas de gestion no queden vacias
          // sin explicacion.
          if (_selectedOrgId != null &&
              organizations.every((o) => o.id != _selectedOrgId)) {
            _selectedOrgId = null;
          }
          if (_selectedOrgId == null && organizations.isNotEmpty) {
            _selectedOrgId = organizations.first.id;
          }

          // Acota el ancho en desktop para que la gestión no se estire.
          final Widget body;
          if (_tab == 0) {
            body = _OrganizationsTab(
              repo: repo,
              organizations: organizations,
              selectedOrgId: _selectedOrgId,
              onSelect: (id) => setState(() => _selectedOrgId = id),
              onCreate: () => _openCreateOrganizationDialog(repo),
              onChanged: () => setState(() {}),
            );
          } else if (organizations.isEmpty) {
            body = const _NoOrganizationsState();
          } else {
            body = Column(
              children: [
                _OrganizationSelectorBar(
                  organizations: organizations,
                  selectedOrgId: _selectedOrgId,
                  onChanged: (id) => setState(() => _selectedOrgId = id),
                ),
                const Divider(height: 1),
                Expanded(
                  child: switch (_tab) {
                    1 => UsersTab(
                        repo: repo,
                        organizationId: _selectedOrgId,
                        currentUserId: ref.watch(sessionProvider).user?.id,
                      ),
                    2 => StaffTab(repo: repo, organizationId: _selectedOrgId),
                    3 => SitesTab(repo: repo, organizationId: _selectedOrgId),
                    4 => NoteCatalogTab(repo: repo, organizationId: _selectedOrgId),
                    5 => BrandingTab(repo: repo, organizationId: _selectedOrgId),
                    _ => _ModulesTab(
                        repo: repo,
                        organizationId: _selectedOrgId,
                        updatedBy: ref.watch(sessionProvider).user?.id,
                      ),
                  },
                ),
              ],
            );
          }
          if (!wide) return PageMaxWidth(maxWidth: 1100, child: body);
          return Row(
            children: [
              SectionRail(
                selectedIndex: _tab,
                onSelected: (i) => setState(() {
                  _tab = i;
                  _tabController.index = i;
                }),
                destinations: const [
                  (Icons.business_outlined, 'Centros'),
                  (Icons.people_outline, 'Usuarios'),
                  (Icons.medical_services_outlined, 'Personal'),
                  (Icons.location_on_outlined, 'Sitios'),
                  (Icons.list_alt_outlined, 'Catálogo'),
                  (Icons.palette_outlined, 'Marca'),
                  (Icons.tune_outlined, 'Módulos'),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          );
        },
      ),
    );
  }
}

/// Barra fija (no scrollable) con el selector de centro, mostrada arriba
/// de Personal/Sitios/Catálogo cuando el rol es master. Un admin normal
/// nunca ve esta barra (AdminHomeScreen no la usa).
class _OrganizationSelectorBar extends StatelessWidget {
  final List<Organization> organizations;
  final String? selectedOrgId;
  final ValueChanged<String?> onChanged;

  const _OrganizationSelectorBar({
    required this.organizations,
    required this.selectedOrgId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: KuraColors.primary.withOpacity(0.05),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.hub_outlined, size: 18, color: KuraColors.primary),
          const SizedBox(width: 8),
          const Text('Centro:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: selectedOrgId,
                items: organizations
                    .map((o) => DropdownMenuItem<String>(
                          value: o.id,
                          child: Text(
                            o.isActive ? o.name : '${o.name} (inactivo)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoOrganizationsState extends StatelessWidget {
  const _NoOrganizationsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hub_outlined, size: 48, color: KuraColors.darkText.withOpacity(0.25)),
            const SizedBox(height: 12),
            Text(
              'Aún no hay ninguna organización (centro) creada.\n'
              'Ve a la pestaña "Organizaciones" para crear la primera.',
              textAlign: TextAlign.center,
              style: TextStyle(color: KuraColors.darkText.withOpacity(0.5)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pestaña "Organizaciones": lista TODOS los centros (ve todas las
/// organizaciones porque la policy RLS `organizations_select_own` de
/// 0012_master_role.sql agrega `or is_master()`) y permite crear uno
/// nuevo. Tocar una fila la selecciona como centro activo para las
/// demas pestanas.
class _OrganizationsTab extends StatelessWidget {
  final DataRepository repo;
  final List<Organization> organizations;
  final String? selectedOrgId;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreate;
  final VoidCallback onChanged;

  const _OrganizationsTab({
    required this.repo,
    required this.organizations,
    required this.selectedOrgId,
    required this.onSelect,
    required this.onCreate,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: organizations.isEmpty
          ? const _NoOrganizationsState()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: organizations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final o = organizations[i];
                final isSelected = o.id == selectedOrgId;
                return Card(
                  color: isSelected ? KuraColors.primary.withOpacity(0.08) : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: centerTypeColor(o.centerType).withOpacity(0.12),
                          child: Icon(Icons.hub_outlined, color: centerTypeColor(o.centerType)),
                        ),
                        title: Text(o.name),
                        subtitle: Text(o.isActive ? 'Activo' : 'Inactivo'),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Activo', style: TextStyle(fontSize: 10)),
                            Switch(
                              value: o.isActive,
                              activeColor: KuraColors.primary,
                              onChanged: (v) async {
                                await repo.setOrganizationActive(o.id, v);
                                onChanged();
                              },
                            ),
                          ],
                        ),
                        onTap: () => onSelect(o.id),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                        child: Row(
                          children: [
                            const Text('Tipo:', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 8),
                            DropdownButton<CenterType>(
                              value: o.centerType,
                              items: CenterType.values
                                  .map((t) => DropdownMenuItem(
                                        value: t,
                                        child: Text(t.label,
                                            style: const TextStyle(fontSize: 13)),
                                      ))
                                  .toList(),
                              onChanged: (t) async {
                                if (t == null) return;
                                await repo.setCenterType(o.id, t);
                                onChanged();
                              },
                            ),
                            const Spacer(),
                            TextButton.icon(
                              icon: const Icon(Icons.group_add_outlined, size: 18),
                              label: const Text('Miembros'),
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (dialogCtx) =>
                                    _MembershipsDialog(repo: repo, org: o),
                              ).then((_) => onChanged()),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: KuraPrimaryFab(
        onPressed: onCreate,
        icon: Icons.add_business_outlined,
        label: 'Nuevo centro',
      ),
    );
  }
}

/// Pestaña "Módulos": el master enciende/apaga módulos por centro, sitio o
/// usuario. Sin override => hereda el default del tipo de centro (0040/0041).
/// Los defaults por tipo son solo sugerencia: se puede, p.ej., encender
/// Prevención en una clínica de heridas. Apagar solo oculta (datos intactos).
class _ModulesTab extends StatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  final String? updatedBy;
  const _ModulesTab({required this.repo, required this.organizationId, this.updatedBy});

  @override
  State<_ModulesTab> createState() => _ModulesTabState();
}

enum _ModuleScope { centro, sitio, usuario }

class _ModulesTabState extends State<_ModulesTab> {
  _ModuleScope _scope = _ModuleScope.centro;
  String? _siteId;
  String? _profileId;
  bool _busy = false;

  Organization? get _org => widget.repo.organizationById(widget.organizationId);

  @override
  Widget build(BuildContext context) {
    final orgId = widget.organizationId;
    if (orgId == null || _org == null) {
      return const Center(child: Text('Selecciona un centro.'));
    }
    final org = _org!;
    final sites = widget.repo.listSites(organizationId: orgId).where((s) => s.isActive).toList();
    final users =
        widget.repo.listUsers().where((u) => u.organizationId == orgId && u.role != AppRole.master).toList();

    // Contexto del override según el alcance elegido.
    final scopeSiteId = _scope == _ModuleScope.sitio ? _siteId : null;
    final scopeProfileId = _scope == _ModuleScope.usuario ? _profileId : null;
    final scopeSelected = _scope == _ModuleScope.centro ||
        (_scope == _ModuleScope.sitio && scopeSiteId != null) ||
        (_scope == _ModuleScope.usuario && scopeProfileId != null);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      children: [
        Text('Módulos de ${org.name}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text('Tipo: ${org.centerType.label}. Sin ajuste = hereda el valor por tipo.',
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 12),
        // Módulos premium (add-ons de la licencia del centro): funciones de pago
        // que se añaden por centro, independientes entre sí. Protocolo Kura+
        // (0049) e Insumos (0047).
        Card(
          child: Column(
            children: [
              const ListTile(
                dense: true,
                leading: Icon(Icons.workspace_premium_outlined),
                title: Text('Módulos premium (add-ons)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    'Funciones premium que se añaden a la licencia de este centro.'),
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Protocolo Kura+'),
                subtitle: const Text(
                    'Sugerencia de tratamiento del motor para todo el centro '
                    '(además de la activación por usuario).'),
                value: org.premiumProtocoloKura,
                onChanged: _busy
                    ? null
                    : (v) async {
                        setState(() => _busy = true);
                        try {
                          await widget.repo
                              .setOrgPremiumProtocoloKura(org.id, v);
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
              ),
              SwitchListTile(
                title: const Text('Insumos'),
                subtitle: const Text(
                    'Mapeo insumo↔producto, inventario, costeo y reabasto '
                    '(la tienda base no requiere premium).'),
                value: org.premiumInsumos,
                onChanged: _busy
                    ? null
                    : (v) async {
                        setState(() => _busy = true);
                        try {
                          await widget.repo.setOrgPremiumInsumos(org.id, v);
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Guardia VAC: número de WhatsApp al que escalan las alarmas del módulo
        // de Terapia VAC. Se muestra solo si el módulo está activo en el centro.
        if (widget.repo.isModuleEnabled(ModuleKey.vac, organizationId: orgId)) ...[
          _VacGuardiaCard(
            repo: widget.repo,
            orgId: orgId,
            initial: widget.repo.vacOncallPhone(orgId) ?? '',
          ),
          const SizedBox(height: 12),
        ],
        SegmentedButton<_ModuleScope>(
          segments: const [
            ButtonSegment(value: _ModuleScope.centro, label: Text('Centro')),
            ButtonSegment(value: _ModuleScope.sitio, label: Text('Sitio')),
            ButtonSegment(value: _ModuleScope.usuario, label: Text('Usuario')),
          ],
          selected: {_scope},
          onSelectionChanged: (s) => setState(() => _scope = s.first),
        ),
        const SizedBox(height: 12),
        if (_scope == _ModuleScope.sitio)
          DropdownButtonFormField<String>(
            value: _siteId,
            decoration: const InputDecoration(labelText: 'Sitio'),
            items: sites
                .map((Site s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                .toList(),
            onChanged: (v) => setState(() => _siteId = v),
          ),
        if (_scope == _ModuleScope.usuario)
          DropdownButtonFormField<String>(
            value: _profileId,
            decoration: const InputDecoration(labelText: 'Usuario'),
            items: users
                .map((u) => DropdownMenuItem(value: u.id, child: Text(u.fullName)))
                .toList(),
            onChanged: (v) => setState(() => _profileId = v),
          ),
        const SizedBox(height: 12),
        if (!scopeSelected)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Elige un sitio o usuario para configurar.')),
          )
        else
          // Solo módulos que aplican al tipo de centro (p.ej. eKare no en
          // hospital); los no disponibles ni se ofrecen para configurar.
          ...ModuleKey.values
              .where((m) => _org == null || m.availableFor(_org!.centerType))
              .map((m) => _moduleRow(
                    m,
                    orgId: orgId,
                    siteId: scopeSiteId,
                    profileId: scopeProfileId,
                  )),
      ],
    );
  }

  Widget _moduleRow(ModuleKey m,
      {required String orgId, String? siteId, String? profileId}) {
    // Override actual EXACTO en este alcance (si existe).
    final settings = widget.repo.listModuleSettings(organizationId: orgId).where((s) =>
        s.moduleKey == m.dbValue && s.siteId == siteId && s.profileId == profileId);
    final override = settings.isEmpty ? null : settings.first.enabled;

    // Valor heredado (lo que aplicaría sin override en este alcance): se calcula
    // resolviendo el nivel inmediatamente superior.
    final inherited = _inheritedValue(m, orgId: orgId, siteId: siteId, profileId: profileId);

    // Estado del selector: null = Heredado.
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('Heredado: ${inherited ? "encendido" : "apagado"}',
                      style: const TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              ),
            ),
            DropdownButton<String>(
              value: override == null ? 'inherit' : (override ? 'on' : 'off'),
              underline: const SizedBox.shrink(),
              onChanged: _busy
                  ? null
                  : (v) async {
                      final enabled = v == 'inherit' ? null : v == 'on';
                      setState(() => _busy = true);
                      try {
                        await widget.repo.setModuleSetting(
                          organizationId: orgId,
                          siteId: siteId,
                          profileId: profileId,
                          module: m,
                          enabled: enabled,
                          updatedBy: widget.updatedBy,
                        );
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              items: const [
                DropdownMenuItem(value: 'inherit', child: Text('Heredado')),
                DropdownMenuItem(value: 'on', child: Text('Encendido')),
                DropdownMenuItem(value: 'off', child: Text('Apagado')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Valor que aplicaría SIN override en el alcance actual (el nivel superior).
  bool _inheritedValue(ModuleKey m,
      {required String orgId, String? siteId, String? profileId}) {
    if (profileId != null) {
      // usuario hereda de: sitio del usuario (si tuviera) -> centro -> default
      return widget.repo.isModuleEnabled(m,
          organizationId: orgId,
          siteId: widget.repo.primarySiteIdForProfile(profileId));
    }
    if (siteId != null) {
      // sitio hereda de: centro -> default
      return widget.repo.isModuleEnabled(m, organizationId: orgId);
    }
    // centro hereda de: default por tipo
    return m.defaultFor(_org!.centerType);
  }
}

/// Gestión de miembros de un centro: qué usuarios pueden entrar (switcher) y
/// con qué rol. Un usuario con membresía en ≥2 centros puede alternar entre
/// ellos desde el ícono de apósitos. Solo master/admin (RLS 0040).
class _MembershipsDialog extends StatefulWidget {
  final DataRepository repo;
  final Organization org;
  const _MembershipsDialog({required this.repo, required this.org});

  @override
  State<_MembershipsDialog> createState() => _MembershipsDialogState();
}

class _MembershipsDialogState extends State<_MembershipsDialog> {
  bool _busy = false;

  // Roles asignables a una membresía (no se ofrece 'master': es cross-centro
  // y no se gestiona por membresía de centro).
  static const _assignableRoles = [AppRole.admin, AppRole.clinico, AppRole.cuidador];

  Future<void> _toggle(AppUser user, bool grant, {UserCenterMembership? existing}) async {
    setState(() => _busy = true);
    try {
      if (grant) {
        await widget.repo.addMembership(user.id, widget.org.id, AppRole.clinico);
      } else if (existing != null) {
        await widget.repo.removeMembership(existing.id);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setRole(UserCenterMembership m, AppRole role) async {
    setState(() => _busy = true);
    try {
      // Reemplaza la membresía por una con el nuevo rol (upsert simple).
      await widget.repo.removeMembership(m.id);
      await widget.repo.addMembership(m.profileId, widget.org.id, role);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = widget.repo.listUsers().where((u) => u.role != AppRole.master).toList();
    final memberships = {
      for (final m in widget.repo.listMembershipsForOrg(widget.org.id)) m.profileId: m,
    };
    return AlertDialog(
      title: Text('Miembros · ${widget.org.name}'),
      content: SizedBox(
        width: MediaQuery.sizeOf(context).width < 520 ? double.maxFinite : 460,
        child: users.isEmpty
            ? const Text('No hay usuarios visibles.')
            : ListView(
                shrinkWrap: true,
                children: users.map((u) {
                  final m = memberships[u.id];
                  final isMember = m != null;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(u.fullName),
                    subtitle: Text(u.email, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isMember)
                          DropdownButton<AppRole>(
                            value: _assignableRoles.contains(m.role) ? m.role : AppRole.clinico,
                            underline: const SizedBox.shrink(),
                            items: _assignableRoles
                                .map((r) => DropdownMenuItem(
                                      value: r,
                                      child: Text(r.label, style: const TextStyle(fontSize: 12)),
                                    ))
                                .toList(),
                            onChanged: _busy ? null : (r) => r == null ? null : _setRole(m, r),
                          ),
                        Switch(
                          value: isMember,
                          activeColor: KuraColors.primary,
                          onChanged: _busy
                              ? null
                              : (v) => _toggle(u, v, existing: m),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _OrganizationFormDialog extends StatefulWidget {
  final DataRepository repo;
  const _OrganizationFormDialog({required this.repo});

  @override
  State<_OrganizationFormDialog> createState() => _OrganizationFormDialogState();
}

class _OrganizationFormDialogState extends State<_OrganizationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await widget.repo.createOrganization(_nameCtrl.text.trim());
      // dialogCtx propio (ver convencion documentada en la pantalla):
      // nunca el context externo del ShellRoute anidado.
      if (mounted) Navigator.pop(context, created.id);
    } catch (e) {
      setState(() {
        _error = 'No se pudo crear: $e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo centro (organización)'),
      content: SizedBox(
        // Responsivo: en pantallas angostas llena el ancho disponible (lo acota
        // el AlertDialog) en vez de forzar 380px y desbordar en movil.
        width: MediaQuery.sizeOf(context).width < 460 ? double.maxFinite : 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre del centro'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: KuraColors.danger)),
              ],
            ],
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
              : const Text('Crear'),
        ),
      ],
    );
  }
}

/// Configuración de la GUARDIA VAC del centro: número de WhatsApp al que se
/// escalan las alarmas del módulo de Terapia VAC. Vive en vac_settings.
class _VacGuardiaCard extends StatefulWidget {
  final DataRepository repo;
  final String orgId;
  final String initial;
  const _VacGuardiaCard({
    required this.repo,
    required this.orgId,
    required this.initial,
  });
  @override
  State<_VacGuardiaCard> createState() => _VacGuardiaCardState();
}

class _VacGuardiaCardState extends State<_VacGuardiaCard> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.repo.setVacOncallPhone(
          organizationId: widget.orgId, phone: _ctrl.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Número de guardia VAC guardado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.healing_outlined),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Guardia VAC',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
                'WhatsApp al que se escalan las alarmas de terapia VAC.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Número con lada',
                      hintText: '52 55 1234 5678',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Guardando…' : 'Guardar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
