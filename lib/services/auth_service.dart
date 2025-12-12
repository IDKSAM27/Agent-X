import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/database/database_helper.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // Singleton instance
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  Future<void> signOut(BuildContext context) async {
    try {
      // 1. Clear Local Database (SQLite)
      await _dbHelper.clearAllTables();
      print('✅ Local database cleared');

      // 2. Clear Shared Preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      print('✅ Shared preferences cleared');

      // 3. Sign out from Firebase
      await _auth.signOut();
      print('✅ Firebase signed out');

      // 4. Navigate to Login Screen (Root)
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      print('❌ Error signing out: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing out: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
