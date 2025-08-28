import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart'; // Login screen
import 'screens/home_screen.dart'; // Home screen

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables before anything else
  await dotenv.load();

  // Initialize Firebase
  await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,);


  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agent X Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.deepPurple,
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.deepPurple,
        ),
      ),
      themeMode: ThemeMode.system, // 🌓 Auto switch based on device settings
      home: const LoginScreen(), // Start with the login screen
    );
  }
}
