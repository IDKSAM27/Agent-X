import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants/app_constants.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  // Sample events data (I'll replace with database later)
  final Map<DateTime, List<Map<String, dynamic>>> _events = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _loadSampleEvents();
  }

  void _loadSampleEvents() {
    // Sample events for demo
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final nextWeek = DateTime.now().add(const Duration(days: 7));

    setState(() {
      _events[_normalizeDate(tomorrow)] = [
        {
          'title': 'Team Meeting',
          'time': '10:00 AM',
          'type': 'work',
          'color': Colors.blue,
        },
        {
          'title': 'Lunch Break',
          'time': '12:30 PM',
          'type': 'personal',
          'color': Colors.green,
        },
      ];

      _events[_normalizeDate(nextWeek)] = [
        {
          'title': 'Project Review',
          'time': '2:00 PM',
          'type': 'work',
          'color': Colors.orange,
        },
      ];
    });
  }

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _events[_normalizeDate(day)] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Calendar'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // View switcher buttons
          IconButton(
            icon: Icon(_calendarFormat == CalendarFormat.month
                ? Icons.view_week : Icons.calendar_month),
            onPressed: () {
              setState(() {
                _calendarFormat = _calendarFormat == CalendarFormat.month
                    ? CalendarFormat.week
                    : CalendarFormat.month;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showCalendarMenu,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateEventDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Event'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ).animate().scale(delay: 600.ms),
      body: Column(
        children: [
          // Calendar Widget
          Card(
            margin: AppConstants.paddingM,
            elevation: 0,
            child: TableCalendar<Map<String, dynamic>>(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              eventLoader: _getEventsForDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              onFormatChanged: (format) {
                setState(() {
                  _calendarFormat = format;
                });
              },
              onPageChanged: (focusedDay) {
                _focusedDay = focusedDay;
              },
              calendarStyle: CalendarStyle(
                outsideDaysVisible: false,
                weekendTextStyle: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
                todayDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                markerDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
                  shape: BoxShape.circle,
                ),
              ),
              headerStyle: HeaderStyle(
                titleCentered: true,
                formatButtonVisible: false,
                titleTextStyle: Theme.of(context).textTheme.titleLarge!,
              ),
            ),
          ).animate().slideY(begin: 0.2, duration: 500.ms),

          // Selected Day Events
          Expanded(
            child: _buildSelectedDayEvents(),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedDayEvents() {
    if (_selectedDay == null) {
      return const Center(child: Text('Select a day to view events'));
    }

    final eventsForDay = _getEventsForDay(_selectedDay!);
    final dateString = '${_selectedDay!.day}/${_selectedDay!.month}/${_selectedDay!.year}';

    return Column(
      children: [
        // Date header
        Padding(
          padding: AppConstants.paddingM,
          child: Row(
            children: [
              Icon(
                Icons.event,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: AppConstants.spacingM),
              Text(
                'Events for $dateString',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${eventsForDay.length} events',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        // Events list
        Expanded(
          child: eventsForDay.isEmpty
              ? _buildEmptyEventsView()
              : ListView.builder(
            padding: AppConstants.paddingM,
            itemCount: eventsForDay.length,
            itemBuilder: (context, index) {
              final event = eventsForDay[index];
              return _buildEventCard(event, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyEventsView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy,
            size: 64,
            color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
          ),
          const SizedBox(height: AppConstants.spacingM),
          Text(
            'No events for this day',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppConstants.spacingS),
          Text(
            'Tap the + button to create an event',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppConstants.spacingL),
          OutlinedButton.icon(
            onPressed: _showCreateEventDialog,
            icon: const Icon(Icons.add),
            label: const Text('Create Event'),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms);
  }

  Widget _buildEventCard(Map<String, dynamic> event, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingM),
      child: ListTile(
        leading: Container(
          width: 12,
          height: 40,
          decoration: BoxDecoration(
            color: event['color'] ?? Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        title: Text(
          event['title'],
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Row(
          children: [
            Icon(
              Icons.access_time,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppConstants.spacingS),
            Text(event['time']),
            const SizedBox(width: AppConstants.spacingM),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: (event['color'] ?? Theme.of(context).colorScheme.primary)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                event['type'],
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: event['color'] ?? Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 12),
                  Text('Edit'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 12),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: (value) => _handleEventAction(value as String, event),
        ),
        onTap: () => _showEventDetails(event),
      ),
    ).animate(delay: (index * 100).ms).slideX(begin: 0.2).fadeIn();
  }

  void _showCreateEventDialog() {
    showDialog(
      context: context,
      builder: (context) => _buildEventDialog(),
    );
  }

  void _showEventDetails(Map<String, dynamic> event) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusL),
          ),
        ),
        padding: AppConstants.paddingL,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingL),

            // Event details
            Text(
              event['title'],
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppConstants.spacingM),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppConstants.spacingS),
                Text(event['time']),
                const SizedBox(width: AppConstants.spacingL),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: event['color'],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppConstants.spacingS),
                Text(event['type']),
              ],
            ),
            const SizedBox(height: AppConstants.spacingL),
          ],
        ),
      ),
    );
  }

  Widget _buildEventDialog({Map<String, dynamic>? existingEvent}) {
    final titleController = TextEditingController(
      text: existingEvent?['title'] ?? '',
    );
    final timeController = TextEditingController(
      text: existingEvent?['time'] ?? '10:00 AM',
    );

    return AlertDialog(
      title: Text(existingEvent == null ? 'Create Event' : 'Edit Event'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: titleController,
            decoration: const InputDecoration(
              labelText: 'Event Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AppConstants.spacingM),
          TextField(
            controller: timeController,
            decoration: const InputDecoration(
              labelText: 'Time',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (titleController.text.isNotEmpty) {
              _saveEvent(
                titleController.text,
                timeController.text,
                existingEvent,
              );
              Navigator.pop(context);
            }
          },
          child: Text(existingEvent == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }

  void _saveEvent(String title, String time, Map<String, dynamic>? existingEvent) {
    final normalizedDate = _normalizeDate(_selectedDay ?? DateTime.now());

    setState(() {
      _events[normalizedDate] = _events[normalizedDate] ?? [];

      if (existingEvent == null) {
        // Create new event
        _events[normalizedDate]!.add({
          'title': title,
          'time': time,
          'type': 'work',
          'color': Theme.of(context).colorScheme.primary,
        });
      } else {
        // Update existing event
        final index = _events[normalizedDate]!.indexOf(existingEvent);
        if (index != -1) {
          _events[normalizedDate]![index] = {
            ...existingEvent,
            'title': title,
            'time': time,
          };
        }
      }
    });

    // TODO: Save to database via backend
  }

  void _handleEventAction(String action, Map<String, dynamic> event) {
    switch (action) {
      case 'edit':
        showDialog(
          context: context,
          builder: (context) => _buildEventDialog(existingEvent: event),
        );
        break;
      case 'delete':
        _deleteEvent(event);
        break;
    }
  }

  void _deleteEvent(Map<String, dynamic> event) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Event'),
        content: Text('Delete "${event['title']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                final normalizedDate = _normalizeDate(_selectedDay!);
                _events[normalizedDate]?.remove(event);
              });
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showCalendarMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusL),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: AppConstants.spacingM),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppConstants.spacingL),
            ListTile(
              leading: const Icon(Icons.today),
              title: const Text('Go to Today'),
              onTap: () {
                setState(() {
                  _focusedDay = DateTime.now();
                  _selectedDay = DateTime.now();
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_sync),
              title: const Text('Sync with Google Calendar'),
              subtitle: const Text('Coming soon'),
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: AppConstants.spacingL),
          ],
        ),
      ),
    );
  }
}
