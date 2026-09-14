/// AppShell muestra su PROPIA navegación (riel en escritorio, barra flotante en
/// móvil) SALVO en /platform, donde la consola del master ya trae su único riel
/// (KuraNavRail). Así no conviven dos rieles ni una etiqueta activa por duplicado.
///
/// Vive aparte (sin dependencias pesadas) para probarse en local.
bool appShellShowsOwnNav(String path) => !path.startsWith('/platform');
