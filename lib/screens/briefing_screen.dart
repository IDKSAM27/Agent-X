import 'package:flutter/material.dart';
import '../services/briefing_service.dart';
import '../services/voice_service.dart';
import '../services/background_service.dart';
import '../core/notifications/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BriefingScreen extends StatefulWidget {
  const BriefingScreen({super.key});

  @override
  State<BriefingScreen> createState() => _BriefingScreenState();
}

class _BriefingScreenState extends State<BriefingScreen> {
  final BriefingService _briefingService = BriefingService();
  final VoiceService _voiceService = VoiceService();
  
  bool _isLoading = true;
  String? _summary;
  Map<String, dynamic>? _data;
  String? _error;
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _loadBriefing();
    _voiceService.initialize();
  }

  @override
  void dispose() {
    _voiceService.stopSpeaking();
    super.dispose();
  }

  Future<void> _loadBriefing({bool forceRefresh = false}) async {
    try {
      if (forceRefresh) {
        setState(() => _isLoading = true);
      }
      
      final data = await _briefingService.getBriefing(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _summary = data['summary'];
          _data = data['data'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleSpeech() async {
    if (_summary == null) return;

    if (_isSpeaking) {
      await _voiceService.stopSpeaking();
      setState(() => _isSpeaking = false);
    } else {
      setState(() => _isSpeaking = true);
      await _voiceService.speak(_summary!);
    }
  }

  Future<void> _showNotificationScheduler() async {
    // Ensure permissions are granted before scheduling
    await NotificationService().requestPermissions();

    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(), // ...
      builder: (context, child) {
         return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Theme.of(context).colorScheme.surface,
              hourMinuteTextColor: Theme.of(context).colorScheme.onSurface,
              dayPeriodTextColor: Theme.of(context).colorScheme.onSurface,
              dialHandColor: Theme.of(context).colorScheme.primary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (selectedTime != null) {
      // 1. Save Preference
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('briefing_hour', selectedTime.hour);
      await prefs.setInt('briefing_minute', selectedTime.minute);

      // 2. Schedule Notification - DISABLED (Using WorkManager trigger for reliability)
      // await NotificationService().scheduleDailyBriefingNotification(selectedTime);

      // 3. Schedule WorkManager (Targeting the exact time now)
      // We schedule it for the EXACT time the user wants. 
      // WorkManager might delay it slightly, but it will run.
      await BackgroundService().scheduleBriefingFetch(notificationTime: selectedTime);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Daily briefing scheduled for ${selectedTime.format(context)}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Briefing'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.access_time),
            onPressed: _showNotificationScheduler,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : () => _loadBriefing(forceRefresh: true),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 24),
                      _buildSummaryCard(),
                      const SizedBox(height: 24),
                      _buildStatsRow(),
                    ],
                  ),
                ),
      floatingActionButton: !_isLoading && _error == null
          ? FloatingActionButton.extended(
              onPressed: _toggleSpeech,
              icon: Icon(_isSpeaking ? Icons.stop : Icons.volume_up),
              label: Text(_isSpeaking ? 'Stop' : 'Read Aloud'),
            )
          : null,
    );
  }

  Widget _buildHeader() {
    final date = _data?['date'] ?? DateTime.now().toString().split(' ')[0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _getGreeting(),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Here is your briefing for $date',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Text(
          _summary ?? 'No summary available.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.6,
                fontSize: 16,
              ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    final eventsCount = _data?['events_count'] ?? 0;
    final tasksCount = _data?['tasks_count'] ?? 0;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Events',
            eventsCount.toString(),
            Icons.calendar_today,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildStatCard(
            'Priority Tasks',
            tasksCount.toString(),
            Icons.check_circle_outline,
            Colors.orange,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning!';
    } else if (hour < 17) {
      return 'Good Afternoon!';
    } else {
      return 'Good Evening!';
    }
  }
}
