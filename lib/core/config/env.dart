/// App-wide configuration. Override via --dart-define at build time, e.g.
/// flutter run --dart-define=API_URL=https://dev.api.crm.cnc.marifahlabs.com
class Env {
  /// Backend base URL (portal default was http://localhost:3001).
  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://dev.api.crm.cnc.marifahlabs.com',
  );

  /// Google Maps key for the driver route map.
  // Defaults to the shared CNC Maps key (used for reverse-geocoding); can be
  // overridden with --dart-define=GOOGLE_MAPS_API_KEY=...
  static const String googleMapsApiKey = String.fromEnvironment(
      'GOOGLE_MAPS_API_KEY',
      defaultValue: 'AIzaSyDBUAiCAGzjDCSH1MG4JwAAfGuSw38kcZw');

  /// Login portal scope — the backend uses this to restrict to partner/worker.
  static const String loginPortal = 'partner';
}
