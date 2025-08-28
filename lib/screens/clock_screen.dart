import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';

final List<String> _titles = ['Alarm', 'Clock', 'Timer'];

class ClockScreen extends StatefulWidget {
  const ClockScreen({super.key});

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen> {
  int _selectedIndex = 1; // Default to Clock tab

  // Page switching logic
  final List<Widget> _pages = [
    const AlarmPage(),
    const ClockPage(),
    const TimerPage(),
  ];

  void _onTabTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Agent X ${_titles[_selectedIndex]}')),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTapped,
        type: BottomNavigationBarType.fixed, // or shifting for animation
        selectedItemColor: Colors.purple, // Highlighted tab color
        unselectedItemColor: Colors.grey, // Dimmed others
        showUnselectedLabels: true, // Optional
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.alarm), label: 'Alarm'),
          BottomNavigationBarItem(
            icon: Icon(Icons.access_time),
            label: 'Clock',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.timer), label: 'Timer'),
        ],
      ),
    );
  }
}

class ClockPage extends StatefulWidget {
  const ClockPage({super.key});

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> {
  late Timer _timer;
  String _currentTime = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    final now = DateTime.now();
    final formatted = DateFormat('hh:mm:ss a').format(now);
    setState(() => _currentTime = formatted);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        _currentTime,
        style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class AlarmPage extends StatelessWidget {
  const AlarmPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Alarm Page', style: TextStyle(fontSize: 28)),
    );
  }
}

class TimerPage extends StatelessWidget {
  const TimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Timer Page', style: TextStyle(fontSize: 28)),
    );
  }
}
