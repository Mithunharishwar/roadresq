/// Build-time API keys.
///
/// No key is committed to this repository. Keys are injected when the app is
/// built, either with a single `--dart-define`:
///
///   flutter run --dart-define=GOOGLE_MAPS_API_KEY=AIza...
///
/// or — for local development — with a git-ignored defines file:
///
///   flutter run --dart-define-from-file=dart_defines.json
///
/// The Android Maps SDK reads its key separately, as the `MAPS_API_KEY` Gradle
/// manifest placeholder supplied by `android/local.properties` (also ignored).
///
/// Callers must treat an empty key as "not configured" and degrade gracefully
/// rather than issuing an unauthenticated request that is guaranteed to fail.
library;

/// Central access point for third-party API keys.
class ApiKeys {
  const ApiKeys._();

  /// Google Maps key used for the Dart-side Directions calls.
  ///
  /// Empty when the build did not supply `GOOGLE_MAPS_API_KEY`.
  static const String googleMaps = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  /// True when a Google Maps key was supplied at build time.
  static bool get hasGoogleMaps => googleMaps.isNotEmpty;
}
