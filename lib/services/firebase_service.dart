import 'package:firebase_auth/firebase_auth.dart';

class FirebaseService {
  static Future<String?> getCurrentUserToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        return await user.getIdToken();
      }
      return null;
    } catch (e) {
      print('Error getting Firebase ID token: $e');
      return null;
    }
  }

  static String? getCurrentUserId() {
    return FirebaseAuth.instance.currentUser?.uid;
  }

  static User? getCurrentUser() {
    return FirebaseAuth.instance.currentUser;
  }
}