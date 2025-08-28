import 'package:flutter/material.dart';
import 'screens/chat_screen.dart';
import 'screens/clock_screen.dart';
import 'screens/calendar_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agent X Assistant')),
      body: Column(
        children: [
          // Top content
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Welcome to Agent-X! You are logged in.',
                    style: TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const ChatScreen(profession: 'YourProfession'),
                        ),
                      );
                    },
                    child: const Text("Open Chatbot"),
                  ),
                ],
              ),
            ),
          ),

          // Bottom buttons (Clock and Calendar)
          // padding: const EdgeInsets.fromLTRB(16, 0, 16, 30), -> Pookie Gyan this will add padding to left and right too, if needed
          Padding(
            padding: const EdgeInsets.only(
              bottom: 30.0,
            ), // <-- Adjust value as needed
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ClockScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(140, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text("Clock", style: TextStyle(fontSize: 18)),
                ),

                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CalendarScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(140, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text("Calendar", style: TextStyle(fontSize: 18)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
