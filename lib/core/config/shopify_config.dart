/// Configuración de la tienda Shopify (Storefront API) del módulo de Insumos.
///
/// El dominio y la versión de API no son sensibles; el Storefront access token
/// es "público-seguro" (Shopify lo diseña para embeberse en el cliente), pero de
/// todos modos se inyecta por `--dart-define` (secret de CI) para no versionarlo
/// en el repo. Sin token, la tienda muestra un estado "no configurada".
class ShopifyConfig {
  static const String storeDomain = String.fromEnvironment(
    'SHOPIFY_STORE_DOMAIN',
    defaultValue: 'kuramas.myshopify.com',
  );

  static const String apiVersion = String.fromEnvironment(
    'SHOPIFY_API_VERSION',
    defaultValue: '2026-07',
  );

  static const String storefrontToken =
      String.fromEnvironment('SHOPIFY_STOREFRONT_TOKEN');

  static bool get isConfigured =>
      storeDomain.isNotEmpty && storefrontToken.isNotEmpty;

  static Uri get graphqlEndpoint =>
      Uri.parse('https://$storeDomain/api/$apiVersion/graphql.json');
}
