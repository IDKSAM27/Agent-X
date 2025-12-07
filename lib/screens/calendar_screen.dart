import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:logger/logger.dart';
import '../core/constants/app_constants.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/config/api_config.dart';
import '../core/database/database_helper.dart';
import '../services/sync_service.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';

class CalendarScreen extends StatefulWidget {
  final String? highlightEventId; // NEW: Event ID to highlight
  final DateTime? highlightDate; // NEW: Optional date to focus on

  const CalendarScreen({super.key, this.highlightEventId, this.highlightDate});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> with TickerProviderStateMixin {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  // Event form state variables
  TextEditingController? _eventTitleController;
  TimeOfDay? _eventSelectedTime;
  String? _eventSelectedCategory;
  bool? _eventIsAllDay;

  // NEW: Highlighting support
  final ScrollController _eventsScrollController = ScrollController();
  String? _highlightedEventId;
  late AnimationController _highlightAnimationController;
  late Animation<double> _highlightAnimation;

  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 90),
    receiveTimeout: const Duration(seconds: 90),
  ));

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final SyncService _syncService = SyncService();
  StreamSubscription<bool>? _onlineStatusSubscription;
  bool _isOnline = false;

  var logger = Logger();

  // Sample events data
  final Map<DateTime, List<Map<String, dynamic>>> _events = {};

  @override
  void initState() {
    super.initState();

    // NEW: Initialize highlight animation
    _highlightAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _highlightAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _highlightAnimationController,
      curve: Curves.easeInOut,
    ));

    // NEW: Set initial highlight event and date
    _highlightedEventId = widget.highlightEventId;

    // Set initial selected day and focused day
    if (widget.highlightDate != null) {
      _selectedDay = widget.highlightDate;
      _focusedDay = widget.highlightDate!;
    } else {
      _selectedDay = DateTime.now();
    }

    _syncService.initialize();
    _isOnline = _syncService.isOnline;
    _onlineStatusSubscription = _syncService.onlineStatusStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
        if (isOnline) {
          _loadEventsFromBackend();
        }
      }
    });

    _loadEvents();
  }

  @override
  void dispose() {
    _onlineStatusSubscription?.cancel();
    _eventTitleController?.dispose();
    _eventsScrollController.dispose(); // NEW: Dispose scroll controller
    _highlightAnimationController.dispose(); // NEW: Dispose animation
    super.dispose();
  }

  Future<TimeOfDay?> _showEnhancedTimePicker(BuildContext context, TimeOfDay initialTime) async {
    return await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Theme.of(context).colorScheme.surface,
              hourMinuteTextColor: Theme.of(context).colorScheme.onSurface,
              dayPeriodTextColor: Theme.of(context).colorScheme.onSurface,
              dialHandColor: Theme.of(context).colorScheme.primary,
              dialBackgroundColor: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
              hourMinuteColor: Theme.of(context).colorScheme.primaryContainer,
              dayPeriodBorderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
            ),
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
            child: child!,
          ),
        );
      },
    );
  }

  Future<String?> _getFirebaseToken() async {
    final user = FirebaseAuth.instance.currentUser;
    return await user?.getIdToken();
  }

  Future<void> _loadEvents() async {
    await _loadEventsFromLocal();
    if (_isOnline) {
      await _loadEventsFromBackend();
    }
  }

  Future<void> _loadEventsFromLocal() async {
    final data = await _dbHelper.queryAllRows('events');
    setState(() {
      _events.clear();
      for (final e in data) {
        if (e['is_deleted'] == 1) continue; // Skip deleted events
        
        try {
          final date = DateTime.parse(e['start_time']);
          final normalized = DateTime(date.year, date.month, date.day);
          final eventMap = {
            'id': e['id'],
            'title': e['title'],
            'description': e['description'],
            'time': _formatTimeFromDateTime(e['start_time']),
            'type': e['category'] ?? 'general',
            'color': _getCategoryColor(e['category'] ?? 'general'),
            'isAllDay': e['is_all_day'] == 1,
            'start_time': e['start_time'], // Keep original string for editing
          };
          _events[normalized] = (_events[normalized] ?? [])..add(eventMap);
        } catch (e) {
          print('⚠️ Error parsing event date: $e');
          continue;
        }
      }
    });
  }

  Future<void> _loadEventsFromBackend() async {
    try {
      final token = await _getFirebaseToken();
      final response = await _dio.get(
        '/api/events',
        options: Options(
          headers: {
            ...ApiConfig.defaultHeaders,
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final List<dynamic> eventsJson = response.data['events'] ?? [];
        
        // Update local DB
        for (final e in eventsJson) {
           await _dbHelper.insert('events', {
            'id': e['id'].toString(),
            'title': e['title'],
            'description': e['description'],
            'start_time': e['start_time'],
            'end_time': e['end_time'], // Assuming backend returns this
            'category': e['category'],
            'is_all_day': (e['is_all_day'] ?? false) ? 1 : 0,
            'is_synced': 1,
            'is_deleted': 0,
            'last_updated': DateTime.now().toIso8601String(),
          });
        }
        
        await _loadEventsFromLocal();

        print('✅ Loaded ${_events.values.expand((e) => e).length} events from backend and synced to local');

        // NEW: Auto-scroll and highlight after data loads
        if (_highlightedEventId != null) {
          _scrollToHighlightedEvent();
        }
      }
    } catch (e) {
      print('❌ Error loading events: $e');
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'work': return Colors.blue;
      case 'personal': return Colors.green;
      case 'meeting': return Colors.orange;
      case 'appointment': return Colors.purple;
      default: return Colors.grey;
    }
  }

  void _scrollToHighlightedEvent() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_highlightedEventId == null) return;

      // Find the event and its date
      DateTime? eventDate;
      Map<String, dynamic>? targetEvent;

      for (final entry in _events.entries) {
        final foundEvent = entry.value.firstWhere(
              (event) => event['id'].toString() == _highlightedEventId,
          orElse: () => {},
        );
        if (foundEvent.isNotEmpty) {
          eventDate = entry.key;
          targetEvent = foundEvent;
          break;
        }
      }

      if (eventDate == null || targetEvent == null) {
        print('⚠️ Event with ID $_highlightedEventId not found');
        return;
      }

      // NEW: Update selected day to show the event
      setState(() {
        _selectedDay = eventDate;
        _focusedDay = eventDate!;
      });

      // Wait for rebuild, then scroll to the event in the events list
      await Future.delayed(const Duration(milliseconds: 300));

      final eventsForDay = _getEventsForDay(_selectedDay!);
      final targetIndex = eventsForDay.indexWhere((event) => event['id'].toString() == _highlightedEventId);

      if (targetIndex == -1) {
        print('⚠️ Event not found in selected day events');
        return;
      }

      // Calculate scroll position for events list
      const double eventCardHeight = 80.0; // Approximate event card height
      final double scrollOffset = targetIndex * (eventCardHeight + AppConstants.spacingM);

      // Scroll to the event
      if (_eventsScrollController.hasClients) {
        await _eventsScrollController.animateTo(
          scrollOffset,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );

        // Start highlight animation after scrolling
        await Future.delayed(const Duration(milliseconds: 200));
        _highlightAnimationController.forward();

        // Clear highlight after animation
        Future.delayed(const Duration(milliseconds: 2000), () {
          setState(() {
            _highlightedEventId = null;
          });
        });
      }
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
      // FIX 3: Handle keyboard overflow with resizeToAvoidBottomInset
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Calendar'),
            if (!_isOnline) ...[
              const SizedBox(width: 8),
              Icon(Icons.wifi_off, size: 16, color: Theme.of(context).colorScheme.error),
            ],
          ],
        ),
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
      // FAB positioned properly
      floatingActionButton: AnimatedContainer(
        duration: const Duration(milliseconds: 200), // Shorter animation
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 16,
          right: MediaQuery.of(context).padding.right + 16,
        ),
        child: FloatingActionButton(
          onPressed: _showCreateEventDialog,
          backgroundColor: Theme.of(context).colorScheme.primary,
          heroTag: null,
          child: const Icon(Icons.add),
        ),
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: RefreshIndicator(
        onRefresh: () async {
          if (_isOnline) {
             await _syncService.syncData(context: context);
             await _loadEventsFromBackend();
          } else {
             ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You are offline. Events are loaded from local storage.')),
            );
          }
        },
        child: ListView(
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

                // Optimize callbacks
                onDaySelected: (selectedDay, focusedDay) {
                  if (!isSameDay(_selectedDay, selectedDay)) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                  }
                },
                onFormatChanged: (format) {
                  if (_calendarFormat != format) {
                    setState(() {
                      _calendarFormat = format;
                    });
                  }
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
                  // Basic marker decoration
                  markerDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary,
                    shape: BoxShape.circle,
                  ),
                  // FIX 1: Allow more markers to show multiple event dots
                  markersMaxCount: 5, // Show up to 5 dots for multiple events
                  markerSize: 6.0,
                  markerMargin: const EdgeInsets.symmetric(horizontal: 0.5),
                ),
                headerStyle: HeaderStyle(
                  titleCentered: true,
                  formatButtonVisible: false,
                  titleTextStyle: Theme.of(context).textTheme.titleLarge!,
                ),

                // FIX 1: Custom marker builder for multiple event indicators
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, day, events) {
                    // Don't show markers on selected day (like Google Calendar)
                    if (isSameDay(day, _selectedDay)) {
                      return const SizedBox.shrink();
                    }

                    if (events.isNotEmpty) {
                      return Positioned(
                        bottom: 1,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                            events.length > 3 ? 3 : events.length, // Max 3 dots
                                (index) => Container(
                              margin: const EdgeInsets.symmetric(horizontal: 0.5),
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: events.length > 3 && index == 2
                                    ? Theme.of(context).colorScheme.primary // Different color for "more" indicator
                                    : Theme.of(context).colorScheme.secondary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),

            // Selected Day Events
            SizedBox(
              height: 400,
              child: _buildSelectedDayEvents(),
            ),
          ],
        )
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
            controller: _eventsScrollController, // NEW: Add scroll controller
            padding: EdgeInsets.only(
              left: AppConstants.spacingM,
              right: AppConstants.spacingM,
              top: 0,
              bottom: 100, // Extra space for FAB
            ),
            physics: const BouncingScrollPhysics(),
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
          // FIX 4: Remove duplicate create button - only keep the FAB
        ],
      ),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event, int index) {
    final isHighlighted = event['id'].toString() == _highlightedEventId;

    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingM),
      decoration: isHighlighted
          ? BoxDecoration(
        borderRadius: BorderRadius.circular(AppConstants.radiusM),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      )
          : null,
      child: Card(
        elevation: 0,
        child: Container(
          decoration: isHighlighted
              ? BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusM),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          )
              : null,
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
        ),
      ),
    );
  }

  void _showCreateEventDialog({Map<String, dynamic>? existingEvent}) {
    // Reset state for new event creation
    _resetEventFormState();

    // If editing an existing event, populate the form fields
    if (existingEvent != null) {
      _eventTitleController = TextEditingController(text: existingEvent['title'] ?? '');
      _eventSelectedTime = _parseTimeString(existingEvent['time']);
      _eventSelectedCategory = existingEvent['type'] ?? 'general';
      _eventIsAllDay = existingEvent['isAllDay'] ?? false;
    } else {
      _eventTitleController = TextEditingController();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      isDismissible: true,
      builder: (context) => _buildCreateEventBottomSheet(),
    );
  }

  Widget _buildCreateEventBottomSheet({Map<String, dynamic>? existingEvent}) {
    // FIXED: Only initialize once, don't clear on rebuilds
    if (_eventTitleController == null) {
      _eventTitleController = TextEditingController();
      _eventSelectedTime = TimeOfDay(hour: DateTime.now().hour + 1, minute: 0);
      _eventSelectedCategory = 'general';
      _eventIsAllDay = false;

      // Only set text for existing events during initial creation
      if (existingEvent != null) {
        _eventTitleController!.text = existingEvent['title'] ?? '';
        _eventSelectedTime = _parseTimeString(existingEvent['time']);
        _eventSelectedCategory = existingEvent['type'] ?? 'general';
        _eventIsAllDay = existingEvent['isAllDay'] ?? false;
      }
    }

    return StatefulBuilder(
      builder: (context, setModalState) => Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppConstants.radiusL),
          ),
        ),
        child: SingleChildScrollView(
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

              // Title
              Text(
                existingEvent == null ? 'Create Event' : 'Edit Event',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppConstants.spacingL),

              // Event Title Field
              TextFormField(
                controller: _eventTitleController,
                decoration: InputDecoration(
                  labelText: 'Event Title',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusM),
                  ),
                  prefixIcon: const Icon(Icons.event),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: AppConstants.spacingL),

              // All Day Toggle
              Row(
                children: [
                  Text(
                    'All Day Event',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Switch(
                    value: _eventIsAllDay!,
                    onChanged: (value) {
                      setModalState(() {
                        _eventIsAllDay = value;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spacingM),

              // Time Selection (only show if not all day)
              if (!_eventIsAllDay!) ...[
                Row(
                  children: [
                    Text(
                      'Time',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(AppConstants.radiusM),
                      ),
                      child: Text(
                        _eventSelectedTime!.format(context),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        final TimeOfDay? picked = await _showEnhancedTimePicker(context, _eventSelectedTime!);
                        if (picked != null) {
                          setModalState(() {
                            _eventSelectedTime = picked;
                          });
                        }
                      },
                      icon: const Icon(Icons.schedule),
                    ),
                  ],
                ),
                const SizedBox(height: AppConstants.spacingM),

                // Quick Time Presets
                Text(
                  'Quick Times',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppConstants.spacingM),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildQuickTimeChip(context, '9:00 AM', const TimeOfDay(hour: 9, minute: 0), _eventSelectedTime!, (time) {
                      setModalState(() {
                        _eventSelectedTime = time;
                      });
                    }),
                    _buildQuickTimeChip(context, '12:00 PM', const TimeOfDay(hour: 12, minute: 0), _eventSelectedTime!, (time) {
                      setModalState(() {
                        _eventSelectedTime = time;
                      });
                    }),
                    _buildQuickTimeChip(context, '2:00 PM', const TimeOfDay(hour: 14, minute: 0), _eventSelectedTime!, (time) {
                      setModalState(() {
                        _eventSelectedTime = time;
                      });
                    }),
                    _buildQuickTimeChip(context, '5:00 PM', const TimeOfDay(hour: 17, minute: 0), _eventSelectedTime!, (time) {
                      setModalState(() {
                        _eventSelectedTime = time;
                      });
                    }),
                  ],
                ),
                const SizedBox(height: AppConstants.spacingL),
              ],

              // Category Selection
              Text(
                'Category',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppConstants.spacingM),
              Wrap(
                spacing: 8,
                children: ['general', 'work', 'personal', 'meeting', 'appointment'].map((category) {
                  final isSelected = _eventSelectedCategory == category;
                  Color categoryColor;
                  IconData categoryIcon;

                  switch (category) {
                    case 'work':
                      categoryColor = Colors.blue;
                      categoryIcon = Icons.work;
                      break;
                    case 'personal':
                      categoryColor = Colors.green;
                      categoryIcon = Icons.person;
                      break;
                    case 'meeting':
                      categoryColor = Colors.orange;
                      categoryIcon = Icons.groups;
                      break;
                    case 'appointment':
                      categoryColor = Colors.purple;
                      categoryIcon = Icons.schedule;
                      break;
                    default:
                      categoryColor = Colors.grey;
                      categoryIcon = Icons.event;
                  }

                  return FilterChip(
                    avatar: Icon(
                      categoryIcon,
                      size: 16,
                      color: isSelected
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : categoryColor,
                    ),
                    label: Text(category.toUpperCase()),
                    selected: isSelected,
                    onSelected: (selected) {
                      setModalState(() {
                        _eventSelectedCategory = category;
                      });
                    },
                    backgroundColor: categoryColor.withOpacity(0.1),
                    selectedColor: Theme.of(context).colorScheme.primaryContainer,
                    labelStyle: TextStyle(
                      color: isSelected
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : categoryColor,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppConstants.spacingL),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _resetEventFormState();
                        Navigator.pop(context);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingM),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        if (_eventTitleController!.text.isNotEmpty) {
                          final timeString = _eventIsAllDay!
                              ? 'All Day'
                              : _eventSelectedTime!.format(context);

                          _saveEvent(
                            _eventTitleController!.text,
                            timeString,
                            existingEvent,
                            _eventSelectedCategory!,
                          );

                          _resetEventFormState();
                          Navigator.pop(context);
                        }
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(existingEvent == null ? 'Create' : 'Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
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

    return Dialog(
      // FIX 2 & 3: Better dialog configuration for keyboard handling
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              existingEvent == null ? 'Create Event' : 'Edit Event',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppConstants.spacingL),

            // Event Title Field
            TextField(
              controller: titleController,
              autofocus: false, // FIX 2: Don't auto-focus to reduce keyboard lag
              decoration: const InputDecoration(
                labelText: 'Event Title',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.event),
              ),
            ),
            const SizedBox(height: AppConstants.spacingM),

            // Time Field
            TextField(
              controller: timeController,
              decoration: const InputDecoration(
                labelText: 'Time',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.access_time),
              ),
            ),
            const SizedBox(height: AppConstants.spacingL),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AppConstants.spacingM),
                FilledButton(
                  onPressed: () {
                    if (titleController.text.isNotEmpty) {
                      _saveEvent(
                        titleController.text,
                        timeController.text,
                        existingEvent,
                        _eventSelectedCategory!,
                      );
                      Navigator.pop(context);
                    }
                  },
                  child: Text(existingEvent == null ? 'Create' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showEventDetails(Map<String, dynamic> event) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
  Future<void> _saveEvent(String title, String timeString, Map<String, dynamic>? existingEvent, String category,) async {
    final selectedDate = _selectedDay ?? DateTime.now();

    // Parse the time string properly
    final timeOfDay = timeString == 'All Day'
        ? const TimeOfDay(hour: 0, minute: 0)
        : _parseTimeString(timeString);

    final startTime = timeString == 'All Day'
        ? DateTime(selectedDate.year, selectedDate.month, selectedDate.day)
        : DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        timeOfDay.hour,
        timeOfDay.minute
    );
    
    // Simple end time assumption (1 hour duration)
    final endTime = startTime.add(const Duration(hours: 1));

    final isNew = existingEvent == null;
    final String eventId = existingEvent?['id']?.toString() ?? const Uuid().v4();

    // Format dates to match backend expectation (yyyy-MM-dd HH:mm:ss)
    final DateFormat formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
    final String formattedStartTime = formatter.format(startTime);
    final String formattedEndTime = formatter.format(endTime);

    final eventData = {
      "id": eventId,
      "title": title,
      "description": "",
      "start_time": formattedStartTime,
      "end_time": formattedEndTime,
      "category": category,
      "priority": "medium",
      "is_all_day": timeString == 'All Day' ? 1 : 0,
    };
    
    // Save to local DB
    await _dbHelper.insert('events', {
      ...eventData,
      'is_synced': _isOnline ? 1 : 0,
      'is_deleted': 0,
      'last_updated': DateTime.now().toIso8601String(),
    });
    
    await _loadEventsFromLocal();

    if (!_isOnline) {
       await _dbHelper.addToSyncQueue(
        'event',
        isNew ? 'create' : 'update',
        eventId,
        jsonEncode(eventData),
      );
       
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved offline. Will sync when online.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      final token = await _getFirebaseToken();
      Response response;

      if (isNew) {
        // Create new event
        response = await _dio.post(
          '/api/events',
          data: eventData,
          options: Options(
            headers: {
              ...ApiConfig.defaultHeaders,
              'Authorization': 'Bearer $token',
            },
          ),
        );
      } else {
        // Update existing event
        response = await _dio.put(
          '/api/events/$eventId',
          data: eventData,
          options: Options(
            headers: {
              ...ApiConfig.defaultHeaders,
              'Authorization': 'Bearer $token',
            },
          ),
        );
      }

      if (response.statusCode == 200 && response.data['success'] == true) {
        if (isNew) {
           final newId = response.data['event_id'].toString();
           // Update local DB with new ID
           await _dbHelper.updateEntityId('events', eventId, newId);
           
           // Update in-memory list
           // We need to find the event in the map and update its ID
           // Since _events is Map<DateTime, List<Map<String, dynamic>>>, we iterate
           final normalizedDate = _normalizeDate(startTime);
           if (_events.containsKey(normalizedDate)) {
             final eventsList = _events[normalizedDate]!;
             final index = eventsList.indexWhere((e) => e['id'].toString() == eventId);
             if (index >= 0) {
               eventsList[index]['id'] = newId;
               // Reload from local to ensure consistency
               await _loadEventsFromLocal();
             }
           }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isNew ? 'Event created!' : 'Event updated!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error saving event: $e');
      
       // Queue for retry
       await _dbHelper.addToSyncQueue(
        'event',
        isNew ? 'create' : 'update',
        eventId,
        jsonEncode(eventData),
      );
       await _dbHelper.update('events', {'is_synced': 0}, 'id');
       
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed, queued for later: ${e.toString()}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _handleEventAction(String action, Map<String, dynamic> event) {
    switch (action) {
      case 'edit':
      // DON'T reset state for editing - preserve existing data
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          enableDrag: true,
          builder: (context) => _buildCreateEventBottomSheet(existingEvent: event),
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
            onPressed: () async {
              Navigator.pop(context); // Close dialog first
              await _deleteEventFromBackend(event);
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
  void _showTimePicker(BuildContext context, TextEditingController controller) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            // Optimize time picker theme for performance
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Theme.of(context).colorScheme.surface,
              hourMinuteTextColor: Theme.of(context).colorScheme.onSurface,
              dayPeriodTextColor: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formattedTime = picked.format(context);
      controller.text = formattedTime;
    }
  }
  Future<void> _deleteEventFromBackend(Map<String, dynamic> event) async {
    final eventId = event['id'].toString();
    
    // Optimistic delete from local
    await _dbHelper.update('events', {'is_deleted': 1, 'is_synced': _isOnline ? 1 : 0}, 'id'); // Soft delete
    // Or hard delete: await _dbHelper.delete('events', eventId);
    
    await _loadEventsFromLocal();
    
    if (!_isOnline) {
      await _dbHelper.addToSyncQueue('event', 'delete', eventId, '{}');
      return;
    }

    try {
      final token = await _getFirebaseToken();

      final response = await _dio.delete(
        '/api/events/$eventId',
        options: Options(
          headers: {
            ...ApiConfig.defaultHeaders,
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Event deleted!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

    } catch (e) {
      print('❌ Error deleting event: $e');
      // Queue for retry
      await _dbHelper.addToSyncQueue('event', 'delete', eventId, '{}');
      await _dbHelper.update('events', {'is_synced': 0}, 'id');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed, queued for later: ${e.toString()}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // Helper method to parse time string
  TimeOfDay _parseTimeString(String timeStr) {
    try {
      final timeParts = timeStr.split(':');
      int hour = int.parse(timeParts[0]);
      int minute = int.parse(timeParts[1].split(' ')[0]);

      // Handle AM/PM
      if (timeStr.toUpperCase().contains('PM') && hour != 12) {
        hour += 12;
      } else if (timeStr.toUpperCase().contains('AM') && hour == 12) {
        hour = 0;
      }

      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      // Default fallback
      return const TimeOfDay(hour: 10, minute: 0);
    }
  }

  String _formatTimeFromDateTime(String dateTimeStr) {
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return "${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      // Fallback for any parsing errors
      return "00:00";
    }
  }

  Widget _buildQuickTimeChip(BuildContext context, String label, TimeOfDay time, TimeOfDay selectedTime, Function(TimeOfDay) onTimeSelected) {
    final isSelected = time.hour == selectedTime.hour && time.minute == selectedTime.minute;

    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          onTimeSelected(time); // FIX: Call the callback properly
        }
      },
      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
      selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
      labelStyle: TextStyle(
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  void _resetEventFormState() {
    _eventTitleController?.dispose();
    _eventTitleController = null;
    _eventSelectedTime = null;
    _eventSelectedCategory = null;
    _eventIsAllDay = null;
  }
}
