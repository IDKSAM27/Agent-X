import 'package:flutter/material.dart';
import 'services/briefing_service.dart';
import 'core/notifications/notification_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/auth_gate.dart';
import 'core/agents/agent_orchestrator.dart';

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

  // Initialize agent orchestrator
  // await AgentOrchestrator().initialize();

  // Initialize Notifications
  final notificationService = NotificationService();
  await notificationService.initialize();
  await notificationService.requestPermissions();

  runApp(const AgentXApp());
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
//ye le bkl