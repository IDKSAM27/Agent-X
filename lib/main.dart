import 'package:AgentX/repositories/calendar_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:sqflite/sqflite.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/auth_gate.dart';
import 'core/config/api_config.dart';
import 'core/services/connectivity_service.dart';
import 'core/database/database_helper.dart';
import 'repositories/task_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Performance optimizations
  if (kDebugMode) {
    // Reduce animation scale for testing
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // Load environment variables
  await dotenv.load();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // CALL the offline services initialization
  await _initializeOfflineServices();

  // Initialize agent orchestrator
  // await AgentOrchestrator().initialize();

  runApp(const AgentXApp());
}

// MOVE the function outside of main() and make it top-level
Future<void> _initializeOfflineServices() async {
  try {
    print('🔄 Initializing offline services...');

    // Initialize connectivity service
    await ConnectivityService().initialize();

    // Initialize database
    await DatabaseHelper().database;

    // Initialize repositories
    TaskRepository().initialize();
    CalendarRepository().initialize();
    // NewsRepository doesn't need initialization

    // Clean expired cache
    await DatabaseHelper().cleanExpiredCache();

    print('✅ Offline services initialized successfully');
    print('🌐 Using backend: ${ApiConfig.baseUrl}');
  } catch (e) {
    print('❌ Error initializing offline services: $e');
    // Don't prevent app from starting, just log the error
  }
}

class AgentXApp extends StatelessWidget {
  const AgentXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgentX',
      debugShowCheckedModeBanner: false,

      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,

      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.of(context).textScaler.scale(1.0).clamp(1.0, 1.3),
            ),
          ),
          child: child!,
        );
      },

      // Use AuthGate instead of LoginScreen
      home: const AuthGate(),
    );
  }
}
