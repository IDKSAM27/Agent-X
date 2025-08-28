import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_screen.dart';

class ProfessionInputScreen extends StatelessWidget {
  final TextEditingController _controller = TextEditingController();

  ProfessionInputScreen({super.key});

  void _saveProfession(BuildContext context) async {
    final profession = _controller.text.trim();
    if (profession.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'email': user.email,
        'profession': profession,
      }, SetOptions(merge: true));
    }

    // ✅ Instead of going to ChatScreen directly, go to HomeScreen
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Enter Profession")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              "Please tell us your profession (e.g. Student, Teacher):",
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: "Profession",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => _saveProfession(context),
              child: const Text("Continue"),
            ),
          ],
        ),
      ),
    );
  }
}
