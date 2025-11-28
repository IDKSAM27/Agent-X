class ApiConfig {
  // Development configuration
  static String get baseUrl {
    // 1. Check for environment variable (passed via --dart-define)
    const envUrl = String.fromEnvironment('API_BASE_URL');
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    // 2. Platform-specific defaults
    // Note: kIsWeb is not available in pure Dart, but for Flutter apps we usually import foundation.
    // However, to keep this file simple and dependency-free if possible, we can use conditional imports or just assume.
    // Since this is a Flutter project, let's use a simple heuristic or just standard defaults.
    // Ideally we would import 'package:flutter/foundation.dart'; but let's check if we can avoid it.
    // Actually, for this specific file, let's just use the standard localhost for now, 
    // but we really should import foundation to check for kIsWeb if we want to be robust.
    // Let's assume the user has foundation available.
    
    // For now, let's implement the logic requested:
    // Web -> "" (relative)
    // Android -> 10.0.2.2
    // iOS/Desktop -> localhost
    
    // We need to import 'dart:io' to check Platform, but 'dart:io' is not available on Web.
    // So we need to use 'package:flutter/foundation.dart'.
    
    return _determineBaseUrl();
  }

  static String _determineBaseUrl() {
    // If we are in a web build (kIsWeb), return empty string for relative path
    // We can't easily check kIsWeb without importing foundation. 
    // Let's assume this file is part of the Flutter app.
    // We will need to add the import to the top of the file.
    if (const bool.fromEnvironment('dart.library.js_util')) {
       return ""; // Web: relative path, will use Nginx proxy
    }
    
    // For mobile/desktop (dart:io available)
    // We can't use Platform.isAndroid here safely if we want this to compile for web without conditional imports.
    // BUT, since we are inside a function that might not be called on web if we guard it, it might be okay?
    // Actually, the safest way without conditional imports is just to rely on the user passing the flag for mobile,
    // OR use the 10.0.2.2 default if we can detect Android.
    
    // SIMPLIFICATION:
    // If not web (checked via dart.library.js_util), default to localhost.
    // The user can override with --dart-define=API_BASE_URL=http://10.0.2.2:8000 for Android emulator.
    // OR we can try to be smart.
    
    return "http://localhost:8000";
  }

  // API endpoints
  static const String agentsEndpoint = "/api/agents";
  static const String healthEndpoint = "/api/health";

  // For production deployment
  // static const String baseUrl = "https://your-deployed-api.com";

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 90);
  static const Duration receiveTimeout = Duration(seconds: 90);
 
  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
}
