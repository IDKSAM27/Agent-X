import 'package:flutter/material.dart';
import '../models/scheduler_model.dart';
import '../services/scheduler_service.dart';
import 'create_schedule_screen.dart';
import 'package:intl/intl.dart';

class SchedulerHomeScreen extends StatefulWidget {
  const SchedulerHomeScreen({super.key});

  @override
  State<SchedulerHomeScreen> createState() => _SchedulerHomeScreenState();
}

class _SchedulerHomeScreenState extends State<SchedulerHomeScreen> {
  final SchedulerService _schedulerService = SchedulerService();
  List<Schedule> _schedules = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final schedules = await _schedulerService.getSchedules();
      setState(() {
        _schedules = schedules;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSchedule(int id) async {
    try {
      await _schedulerService.deleteSchedule(id);
      _loadSchedules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Schedule deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting schedule: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scheduler'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateScheduleScreen()),
          );
          if (result == true) {
            _loadSchedules();
          }
        },
        label: const Text('New Schedule'),
        icon: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _schedules.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.calendar_today_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 16),
                          Text(
                            'No schedules found',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text('Upload your timetable or create a new schedule'),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _schedules.length,
                      itemBuilder: (context, index) {
                        final schedule = _schedules[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            onTap: () {
                               // TODO: Navigate to details view
                               _showScheduleDetails(schedule);
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.calendar_month,
                                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          schedule.name,
                                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        Text(
                                          '${schedule.type.toUpperCase()} • ${schedule.items.length} items',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                        if (schedule.createdAt != null)
                                            Text(
                                              'Created: ${DateFormat.yMMMd().format(DateTime.parse(schedule.createdAt!))}',
                                              style: Theme.of(context).textTheme.bodySmall,
                                            )
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _confirmDelete(schedule),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  void _confirmDelete(Schedule schedule) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Schedule'),
        content: Text('Are you sure you want to delete "${schedule.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (schedule.id != null) {
                _deleteSchedule(schedule.id!);
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showScheduleDetails(Schedule schedule) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
               padding: const EdgeInsets.all(16.0),
               child: Text(schedule.name, style: Theme.of(context).textTheme.headlineSmall),
            ),
             const Divider(),
             Expanded(
               child: ListView.separated(
                 padding: const EdgeInsets.all(16),
                 itemCount: schedule.items.length,
                 separatorBuilder: (context, index) => const Divider(),
                 itemBuilder: (context, index) {
                   final item = schedule.items[index];
                   return ListTile(
                     leading: Text(
                        item.startTime, 
                        style: const TextStyle(fontWeight: FontWeight.bold)
                     ),
                     title: Text(item.subject),
                     subtitle: Text('${item.day} • ${item.type}'),
                     trailing: item.location != null ? Text(item.location!) : null,
                   );
                 },
               ),
             ),
          ],
        ),
      ),
    );
  }
}
