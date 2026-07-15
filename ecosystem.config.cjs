module.exports = {
  apps: [
    {
      // Build de produccion: compilado con --dart-define=SUPABASE_URL/ANON_KEY
      // reales -> AppConfig.isSupabaseConfigured == true. Sirve build/web.
      name: 'kuratracker-web',
      script: 'python3',
      args: 'serve_spa.py',
      env: {
        SERVE_DIR: 'web',
        SERVE_PORT: '3000'
      },
      watch: false,
      instances: 1,
      exec_mode: 'fork'
    },
    {
      // Build demo: compilado SIN --dart-define de Supabase ->
      // AppConfig.isSupabaseConfigured == false. Reaparece el panel de
      // "Cuentas de demostracion" (accesos de un toque) y los pacientes
      // sinteticos del seed local. Sirve build/web-demo en otro puerto,
      // no toca Supabase ni el build de produccion.
      name: 'kuratracker-web-demo',
      script: 'python3',
      args: 'serve_spa.py',
      env: {
        SERVE_DIR: 'web-demo',
        SERVE_PORT: '3001'
      },
      watch: false,
      instances: 1,
      exec_mode: 'fork'
    }
  ]
}
