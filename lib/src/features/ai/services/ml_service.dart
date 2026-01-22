// Conditionally export the correct implementation
// If dart:io is available (Mobile/Desktop), use Mobile implementation (TFLite)
// If not (Web), use Web implementation (Stub)

export 'ml_service_web.dart'
    if (dart.library.io) 'ml_service_mobile.dart';
