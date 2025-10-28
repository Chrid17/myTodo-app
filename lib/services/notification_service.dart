// Conditional export: web implementation will be used when running on web.
export 'notification_service_mobile.dart'
    if (dart.library.html) 'notification_service_web.dart';
