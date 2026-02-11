// Conditional export: web implementation will be used when running on web.
// Use universal (handles both mobile and desktop) for non-web platforms.
export 'notification_service_universal.dart'
    if (dart.library.js_interop) 'notification_service_web.dart';
