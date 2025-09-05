import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../core/constants/app_constants.dart';

class CalendarResponseCard extends StatefulWidget {
  final Map<String, dynamic> metadata;

  const CalendarResponseCard({super.key, required this.metadata});

  @override
  State<CalendarResponseCard> createState() => _CalendarResponseCardState();
}

class _CalendarResponseCardState extends State<CalendarResponseCard> {
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final action = widget.metadata['action'];

    switch (action) {
      case 'event_created':
        return _buildEventCreatedCard();
      case 'events_listed':
        return _buildEventsListCard();
      case 'empty_calendar':
        return _buildEmptyCalendarCard();
      default:
        return _buildCalendarWidget();
    }
  }

  Widget _buildEventCreatedCard() {
    final event = widget.metadata['event'];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppConstants.spacingS),
      child: Padding(
        padding: AppConstants.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.event_available,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppConstants.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event['title'],
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${event['date']} at ${event['time']}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacingM),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Add to actual calendar
                    },
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: const Text('Add to Calendar'),
                  ),
                ),
                const SizedBox(width: AppConstants.spacingS),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Set reminder
                    },
                    icon: const Icon(Icons.notifications, size: 18),
                    label: const Text('Set Reminder'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsListCard() {
    final events = widget.metadata['events'] as List<dynamic>;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppConstants.spacingS),
      child: Column(
        children: [
          Padding(
            padding: AppConstants.cardPadding,
            child: Row(
              children: [
                Icon(
                  Icons.event,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AppConstants.spacingM),
                Text(
                  'Your Events',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          ...events.map((event) => ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                event['date'].toString().split('-')[2],
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            title: Text(event['title']),
            subtitle: Text('${event['date']} at ${event['time']}'),
            trailing: const Icon(Icons.more_vert, size: 20),
          )).toList(),
        ],
      ),
    );
  }

  Widget _buildEmptyCalendarCard() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppConstants.spacingS),
      child: Padding(
        padding: AppConstants.cardPadding,
        child: Column(
          children: [
            Icon(
              Icons.event_busy,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: AppConstants.spacingM),
            Text(
              'No Events Scheduled',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppConstants.spacingS),
            Text(
              'Your calendar is empty. Would you like to schedule something?',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarWidget() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppConstants.spacingS),
      child: Padding(
        padding: AppConstants.cardPadding,
        child: TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          calendarFormat: CalendarFormat.month,
          startingDayOfWeek: StartingDayOfWeek.monday,
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          calendarStyle: CalendarStyle(
            todayDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            selectedDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
