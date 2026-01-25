// Conditional export: web implementation will be used when running on web.
// Use universal (no-op on unsupported desktop) for non-web.
export 'notification_service_universal.dart'
    if (dart.library.html) 'notification_service_web.dart';
