import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';

/// Un lead capturado en la pantalla previa de la demo. NO se guarda en Supabase:
/// se reenvía a Bitrix por la función portera (demo-lead). Aquí solo vive de paso
/// —y, si no hay red, en la cola local— hasta que se envía. Sin identificadores
/// del navegador, sin IP, sin lo que el prospecto hizo dentro de la demo (§3).
class DemoLead {
  final String firstName;
  final String lastName;
  final String email;
  final String? phone; // opcional (§1)
  final String userType; // la opción que eligió, en sus palabras (§2)
  final String? otherText; // texto libre cuando eligió "Otro"
  final String? event; // evento donde se mostró la demo (oculto en el form)
  final String createdAt; // ISO-8601

  const DemoLead({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.userType,
    this.phone,
    this.otherText,
    this.event,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        if (phone != null && phone!.isNotEmpty) 'phone': phone,
        'user_type': userType,
        if (otherText != null && otherText!.isNotEmpty) 'other_text': otherText,
        if (event != null && event!.isNotEmpty) 'event': event,
        'created_at': createdAt,
        'source': 'Demo KuraTracker',
      };

  factory DemoLead.fromJson(Map<String, dynamic> j) => DemoLead(
        firstName: j['first_name'] as String? ?? '',
        lastName: j['last_name'] as String? ?? '',
        email: j['email'] as String? ?? '',
        phone: j['phone'] as String?,
        userType: j['user_type'] as String? ?? '',
        otherText: j['other_text'] as String?,
        event: j['event'] as String?,
        createdAt: j['created_at'] as String? ?? '',
      );
}

/// Captura de leads de la demo (Fase 1: todo local). Guarda el lead ACTIVO
/// (bandera + nombre para el saludo) en preferencias, intenta enviarlo a la
/// función portera con timeout corto, y si falla lo deja en una COLA local para
/// reintentar — la demo nunca se bloquea por un problema de red (§5).
///
/// Persistencia en SharedPreferences (localStorage en Web), como [OfflineOutbox].
class DemoLeadService {
  static const _capturedKey = 'demo_lead_captured';
  static const _firstNameKey = 'demo_lead_first_name';
  static const _queueKey = 'demo_lead_queue_v1';

  /// Timeout corto: el wifi de un congreso falla y el prospecto no puede quedar
  /// mirando un spinner (§5).
  static const timeout = Duration(seconds: 4);

  /// Leads pendientes de enviar (cola no vacía). La UI de reinicio lo muestra.
  static final ValueNotifier<int> pendingCount = ValueNotifier<int>(0);

  /// Refresca el contador de pendientes desde disco (llamar al arrancar).
  static Future<void> init() async {
    pendingCount.value = (await _loadQueue()).length;
  }

  static Future<bool> hasLead() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_capturedKey) ?? false;
  }

  /// Nombre del lead para el saludo del dashboard (null si no hay o está vacío).
  static Future<String?> firstName() async {
    final p = await SharedPreferences.getInstance();
    final n = p.getString(_firstNameKey);
    return (n != null && n.trim().isNotEmpty) ? n.trim() : null;
  }

  /// Captura el lead: marca la sesión, guarda el nombre e intenta enviarlo. Si el
  /// envío falla o expira, lo encola y regresa igual (el flujo NO se bloquea).
  static Future<void> capture(DemoLead lead) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_capturedKey, true);
    await p.setString(_firstNameKey, lead.firstName);
    final ok = await _post(lead);
    if (!ok) await _enqueue(lead);
  }

  /// Borra el lead ACTIVO (bandera + nombre) para que reaparezca el formulario en
  /// blanco al siguiente prospecto. NO toca la cola de pendientes (§5.4/§7).
  static Future<void> clearActiveLead() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_capturedKey);
    await p.remove(_firstNameKey);
  }

  /// Reintenta enviar la cola en segundo plano; quita los que se envían y deja
  /// los que siguen fallando. Silencioso: es best-effort.
  static Future<void> retryPending() async {
    final q = await _loadQueue();
    if (q.isEmpty) return;
    final remaining = <DemoLead>[];
    for (final l in q) {
      final ok = await _post(l);
      if (!ok) remaining.add(l);
    }
    await _saveQueue(remaining);
  }

  static Future<int> pending() async => (await _loadQueue()).length;

  /// Los leads pendientes de enviar como CSV (para copiar al portapapeles antes
  /// de reiniciar y no perder ninguno si la red falló todo el evento). Vacío si
  /// no hay pendientes.
  static Future<String> pendingAsCsv() async {
    final q = await _loadQueue();
    if (q.isEmpty) return '';
    String cell(String? v) {
      final s = v ?? '';
      // Escape CSV: comillas dobles si hay coma, comilla o salto de línea.
      if (s.contains(',') || s.contains('"') || s.contains('\n')) {
        return '"${s.replaceAll('"', '""')}"';
      }
      return s;
    }

    final rows = <String>[
      'nombre,apellido,correo,telefono,tipo_usuario,otro,evento,fecha',
      for (final l in q)
        [
          cell(l.firstName),
          cell(l.lastName),
          cell(l.email),
          cell(l.phone),
          cell(l.userType),
          cell(l.otherText),
          cell(l.event),
          cell(l.createdAt),
        ].join(','),
    ];
    return rows.join('\n');
  }

  // --- interno ---

  static Future<bool> _post(DemoLead lead) async {
    final endpoint = AppConfig.leadsEndpoint;
    // Fase 1 / sin endpoint configurado: no hay a dónde mandarlo → encola.
    if (endpoint.isEmpty) return false;
    try {
      final resp = await http
          .post(
            Uri.parse(endpoint),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(lead.toJson()),
          )
          .timeout(timeout);
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (e) {
      debugPrint('DemoLeadService: envío falló, se encola: $e');
      return false;
    }
  }

  static Future<List<DemoLead>> _loadQueue() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_queueKey);
    if (raw == null || raw.isEmpty) return <DemoLead>[];
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          DemoLead.fromJson((e as Map).cast<String, dynamic>())
      ];
    } catch (e) {
      debugPrint('DemoLeadService: cola corrupta, se descarta: $e');
      return <DemoLead>[];
    }
  }

  static Future<void> _saveQueue(List<DemoLead> q) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_queueKey, jsonEncode([for (final l in q) l.toJson()]));
    pendingCount.value = q.length;
  }

  static Future<void> _enqueue(DemoLead lead) async {
    final q = await _loadQueue()
      ..add(lead);
    await _saveQueue(q);
  }
}

/// Nombre del lead para el saludo (solo en modo demo; null en producción).
final demoLeadFirstNameProvider = FutureProvider<String?>((ref) async {
  if (AppConfig.isSupabaseConfigured) return null;
  return DemoLeadService.firstName();
});
