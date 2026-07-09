import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../models/app_user.dart';
import '../../services/data_repository.dart';

/// Panel de administración: gestión de personal sanitario, sitios y
/// activación de usuarios / función premium (sección 4).
class AdminHomeScreen extends ConsumerStatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  ConsumerState<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends ConsumerState<AdminHomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
        bottom: TabBar(
          tabs: const [
            Tab(text: 'Usuarios'),
            Tab(text: 'Personal sanitario'),
            Tab(text: 'Sitios'),
          ],
          onTap: (i) => setState(() => _tab = i),
        ),
      ),
      body: DefaultTabController(
        length: 3,
        child: repoAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error: $e')),
          data: (repo) {
            switch (_tab) {
              case 1:
                return _StaffTab(repo: repo);
              case 2:
                return _SitesTab(repo: repo);
              default:
                return _UsersTab(repo: repo);
            }
          },
        ),
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
            subtitle: Text('${u.email} · ${u.role.label}'),
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
  @override
  Widget build(BuildContext context) {
    final staff = widget.repo.listStaff();
    return Scaffold(
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: staff.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final s = staff[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: KuraColors.primary.withOpacity(0.12),
                child: Text(s.folio.substring(1, 3)),
              ),
              title: Text(s.fullName),
              subtitle: Text('${s.folio} · ${s.roleTitle}'),
              trailing: Switch(
                value: s.isActive,
                activeColor: KuraColors.primary,
                onChanged: (v) async {
                  await widget.repo.setStaffActive(s.id, v);
                  setState(() {});
                },
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: KuraColors.primary,
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo'),
        onPressed: () async {
          final sites = widget.repo.listSites();
          await widget.repo.createStaff(
            fullName: 'Nuevo Kurador',
            roleTitle: 'Kurador',
            primarySiteId: sites.isNotEmpty ? sites.first.id : null,
          );
          setState(() {});
        },
      ),
    );
  }
}

class _SitesTab extends StatelessWidget {
  final DataRepository repo;
  const _SitesTab({required this.repo});

  @override
  Widget build(BuildContext context) {
    final sites = repo.listSites();
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: sites.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final s = sites[i];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.location_on_outlined, color: KuraColors.primary),
            title: Text(s.name),
            subtitle: Text('${s.kind}${s.address != null ? ' · ${s.address}' : ''}'),
          ),
        );
      },
    );
  }
}
