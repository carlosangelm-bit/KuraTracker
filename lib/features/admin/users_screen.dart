import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/design/tokens.dart';
import '../../core/utils/caregiver_login.dart';
import '../../core/widgets/kura_primary_fab.dart';
import '../../models/app_user.dart';
import '../../services/data_repository.dart';

/// Pantalla de gestión de usuarios y roles (sección de Administración). Se reutiliza
/// en dos contextos:
///   - Panel de Administración (admin de centro): organizationId = su centro.
///   - Área de Plataforma (master): organizationId = centro elegido en el
///     selector (por eso ve/gestiona usuarios de cualquier centro, uno a la vez).
/// Permite crear usuarios CON login (via Edge Function admin-create-user), cambiar su
/// conjunto de roles y activar/desactivar. El usuario en sesión ([currentUserId]) no
/// puede cambiarse el rol ni desactivarse a sí mismo, para evitar dejarse fuera.
///
/// Es un CUERPO de sección, no una pantalla completa: NO se envuelve en KuraScreen ni
/// trae AppBar. AdminSectionsShell ya pinta el KuraContentHeader («Administración ›
/// Usuarios») y el KuraNavRail con la cuenta en el pie. El Scaffold aquí es solo para
/// hospedar el KuraPrimaryFab. Todo color sale de [BrandTokens] (respeta la marca del
/// centro: morado/azul/rosa), nunca del alias de marca fija.
class UsersScreen extends StatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  final String? currentUserId;
  const UsersScreen({
    super.key,
    required this.repo,
    required this.organizationId,
    required this.currentUserId,
  });

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

enum _UserStatus { todos, activos, inactivos }

class _UsersScreenState extends State<UsersScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';
  AppRole? _roleFilter;
  _UserStatus _status = _UserStatus.todos;

  /// Muestra el mensaje de un rechazo del repositorio (candado de rol/premium/
  /// asientos). Estos mensajes están redactados a propósito y abren un camino de
  /// acción; morían silenciosos en los interruptores.
  void _showRepoError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', ''))));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Envía el correo de "restablecer/establecer contraseña" (Supabase) para que
  /// la persona ponga su propia clave, en vez de compartir una temporal a mano.
  Future<void> _sendPasswordEmail(String email) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: kIsWeb ? Uri.base.origin : null,
      );
      messenger.showSnackBar(SnackBar(
          content: Text('Correo enviado a $email para establecer su contraseña.')));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('No se pudo enviar el correo: $e')));
    }
  }

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
      builder: (dialogCtx) {
        final t = BrandTokens.of(dialogCtx);
        return AlertDialog(
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
                    color: t.chipBg,
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
            if (AppConfig.isSupabaseConfigured && user.role != AppRole.cuidador)
              TextButton.icon(
                icon: const Icon(Icons.mail_outline, size: 18),
                label: const Text('Enviar correo para contraseña'),
                onPressed: () async {
                  Navigator.pop(dialogCtx);
                  await _sendPasswordEmail(user.email);
                },
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Listo'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _editRoles(AppUser u) async {
    final result = await showDialog<Set<AppRole>>(
      context: context,
      builder: (dialogCtx) => _RolesEditorDialog(
        userName: u.fullName,
        initial: u.effectiveRoles,
      ),
    );
    if (result == null) return; // cancelado
    try {
      await widget.repo
          .setUserRoles(u.id, result, organizationId: widget.organizationId);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('No se pudieron cambiar los roles: '
                  '${e.toString().replaceFirst('Exception: ', '')}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.repo
        .listUsers()
        .where((u) =>
            widget.organizationId == null ||
            u.organizationId == widget.organizationId)
        .toList();
    final q = _search.trim().toLowerCase();
    final users = all.where((u) {
      if (_roleFilter != null && u.role != _roleFilter) return false;
      if (_status == _UserStatus.activos && !u.isActive) return false;
      if (_status == _UserStatus.inactivos && u.isActive) return false;
      if (q.isNotEmpty &&
          !u.fullName.toLowerCase().contains(q) &&
          !u.email.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) =>
          a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));

    return Scaffold(
      body: Column(
        children: [
          _filtersBar(all.length, users.length),
          const Divider(height: 1),
          Expanded(
            child: all.isEmpty
                // Dos vacíos DISTINTOS a propósito: aún no hay usuarios vs. los
                // filtros no coinciden. El primero enseña el alta; el segundo dice
                // que el centro sí tiene gente, solo que oculta por el filtro.
                ? const _UsersEmptyState(
                    icon: Icons.people_outline,
                    message: 'Aún no hay usuarios en este centro.\n'
                        'Usa el botón "Nuevo usuario" para dar de alta al primero.',
                  )
                : users.isEmpty
                    ? const _UsersEmptyState(
                        icon: Icons.search_off,
                        message: 'Ningún usuario coincide con los filtros.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                        itemCount: users.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _userCard(users[i]),
                      ),
          ),
        ],
      ),
      floatingActionButton: KuraPrimaryFab(
        icon: Icons.person_add_alt_1,
        label: 'Nuevo usuario',
        onPressed: widget.organizationId == null ? null : _openCreateForm,
      ),
    );
  }

  Widget _filtersBar(int total, int shown) {
    final t = BrandTokens.of(context);
    const roles = <AppRole?>[
      null,
      AppRole.admin,
      AppRole.clinico,
      AppRole.enfermeria,
      AppRole.cuidador,
    ];
    String roleChip(AppRole? r) => switch (r) {
          null => 'Todos',
          AppRole.admin => 'Admin',
          AppRole.clinico => 'Sanitario',
          AppRole.enfermeria => 'Enfermería',
          AppRole.cuidador => 'Cuidador',
          _ => r.label,
        };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar por nombre o correo…',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: 'Limpiar',
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _search = '');
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in roles)
                FilterChip(
                  label: Text(roleChip(r)),
                  selected: _roleFilter == r,
                  onSelected: (_) => setState(() => _roleFilter = r),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final st in _UserStatus.values)
                      ChoiceChip(
                        label: Text(switch (st) {
                          _UserStatus.todos => 'Todos',
                          _UserStatus.activos => 'Activos',
                          _UserStatus.inactivos => 'Inactivos',
                        }),
                        selected: _status == st,
                        onSelected: (_) => setState(() => _status = st),
                      ),
                  ],
                ),
              ),
              // Contador «N de M»: evita creer que un filtro vació el centro.
              Text(
                '$shown de $total',
                style: TextStyle(fontSize: 12, color: t.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _userCard(AppUser u) {
    final t = BrandTokens.of(context);
    final isSelf = u.id == widget.currentUserId;
    // El cuidador entra con teléfono + clave (correo sintético), no recibe
    // correos reales; por eso el envío de "establecer contraseña" no aplica.
    final canEmail = AppConfig.isSupabaseConfigured && !u.isCaregiverOnly;
    final canRole = !isSelf && !u.isMaster;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: t.chipBg,
            child: Icon(_roleIcon(u.role), color: t.brandPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${u.fullName}${isSelf ? ' (tú)' : ''}',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: t.textPrimary)),
                const SizedBox(height: 2),
                Text(u.email,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: t.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    // El CONJUNTO de roles (ordenado por precedencia), no solo el
                    // primario. Estados van a tokens de ESTADO, no a la marca.
                    for (final r in _rolesByPrecedence(u.effectiveRoles))
                      _tag(r.label, t.brandPrimary),
                    if (!u.isActive) _tag('Inactivo', t.statusDanger),
                    if (u.premiumEnabled) _tag('Premium', t.statusSuccess),
                    if (u.staffId != null)
                      _tag('Vinculado a personal', t.textSecondary),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Controles AGRUPADOS: los dos interruptores juntos en su propio bloque,
          // separados del menú de tres puntos (antes competían en el mismo Wrap).
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: t.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _switchCol(
                      'Activo',
                      u.isActive,
                      t.brandPrimary,
                      isSelf
                          ? null
                          : (v) async {
                              try {
                                await widget.repo.setUserActive(u.id, v);
                                if (mounted) setState(() {});
                              } catch (e) {
                                _showRepoError(e);
                              }
                            },
                    ),
                    _switchCol(
                      'Premium',
                      u.premiumEnabled,
                      t.statusSuccess,
                      (v) async {
                        // El repositorio rechaza si el centro no tiene el add-on
                        // Protocolo Kura+ (candado). Antes moría silencioso: el
                        // interruptor se quedaba apagado sin decir por qué,
                        // indistinguible de un botón roto, y se perdía el camino de
                        // venta que el mensaje abre.
                        try {
                          await widget.repo.setUserPremium(u.id, v);
                          if (mounted) setState(() {});
                        } catch (e) {
                          _showRepoError(e);
                        }
                      },
                    ),
                  ],
                ),
              ),
              if (canEmail || canRole)
                PopupMenuButton<String>(
                  tooltip: 'Más acciones',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) {
                    if (v == 'email') {
                      _sendPasswordEmail(u.email);
                    } else if (v == 'roles') {
                      _editRoles(u);
                    }
                  },
                  itemBuilder: (_) => [
                    if (canEmail)
                      const PopupMenuItem(
                        value: 'email',
                        child: Row(children: [
                          Icon(Icons.mail_outline, size: 18),
                          SizedBox(width: 8),
                          Text('Enviar correo para establecer contraseña'),
                        ]),
                      ),
                    if (canEmail && canRole) const PopupMenuDivider(),
                    if (canRole)
                      const PopupMenuItem(
                        value: 'roles',
                        child: Row(children: [
                          Icon(Icons.badge_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Editar roles'),
                        ]),
                      ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _switchCol(
      String label, bool value, Color color, ValueChanged<bool>? onChanged) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10)),
        Switch(value: value, activeColor: color, onChanged: onChanged),
      ],
    );
  }

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

  IconData _roleIcon(AppRole role) => switch (role) {
        AppRole.admin => Icons.admin_panel_settings,
        AppRole.enfermeria => Icons.vaccines_outlined,
        AppRole.cuidador => Icons.volunteer_activism_outlined,
        AppRole.master => Icons.hub_outlined,
        _ => Icons.medical_services,
      };
}

/// Estado vacío local (icono + mensaje), con [BrandTokens]. Local a propósito: los
/// dos vacíos de Usuarios (sin usuarios / sin coincidencias) no llevan acción, a
/// diferencia de KuraEmptyState; conservarlos tal cual evita cambiar comportamiento.
class _UsersEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _UsersEmptyState({required this.icon, required this.message});

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

/// Roles ordenados por precedencia (master>admin>clinico>enfermeria>cuidador)
/// para mostrarlos de forma estable (el conjunto no tiene orden).
List<AppRole> _rolesByPrecedence(Set<AppRole> roles) => const [
      AppRole.master,
      AppRole.admin,
      AppRole.clinico,
      AppRole.enfermeria,
      AppRole.cuidador,
    ].where(roles.contains).toList();

/// Formulario de alta de usuario con login. Devuelve el [CreatedUser] via
/// Navigator.pop para que la pantalla muestre la contraseña temporal.
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
  final Set<AppRole> _roles = {AppRole.clinico};
  String? _siteId;
  bool _saving = false;
  String? _error;

  bool get _isCaregiver => _roles.contains(AppRole.cuidador);
  bool get _isClinical => _roles.contains(AppRole.clinico);

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
    // Validación del conjunto (misma regla que servidor): no vacío, cuidador
    // exclusivo, sin master. El picker ya lo impide, pero se revalida por si acaso.
    final roleErr = validateRoleSet(_roles);
    if (roleErr != null) {
      setState(() => _error = roleErr);
      return;
    }
    // Gate del módulo Administración (avanzado): un usuario SOLO-administrativo (sin
    // rol clínico ni enfermería ni cuidador) consume un asiento CLÍNICO cuando el
    // centro no tiene el módulo (que trae 3 cupos admin dedicados). Se bloquea SOLO
    // "más allá de lo que permita el conteo": si aún hay asiento clínico libre, el
    // alta pasa y la base lo absorbe. assert_seat_available sigue siendo la autoridad;
    // esto evita el viaje y nombra el módulo en vez de un genérico "sin asientos".
    final adminOnly = _roles.contains(AppRole.admin) &&
        !_roles.contains(AppRole.clinico) &&
        !_roles.contains(AppRole.enfermeria) &&
        !_roles.contains(AppRole.cuidador);
    if (adminOnly &&
        !widget.repo.premiumAdminFor(widget.organizationId) &&
        widget.repo
            .licenseSummaryFor(widget.organizationId)
            .clinicalSeats
            .full) {
      setState(() => _error =
          'Este usuario es solo administrativo. Sin el módulo Administración '
          'avanzada (que incluye 3 cupos admin dedicados) consume un asiento '
          'clínico, y no '
          'hay asientos clínicos disponibles. Contrata el módulo o libera un asiento.');
      return;
    }
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
        roles: _roles,
        organizationId: widget.organizationId,
        phone: phone.isEmpty ? null : phone,
        cedulaProfesional: cedula.isEmpty ? null : cedula,
        primarySiteId: _isClinical ? _siteId : null,
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
    final t = BrandTokens.of(context);
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
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Roles',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.textSecondary)),
                ),
                _RolesPicker(
                  value: _roles,
                  onChanged: (next) => setState(() {
                    _roles
                      ..clear()
                      ..addAll(next);
                  }),
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
                      final tt = (v ?? '').trim();
                      if (tt.isEmpty) return 'Requerido';
                      if (!tt.contains('@') || !tt.contains('.')) {
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
                if (_isClinical) ...[
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
                        (s) => DropdownMenuItem<String?>(
                            value: s.id, child: Text(s.name)),
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
                  style: TextStyle(fontSize: 11, color: t.textSecondary),
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
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: t.brandPrimary),
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Crear usuario'),
        ),
      ],
    );
  }
}

/// Grupo de casillas para elegir el CONJUNTO de roles (punto 6 §3). Impone en la
/// UI la misma regla que valida el servidor: `cuidador` es EXCLUSIVO (al marcarlo
/// se limpian las demás y se deshabilitan; si hay otra marcada, cuidador se
/// deshabilita). `master` nunca aparece. La validación de "no vacío" la hace el
/// formulario al enviar (validateRoleSet).
class _RolesPicker extends StatelessWidget {
  final Set<AppRole> value;
  final ValueChanged<Set<AppRole>> onChanged;
  const _RolesPicker({required this.value, required this.onChanged});

  static const _selectable = [
    AppRole.admin,
    AppRole.clinico,
    AppRole.enfermeria,
    AppRole.cuidador,
  ];

  void _toggle(AppRole r, bool on) {
    final next = {...value};
    if (on) {
      if (r == AppRole.cuidador) {
        next
          ..clear()
          ..add(AppRole.cuidador); // exclusivo
      } else {
        next
          ..remove(AppRole.cuidador)
          ..add(r);
      }
    } else {
      next.remove(r);
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final caregiverSelected = value.contains(AppRole.cuidador);
    final hasNonCaregiver = value.any((x) => x != AppRole.cuidador);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final r in _selectable)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: t.brandPrimary,
            value: value.contains(r),
            onChanged:
                (r == AppRole.cuidador ? hasNonCaregiver : caregiverSelected)
                    ? null
                    : (v) => _toggle(r, v ?? false),
            title: Text(r.label),
            subtitle: r == AppRole.cuidador
                ? const Text('Acceso reducido; no se combina con otros roles',
                    style: TextStyle(fontSize: 11))
                : null,
          ),
      ],
    );
  }
}

/// Diálogo para editar el CONJUNTO de roles de un usuario existente (reemplaza el
/// viejo menú "Hacer X"). Devuelve el conjunto elegido, o null si se cancela.
class _RolesEditorDialog extends StatefulWidget {
  final String userName;
  final Set<AppRole> initial;
  const _RolesEditorDialog({required this.userName, required this.initial});

  @override
  State<_RolesEditorDialog> createState() => _RolesEditorDialogState();
}

class _RolesEditorDialogState extends State<_RolesEditorDialog> {
  late final Set<AppRole> _roles = {...widget.initial}..remove(AppRole.master);

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final err = validateRoleSet(_roles);
    return AlertDialog(
      title: Text('Roles de ${widget.userName}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RolesPicker(
              value: _roles,
              onChanged: (next) => setState(() {
                _roles
                  ..clear()
                  ..addAll(next);
              }),
            ),
            if (err != null) ...[
              const SizedBox(height: 8),
              Text(err,
                  style: TextStyle(color: t.statusDanger, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: err != null ? null : () => Navigator.pop(context, _roles),
          style: FilledButton.styleFrom(backgroundColor: t.brandPrimary),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
