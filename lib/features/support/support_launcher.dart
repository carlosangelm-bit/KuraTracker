import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/session_provider.dart';
import '../../core/router/app_router.dart';
import '../../models/center_type.dart';

/// Abre el asistente de ayuda capturando el CONTEXTO NO SENSIBLE de la pantalla
/// actual (rol, tipo de centro, ruta y una etiqueta legible de la pantalla) para
/// que el agente detecte el perfil y el proceso del usuario. Nunca incluye datos
/// del paciente; la ruta se limpia de ids en la Edge Function.
///
/// No depende del BuildContext para la ruta/navegación (usa el routerProvider),
/// así funciona igual desde un menú o desde el overlay global de ayuda.
void openSupportAssistant(WidgetRef ref) {
  final session = ref.read(sessionProvider);
  final user = session.user;
  if (user == null) return;
  final router = ref.read(routerProvider);
  final location =
      router.routerDelegate.currentConfiguration.uri.toString();
  final ctx = <String, String>{
    'rol': user.role.name,
    'centro': session.activeCenterType.dbValue,
    'ruta': location,
    'pantalla': supportScreenLabelFor(location),
  };
  router.push('/support', extra: ctx);
}

/// Traduce la ruta actual a una etiqueta legible de la pantalla (el "proceso"
/// que el usuario está operando), para el contexto del asistente.
String supportScreenLabelFor(String location) {
  final path = Uri.parse(location).path;
  const exact = <String, String>{
    '/': 'Inicio (dashboard)',
    '/patients': 'Lista de pacientes',
    '/patients/new': 'Alta de paciente',
    '/reports': 'Reportes',
    '/agenda': 'Agenda de citas',
    '/risk': 'Tablero de riesgo (prevención)',
    '/prevention-agenda': 'Agenda de prevención (rondas)',
    '/hospital': 'Dashboard del hospital',
    '/insumos': 'Insumos',
    '/insumos/inventario': 'Inventario',
    '/insumos/tienda': 'Tienda de insumos',
    '/insumos/mapeo': 'Mapeo de insumos',
    '/insumos/consumo': 'Consumo y costeo por paciente',
    '/insumos/reabasto': 'Reabasto sugerido',
    '/comercial': 'Comercial',
    '/caregiver': 'Monitoreo del cuidador',
    '/admin': 'Administración del centro',
    '/platform': 'Plataforma (master)',
    '/import-export': 'Importar / exportar (eKare)',
    '/vac': 'Terapia VAC',
  };
  final e = exact[path];
  if (e != null) return e;

  if (path.endsWith('/edit')) return 'Editar paciente';
  if (path.contains('/wound/') && path.endsWith('/capture')) {
    return 'Valoración: captura de herida';
  }
  if (path.contains('/follow-up/new') || path.contains('/follow-up/draft')) {
    return 'Registrar seguimiento (5 fases)';
  }
  if (path.contains('/follow-up')) return 'Seguimiento de herida';
  if (path.contains('/consultation/new')) return 'Nueva consulta';
  if (path.contains('/consultation/')) return 'Detalle de consulta';
  if (path.endsWith('/diagnoses')) return 'Diagnósticos (CIE-10)';
  if (path.endsWith('/comorbidities')) return 'Comorbilidades';
  if (path.endsWith('/consents')) return 'Consentimientos';
  if (path.endsWith('/referrals/new')) return 'Nueva referencia';
  if (path.endsWith('/referrals')) return 'Referencias / interconsultas';
  if (path.endsWith('/adverse-events/new')) return 'Registrar evento adverso';
  if (path.endsWith('/adverse-events')) return 'Eventos adversos';
  if (path.endsWith('/labs')) return 'Laboratorios';
  if (path.endsWith('/risk')) return 'Prevención y riesgo del paciente';
  if (path.startsWith('/caregiver/patient/')) {
    return 'Monitoreo de paciente (cuidador)';
  }
  if (path.startsWith('/vac/')) return 'Terapia VAC';
  if (path.startsWith('/patients/')) return 'Detalle del paciente';
  return 'KuraTracker';
}
