import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../models/organization.dart';
import '../../services/data_repository.dart';
import '../admin/admin_home_screen.dart' show UsersTab, StaffTab, SitesTab, NoteCatalogTab;

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
  late final TabController _tabController = TabController(length: 5, vsync: this)
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plataforma'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Organizaciones'),
            Tab(text: 'Usuarios'),
            Tab(text: 'Personal sanitario'),
            Tab(text: 'Sitios'),
            Tab(text: 'Catálogo'),
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

          if (_tab == 0) {
            return _OrganizationsTab(
              repo: repo,
              organizations: organizations,
              selectedOrgId: _selectedOrgId,
              onSelect: (id) => setState(() => _selectedOrgId = id),
              onCreate: () => _openCreateOrganizationDialog(repo),
              onChanged: () => setState(() {}),
            );
          }

          if (organizations.isEmpty) {
            return const _NoOrganizationsState();
          }

          return Column(
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
                  _ => NoteCatalogTab(repo: repo, organizationId: _selectedOrgId),
                },
              ),
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
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: KuraColors.primary.withOpacity(0.12),
                      child: const Icon(Icons.hub_outlined, color: KuraColors.primary),
                    ),
                    title: Text(o.name),
                    subtitle: Text(o.isActive ? 'Activo' : 'Inactivo'),
                    trailing: Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Column(
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
                      ],
                    ),
                    onTap: () => onSelect(o.id),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: KuraColors.primary,
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Nuevo centro'),
        onPressed: onCreate,
      ),
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
