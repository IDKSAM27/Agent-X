import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../home_screen.dart';
import 'signup_screen.dart';
import 'profession_input_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  Future<void> _signInWithEmail() async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      _navigateToHome();
    } catch (e) {
      _showError(e.toString());
    }
  }

  Future<void> _signInWithGoogle() async {
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      _navigateToHome();
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _navigateToHome() async {
    print("🔑 Checking logged in user...");
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      try {
        print("📡 Fetching Firestore doc...");

        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 5)); // <-- ADD TIMEOUT

        if (!doc.exists) {
          print("⚠️ Document does not exist, redirecting to profession input");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => ProfessionInputScreen()),
          );
          return;
        }

        final data = doc.data();
        final profession = data?['profession'];
        print("📌 Profession: $profession");

        if (profession != null && profession.toString().isNotEmpty) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => ProfessionInputScreen()),
          );
        }
      } catch (e) {
        print("❌ Error fetching Firestore doc: $e");

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => ProfessionInputScreen()),
        );
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("Error: $message")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _signInWithEmail,
              child: const Text('Login with Email'),
            ),
            const SizedBox(height: 7),
            ElevatedButton(
              onPressed: _signInWithGoogle,
              child: const Text('Login with Google'),
            ),
            const SizedBox(height: 5),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SignUpScreen()),
                );
              },
              child: const Text("Don't have an account? Sign up here"),
            ),
          ],
        ),
      ),
    );
  }
}
