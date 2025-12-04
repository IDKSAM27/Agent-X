import 'package:flutter/material.dart';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import '../core/config/api_config.dart';
import '../models/task_item.dart';
import '../core/constants/app_constants.dart';
import '../core/database/database_helper.dart';
import '../services/sync_service.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';

class TasksScreen extends StatefulWidget {
  final String? highlightTaskId;

  const TasksScreen({super.key, this.highlightTaskId});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> with TickerProviderStateMixin {
  List<TaskItem> _tasks = [];
  String _selectedFilter = 'all';
  late TabController _tabController;

  // NEW: Enhanced search and filtering
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  bool _isSearchActive = false;

  // Advanced filter options
  List<String> _selectedPriorities = [];
  List<String> _selectedCategories = [];
  DateTimeRange? _selectedDateRange;
  double _progressRangeStart = 0.0;
  double _progressRangeEnd = 1.0;
  String _sortBy = 'priority'; // priority, dueDate, title, progress
  bool _sortAscending = false;

  // Highlighting support (existing)
  final ScrollController _scrollController = ScrollController();
  String? _highlightedTaskId;
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

  final List<String> _categories = ['All', 'Work', 'Personal', 'Urgent'];
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

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

    // Set initial highlight task
    _highlightedTaskId = widget.highlightTaskId;

    _syncService.initialize();
    _isOnline = _syncService.isOnline;
    _onlineStatusSubscription = _syncService.onlineStatusStream.listen((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
        if (isOnline) {
          _loadTasksFromBackend();
        }
      }
    });

    _loadTasks();
  }

  @override
  void dispose() {
    _onlineStatusSubscription?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tabController.dispose();
    _scrollController.dispose();
    _highlightAnimationController.dispose();
    super.dispose();
  }

  void _activateSearch() {
    setState(() {
      _isSearchActive = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _exitSearch() {
    setState(() {
      _isSearchActive = false;
      _searchQuery = '';
      _sortBy = 'priority';
    });
    _searchController.clear();
    _searchFocusNode.unfocus();
  }

  void _showAdvancedFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppConstants.radiusL),
            ),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: AppConstants.spacingM),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: AppConstants.paddingM,
                child: Row(
                  children: [
                    Text(
                      'Advanced Filters',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setModalState(() {
                          _clearAllFilters();
                        });
                        setState(() {});
                      },
                      child: const Text('Clear All'),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView(
                  padding: AppConstants.paddingM,
                  children: [
                    _buildPriorityFilter(setModalState),
                    const SizedBox(height: AppConstants.spacingL),

                    _buildCategoryFilter(setModalState),
                    const SizedBox(height: AppConstants.spacingL),

                    _buildDateRangeFilter(setModalState),
                    const SizedBox(height: AppConstants.spacingL),

                    _buildProgressFilter(setModalState),
                    const SizedBox(height: AppConstants.spacingL),

                    _buildQuickFilters(setModalState),
                  ],
                ),
              ),

              // Apply button
              Padding(
                padding: AppConstants.paddingM,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      setState(() {}); // Apply filters
                      Navigator.pop(context);
                    },
                    child: Text('Apply Filters (${_getActiveFilterCount()} active)'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _loadTasks() async {
    await _loadTasksFromLocal();
    if (_isOnline) {
      await _loadTasksFromBackend();
    }
  }

  Future<void> _loadTasksFromLocal() async {
    final data = await _dbHelper.queryAllRows('tasks');
    setState(() {
      _tasks = data.map((item) => TaskItem(
        id: item['id'],
        title: item['title'],
        description: item['description'],
        priority: item['priority'],
        category: item['category'],
        dueDate: item['due_date'] != null ? DateTime.parse(item['due_date']) : null,
        isCompleted: item['is_completed'] == 1,
        progress: item['progress'],
        tags: item['tags'] != null ? List<String>.from(json.decode(item['tags'])) : [],
      )).toList();
    });
  }

  Future<void> _loadTasksFromBackend() async {
    try {
      final response = await _dio.get(
        '/api/tasks',
        options: Options(
          headers: {
            ...ApiConfig.defaultHeaders,
            'Authorization': 'Bearer ${await _getFirebaseToken()}',
          },
        ),
      );

      if (response.statusCode == 200) {
        final List<dynamic> tasksJson = response.data['tasks'] ?? [];

        // Update local database
        for (var taskData in tasksJson) {
           final task = TaskItem(
              id: taskData['id'].toString(),
              title: taskData['title'] ?? '',
              description: taskData['description'] ?? '',
              priority: taskData['priority'] ?? 'medium',
              category: taskData['category'] ?? 'general',
              dueDate: taskData['due_date'] != null
                  ? DateTime.parse(taskData['due_date'])
                  : null,
              isCompleted: (taskData['is_completed'] ?? 0) == 1,
              progress: (taskData['progress'] ?? 0.0).toDouble(),
              tags: taskData['tags'] != null
                  ? List<String>.from(json.decode(taskData['tags']))
                  : [],
            );
            
            await _dbHelper.insert('tasks', {
              'id': task.id,
              'title': task.title,
              'description': task.description,
              'priority': task.priority,
              'category': task.category,
              'due_date': task.dueDate?.toIso8601String(),
              'is_completed': task.isCompleted ? 1 : 0,
              'progress': task.progress,
              'tags': jsonEncode(task.tags),
              'is_synced': 1,
              'last_updated': DateTime.now().toIso8601String(),
            });
        }
        
        // Reload from local to ensure consistency
        await _loadTasksFromLocal();

        print('✅ Loaded ${_tasks.length} tasks from backend and synced to local DB');

        // NEW: Auto-scroll and highlight after data loads
        if (_highlightedTaskId != null) {
          _scrollToHighlightedTask();
        }
      }
    } catch (e) {
      print('❌ Error loading tasks: $e');
    }
  }

  Future<String?> _getFirebaseToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      return await user?.getIdToken();
    } catch (e) {
      print('❌ Error getting Firebase token: $e');
      return null;
    }
  }

  void _scrollToHighlightedTask() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_highlightedTaskId == null) return;

      final filteredTasks = _filteredTasks;
      final targetIndex = filteredTasks.indexWhere((task) => task.id == _highlightedTaskId);

      if (targetIndex == -1) {
        print('⚠️ Task with ID $_highlightedTaskId not found in current filter');
        return;
      }

      // Calculate scroll position
      // Account for: stats card (100px) + category filter (70px) + spacing (16px) + task cards
      const double statsCardHeight = 100.0;
      const double categoryFilterHeight = 70.0;
      const double spacing = 16.0;
      const double taskCardHeight = 120.0; // Approximate task card height

      final double scrollOffset = statsCardHeight + categoryFilterHeight + spacing +
          (targetIndex * (taskCardHeight + AppConstants.spacingM));

      // Scroll to the task
      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          scrollOffset,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );

        // Start highlight animation after scrolling
        await Future.delayed(const Duration(milliseconds: 200));
        _highlightAnimationController.forward();

        // Clear highlight after animation
        Future.delayed(const Duration(milliseconds: 2000), () {
          setState(() {
            _highlightedTaskId = null;
          });
        });
      }
    });
  }

  List<TaskItem> get _filteredTasks {
    List<TaskItem> filtered = List.from(_tasks);

    // 1. Search filter (highest priority)
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((task) {
        return task.title.toLowerCase().contains(query) ||
            task.description.toLowerCase().contains(query) ||
            task.category.toLowerCase().contains(query) ||
            task.tags.any((tag) => tag.toLowerCase().contains(query));
      }).toList();
    }

    // 2. Completion status filter
    switch (_selectedFilter) {
      case 'pending':
        filtered = filtered.where((task) => !task.isCompleted).toList();
        break;
      case 'completed':
        filtered = filtered.where((task) => task.isCompleted).toList();
        break;
    }

    // 3. Priority filter
    if (_selectedPriorities.isNotEmpty) {
      filtered = filtered.where((task) =>
          _selectedPriorities.contains(task.priority)
      ).toList();
    }

    // 4. Category filter (enhanced)
    if (_selectedCategories.isNotEmpty) {
      filtered = filtered.where((task) =>
          _selectedCategories.contains(task.category.toLowerCase())
      ).toList();
    } else if (_selectedCategory != 'All') {
      // Legacy category filter
      filtered = filtered.where((task) =>
      task.category.toLowerCase() == _selectedCategory.toLowerCase()
      ).toList();
    }

    // 5. Date range filter
    if (_selectedDateRange != null) {
      filtered = filtered.where((task) {
        if (task.dueDate == null) return false;
        return task.dueDate!.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) &&
            task.dueDate!.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }

    // 6. Progress range filter
    if (_progressRangeStart > 0.0 || _progressRangeEnd < 1.0) {
      filtered = filtered.where((task) =>
      task.progress >= _progressRangeStart && task.progress <= _progressRangeEnd
      ).toList();
    }

    // 7. Smart sorting
    filtered.sort((a, b) => _compareTasksForSorting(a, b));

    return filtered;
  }

  int _compareTasksForSorting(TaskItem a, TaskItem b) {
    // Completed tasks always go to bottom unless we're viewing completed tab
    if (_selectedFilter != 'completed') {
      if (a.isCompleted != b.isCompleted) {
        return a.isCompleted ? 1 : -1;
      }
    }

    int comparison = 0;

    switch (_sortBy) {
      case 'priority':
        final priorityOrder = {'high': 0, 'medium': 1, 'low': 2};
        comparison = priorityOrder[a.priority]!.compareTo(priorityOrder[b.priority]!);
        break;
      case 'dueDate':
        if (a.dueDate != null && b.dueDate != null) {
          comparison = a.dueDate!.compareTo(b.dueDate!);
        } else if (a.dueDate != null) {
          comparison = -1;
        } else if (b.dueDate != null) {
          comparison = 1;
        }
        break;
      case 'title':
        comparison = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        break;
      case 'progress':
        comparison = a.progress.compareTo(b.progress);
        break;
      case 'relevance':
      // When searching, prioritize matches in title over description
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          final aTitleMatch = a.title.toLowerCase().contains(query);
          final bTitleMatch = b.title.toLowerCase().contains(query);
          if (aTitleMatch && !bTitleMatch) return -1;
          if (!aTitleMatch && bTitleMatch) return 1;
        }
        break;
    }

    return _sortAscending ? comparison : -comparison;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: _isSearchActive 
            ? _buildSearchField() 
            : Row(
                children: [
                  const Text('Tasks'),
                  if (!_isOnline) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.wifi_off, size: 16, color: Theme.of(context).colorScheme.error),
                  ],
                ],
              ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _isSearchActive
            ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _exitSearch,
        )
            : null,
        bottom: _isSearchActive
            ? null
            : TabBar(
          controller: _tabController,
          onTap: (index) {
            setState(() {
              _selectedFilter = ['all', 'pending', 'completed'][index];
            });
          },
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Pending'),
            Tab(text: 'Completed'),
          ],
        ),
        actions: _buildAppBarActions(),
      ),
      floatingActionButton: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 16,
          right: MediaQuery.of(context).padding.right + 16,
        ),
        child: FloatingActionButton(
          onPressed: _showCreateTaskBottomSheet,
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
             await _loadTasksFromBackend();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You are offline. Tasks are loaded from local storage.')),
            );
          }
        },
        child: ListView(
          controller: _scrollController, // NEW: Add scroll controller
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            _buildStatsCard(),
            _buildOriginalCategoryFilter(),
            const SizedBox(height: 16),
            ..._filteredTasks.isEmpty
                ? [_buildEmptyState()]
                : _filteredTasks
                .asMap()
                .entries
                .map((entry) => _buildTaskCard(entry.value, entry.key))
                .toList(),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      autofocus: true,
      decoration: InputDecoration(
        hintText: 'Search tasks, descriptions, tags...',
        border: InputBorder.none,
        hintStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      style: Theme.of(context).textTheme.titleMedium,
      onChanged: (query) {
        setState(() {
          _searchQuery = query;
          _sortBy = query.isEmpty ? 'priority' : 'relevance';
        });
      },
    );
  }

  List<Widget> _buildAppBarActions() {
    if (_isSearchActive) {
      return [
        if (_searchQuery.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              setState(() {
                _searchQuery = '';
                _sortBy = 'priority';
              });
            },
          ),
        IconButton(
          icon: const Icon(Icons.tune),
          onPressed: _showAdvancedFilters,
        ),
      ];
    }

    return [
      IconButton(
        icon: const Icon(Icons.search),
        onPressed: _activateSearch,
      ),
      IconButton(
        icon: const Icon(Icons.tune),
        onPressed: _showAdvancedFilters,
      ),
      IconButton(
        icon: const Icon(Icons.sort),
        onPressed: _showSortOptions,
      ),
    ];
  }

  Widget _buildPriorityFilter(StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Priority',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppConstants.spacingM),
        Wrap(
          spacing: 8,
          children: ['high', 'medium', 'low'].map((priority) {
            final isSelected = _selectedPriorities.contains(priority);
            Color priorityColor = priority == 'high'
                ? Colors.red
                : priority == 'medium'
                ? Colors.orange
                : Colors.green;

            return FilterChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: priorityColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(priority.toUpperCase()),
                ],
              ),
              selected: isSelected,
              onSelected: (selected) {
                setModalState(() {
                  if (selected) {
                    _selectedPriorities.add(priority);
                  } else {
                    _selectedPriorities.remove(priority);
                  }
                });
              },
              backgroundColor: priorityColor.withOpacity(0.1),
              selectedColor: priorityColor.withOpacity(0.2),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildOriginalCategoryFilter() { // Rename this method
    return Container(
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: AppConstants.spacingM),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final isSelected = _selectedCategory == category;

          return Container(
            margin: const EdgeInsets.only(right: AppConstants.spacingS),
            child: FilterChip(
              label: Text(category),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedCategory = category;
                });
              },
              backgroundColor: Theme.of(context).colorScheme.surface,
              selectedColor: Theme.of(context).colorScheme.primaryContainer,
              labelStyle: TextStyle(
                color: isSelected
                    ? Theme.of(context).colorScheme.onPrimaryContainer
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryFilter(StateSetter setModalState) {
    final allCategories = _tasks.map((t) => t.category.toLowerCase()).toSet().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Categories',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppConstants.spacingM),
        Wrap(
          spacing: 8,
          children: allCategories.map((category) {
            final isSelected = _selectedCategories.contains(category);
            final taskCount = _tasks.where((t) => t.category.toLowerCase() == category).length;

            return FilterChip(
              label: Text('$category ($taskCount)'),
              selected: isSelected,
              onSelected: (selected) {
                setModalState(() {
                  if (selected) {
                    _selectedCategories.add(category);
                  } else {
                    _selectedCategories.remove(category);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDateRangeFilter(StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Due Date Range',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (_selectedDateRange != null)
              TextButton(
                onPressed: () {
                  setModalState(() {
                    _selectedDateRange = null;
                  });
                },
                child: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingM),
        OutlinedButton.icon(
          onPressed: () async {
            final DateTimeRange? picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              initialDateRange: _selectedDateRange,
            );

            if (picked != null) {
              setModalState(() {
                _selectedDateRange = picked;
              });
            }
          },
          icon: const Icon(Icons.date_range),
          label: Text(_selectedDateRange == null
              ? 'Select Date Range'
              : '${_selectedDateRange!.start.day}/${_selectedDateRange!.start.month} - ${_selectedDateRange!.end.day}/${_selectedDateRange!.end.month}'
          ),
        ),
      ],
    );
  }

  Widget _buildProgressFilter(StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Progress Range: ${(_progressRangeStart * 100).round()}% - ${(_progressRangeEnd * 100).round()}%',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppConstants.spacingM),
        RangeSlider(
          values: RangeValues(_progressRangeStart, _progressRangeEnd),
          onChanged: (RangeValues values) {
            setModalState(() {
              _progressRangeStart = values.start;
              _progressRangeEnd = values.end;
            });
          },
          divisions: 10,
          labels: RangeLabels(
            '${(_progressRangeStart * 100).round()}%',
            '${(_progressRangeEnd * 100).round()}%',
          ),
        ),
      ],
    );
  }

  Widget _buildQuickFilters(StateSetter setModalState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Filters',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppConstants.spacingM),
        Wrap(
          spacing: 8,
          children: [
            _buildQuickFilterChip('Overdue', Icons.warning, Colors.red, () {
              setModalState(() {
                _selectedDateRange = DateTimeRange(
                  start: DateTime(2020, 1, 1),
                  end: DateTime.now(),
                );
              });
            }),
            _buildQuickFilterChip('Due Today', Icons.today, Colors.orange, () {
              final today = DateTime.now();
              setModalState(() {
                _selectedDateRange = DateTimeRange(
                  start: DateTime(today.year, today.month, today.day),
                  end: DateTime(today.year, today.month, today.day, 23, 59),
                );
              });
            }),
            _buildQuickFilterChip('This Week', Icons.view_week, Colors.blue, () {
              final now = DateTime.now();
              final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
              setModalState(() {
                _selectedDateRange = DateTimeRange(
                  start: startOfWeek,
                  end: startOfWeek.add(const Duration(days: 6)),
                );
              });
            }),
            _buildQuickFilterChip('High Priority', Icons.priority_high, Colors.red, () {
              setModalState(() {
                _selectedPriorities = ['high'];
              });
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickFilterChip(String label, IconData icon, Color color, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: color.withOpacity(0.1),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w500),
    );
  }

  Widget _buildSortOption(String title, String sortKey) {
    final isSelected = _sortBy == sortKey;

    return ListTile(
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSelected) ...[
            IconButton(
              icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
              onPressed: () {
                setState(() {
                  _sortAscending = !_sortAscending;
                });
                Navigator.pop(context);
              },
            ),
            const Icon(Icons.check, color: Colors.green),
          ],
        ],
      ),
      onTap: () {
        setState(() {
          if (_sortBy == sortKey) {
            _sortAscending = !_sortAscending;
          } else {
            _sortBy = sortKey;
            _sortAscending = false;
          }
        });
        Navigator.pop(context);
      },
    );
  }

  Widget _buildStatsCard() {
    final totalTasks = _tasks.length;
    final completedTasks = _tasks.where((task) => task.isCompleted).length;
    final pendingTasks = totalTasks - completedTasks;
    final completionRate = totalTasks > 0 ? (completedTasks / totalTasks) : 0.0;

    return Card(
      margin: AppConstants.paddingM,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(16), // Reduced padding
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.secondaryContainer,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppConstants.radiusL),
        ),
        child: Row( // Changed from Column to Row for horizontal layout
          children: [
            // Left side - Text info
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, // Minimize height
                children: [
                  Text(
                    'Task Overview',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4), // Reduced spacing
                  Text(
                    '$completedTasks of $totalTasks completed',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // Middle - Stats
            Expanded(
              flex: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildCompactStatItem(
                    pendingTasks.toString(),
                    'Pending',
                    Theme.of(context).colorScheme.error,
                  ),
                  _buildCompactStatItem(
                    completedTasks.toString(),
                    'Done',
                    Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),

            // Right side - Circular progress
            Container(
              width: 50, // Smaller circle
              height: 50,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Center(
                child: Text(
                  '${(completionRate * 100).round()}%',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14, // Smaller text
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactStatItem(String value, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 18, // Compact size
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontSize: 11, // Smaller label
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon,
      Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppConstants.radiusM),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppConstants.spacingS),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme
                      .of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  label,
                  style: Theme
                      .of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTasksList() {
    final filteredTasks = _filteredTasks;

    if (filteredTasks.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: EdgeInsets.only(
        left: AppConstants.spacingM,
        right: AppConstants.spacingM,
        top: AppConstants.spacingM,
        bottom: 100, // Space for FAB
      ),
      physics: const BouncingScrollPhysics(),
      itemCount: filteredTasks.length,
      itemBuilder: (context, index) {
        final task = filteredTasks[index];
        return _buildTaskCard(task, index);
      },
    );
  }

  Widget _buildEmptyState() {
    String message;
    IconData icon;

    switch (_selectedFilter) {
      case 'pending':
        message = 'No pending tasks!\nGreat job staying on top of things.';
        icon = Icons.task_alt;
        break;
      case 'completed':
        message = 'No completed tasks yet.\nStart checking some off!';
        icon = Icons.assignment_turned_in;
        break;
      default:
        message = 'No tasks yet.\nCreate your first task to get started!';
        icon = Icons.assignment;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: Theme
                .of(context)
                .colorScheme
                .outline
                .withOpacity(0.5),
          ),
          const SizedBox(height: AppConstants.spacingL),
          Text(
            message,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(TaskItem task, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingM),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          side: BorderSide(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.1),
          ),
        ),
        child: InkWell(
          onTap: () => _showTaskDetails(task),
          borderRadius: BorderRadius.circular(AppConstants.radiusM),
          child: Padding(
            padding: AppConstants.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Task header
                Row(
                  children: [
                    // Priority indicator
                    Container(
                      width: 4,
                      height: 40,
                      decoration: BoxDecoration(
                        color: task.priorityColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingM),

                    // Task content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  task.title,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    decoration: task.isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: task.isCompleted
                                        ? Theme.of(context).colorScheme.onSurfaceVariant
                                        : null,
                                  ),
                                ),
                              ),
                              // Completion checkbox
                              Checkbox(
                                value: task.isCompleted,
                                onChanged: (value) => _toggleTaskCompletion(task),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                          if (task.description.isNotEmpty)
                            Text(
                              task.description,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),

                    // More options
                    PopupMenuButton(
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
                      onSelected: (value) => _handleTaskAction(value as String, task),
                    ),
                  ],
                ),

                // Task metadata (rest of your existing code...)
                const SizedBox(height: AppConstants.spacingM),
                Row(
                  children: [
                    // Category chip and other metadata...
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: task.priorityColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        task.category,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: task.priorityColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    const SizedBox(width: AppConstants.spacingM),

                    // Due date
                    if (task.dueDate != null) ...[
                      Icon(
                        Icons.schedule,
                        size: 16,
                        color: task.isOverdue
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppConstants.spacingS),
                      Text(
                        task.dueStatus,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: task.isOverdue
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: task.isOverdue ? FontWeight.w600 : null,
                        ),
                      ),
                    ],

                    const Spacer(),

                    // Progress indicator
                    if (task.progress > 0 && !task.isCompleted) ...[
                      Text(
                        '${(task.progress * 100).round()}%',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacingS),
                      SizedBox(
                        width: 40,
                        height: 4,
                        child: LinearProgressIndicator(
                          value: task.progress,
                          backgroundColor: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSortOptions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sort Tasks'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSortOption('Priority', 'priority'),
            _buildSortOption('Due Date', 'dueDate'),
            _buildSortOption('Title (A-Z)', 'title'),
            _buildSortOption('Progress', 'progress'),
            if (_searchQuery.isNotEmpty)
              _buildSortOption('Relevance', 'relevance'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Task Actions
  void _toggleTaskCompletion(TaskItem task) async {
    final newStatus = !task.isCompleted;
    final updatedTask = task.copyWith(
      isCompleted: newStatus,
      progress: newStatus ? 1.0 : 0.0,
    );

    // Optimistically update UI and Local DB
    setState(() {
      final index = _tasks.indexWhere((t) => t.id == task.id);
      if (index >= 0) {
        _tasks[index] = updatedTask;
      }
    });

    await _dbHelper.update('tasks', {
      'id': updatedTask.id,
      'is_completed': newStatus ? 1 : 0,
      'progress': updatedTask.progress,
      'is_synced': _isOnline ? 1 : 0,
      'last_updated': DateTime.now().toIso8601String(),
    }, 'id');

    if (!_isOnline) {
      await _dbHelper.addToSyncQueue(
        'task',
        'update',
        task.id,
        jsonEncode({'is_completed': newStatus ? 1 : 0, 'progress': updatedTask.progress}),
      );
      return;
    }

    try {
      final token = await _getFirebaseToken();
      final response = await _dio.post(
        '/api/tasks/${task.id}/complete',
        data: {'completed': newStatus},
        options: Options(
            headers: {
              ...ApiConfig.defaultHeaders,
              'Authorization': 'Bearer $token'
            }
        ),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        print('✅ Task completion updated successfully');
      } else {
        throw Exception('Backend returned error');
      }

    } catch (e) {
      print('❌ Error updating task: $e');
      // We don't revert UI here because we want to keep the local change
      // and retry syncing later.
      
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Synced failed, queued for later: $e'),
          backgroundColor: Colors.orange,
        ),
      );
       
       // Add to sync queue on failure if not already there (though we checked _isOnline)
       // This handles case where _isOnline was true but request failed
       await _dbHelper.addToSyncQueue(
        'task',
        'update',
        task.id,
        jsonEncode({'is_completed': newStatus ? 1 : 0, 'progress': updatedTask.progress}),
      );
       await _dbHelper.update('tasks', {'is_synced': 0}, 'id');
    }
  }



  void _handleTaskAction(String action, TaskItem task) {
    switch (action) {
      case 'edit':
        _showEditTaskBottomSheet(task);
        break;
      case 'delete':
        _deleteTask(task);
        break;
    }
  }

  void _deleteTask(TaskItem task) async {
    // Optimistic delete
    setState(() {
      _tasks.removeWhere((t) => t.id == task.id);
    });
    
    // Mark as deleted in local DB (soft delete) or remove if not synced yet
    // For simplicity, we'll just delete from local and queue a delete op
    await _dbHelper.delete('tasks', task.id);

    if (!_isOnline) {
      await _dbHelper.addToSyncQueue('task', 'delete', task.id, '{}');
      return;
    }

    try {
      final token = await _getFirebaseToken();
      final response = await _dio.delete(
        '/api/tasks/${task.id}',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        print('✅ Task deleted successfully');
      }
    } catch (e) {
      print('❌ Error deleting task: $e');
      // Queue for retry
      await _dbHelper.addToSyncQueue('task', 'delete', task.id, '{}');
    }
  }

// Task Details Modal
  void _showTaskDetails(TaskItem task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          Container(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery
                  .of(context)
                  .padding
                  .bottom + 24,
            ),
            decoration: BoxDecoration(
              color: Theme
                  .of(context)
                  .colorScheme
                  .surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppConstants.radiusL),
              ),
            ),
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
                      color: Theme
                          .of(context)
                          .colorScheme
                          .outline
                          .withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spacingL),

                // Task title with completion status
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.title,
                        style: Theme
                            .of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: task.isCompleted ? TextDecoration
                              .lineThrough : null,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: task.isCompleted
                            ? Colors.green.withOpacity(0.1)
                            : task.priorityColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        task.isCompleted ? 'Completed' : task.priority
                            .toUpperCase(),
                        style: Theme
                            .of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(
                          color: task.isCompleted ? Colors.green : task
                              .priorityColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                // Description
                if (task.description.isNotEmpty) ...[
                  const SizedBox(height: AppConstants.spacingM),
                  Text(
                    task.description,
                    style: Theme
                        .of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(
                      color: Theme
                          .of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
                  ),
                ],

                const SizedBox(height: AppConstants.spacingL),

                // Task metadata
                _buildTaskDetailRow(
                  Icons.category,
                  'Category',
                  task.category.toUpperCase(),
                ),

                if (task.dueDate != null)
                  _buildTaskDetailRow(
                    Icons.schedule,
                    'Due Date',
                    task.dueStatus,
                    isOverdue: task.isOverdue,
                  ),

                if (task.progress > 0 && !task.isCompleted)
                  _buildTaskDetailRow(
                    Icons.trending_up,
                    'Progress',
                    '${(task.progress * 100).round()}%',
                  ),

                if (task.tags.isNotEmpty) ...[
                  const SizedBox(height: AppConstants.spacingM),
                  Text(
                    'Tags',
                    style: Theme
                        .of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(
                      color: Theme
                          .of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingS),
                  Wrap(
                    spacing: 8,
                    children: task.tags.map((tag) =>
                        Chip(
                          label: Text(
                            tag,
                            style: Theme
                                .of(context)
                                .textTheme
                                .labelSmall,
                          ),
                          backgroundColor: Theme
                              .of(context)
                              .colorScheme
                              .secondaryContainer,
                        )).toList(),
                  ),
                ],

                const SizedBox(height: AppConstants.spacingL),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _showEditTaskBottomSheet(task);
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit'),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingM),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          _toggleTaskCompletion(task);
                          Navigator.pop(context);
                        },
                        icon: Icon(task.isCompleted ? Icons.undo : Icons.check),
                        label: Text(task.isCompleted ? 'Undo' : 'Complete'),
                        style: FilledButton.styleFrom(
                          backgroundColor: task.isCompleted
                              ? Theme
                              .of(context)
                              .colorScheme
                              .secondary
                              : Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildTaskDetailRow(IconData icon, String label, String value,
      {bool isOverdue = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacingM),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isOverdue
                ? Theme
                .of(context)
                .colorScheme
                .error
                : Theme
                .of(context)
                .colorScheme
                .onSurfaceVariant,
          ),
          const SizedBox(width: AppConstants.spacingM),
          Text(
            label,
            style: Theme
                .of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(
              color: Theme
                  .of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: Theme
                .of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(
              fontWeight: FontWeight.w600,
              color: isOverdue ? Theme
                  .of(context)
                  .colorScheme
                  .error : null,
            ),
          ),
        ],
      ),
    );
  }

// Create/Edit Task Bottom Sheet
  void _showCreateTaskBottomSheet() {
    _showTaskBottomSheet();
  }

  void _showEditTaskBottomSheet(TaskItem task) {
    _showTaskBottomSheet(existingTask: task);
  }

  void _showTaskBottomSheet({TaskItem? existingTask}) {
    final titleController = TextEditingController(
        text: existingTask?.title ?? '');
    final descriptionController = TextEditingController(
        text: existingTask?.description ?? '');
    String selectedPriority = existingTask?.priority ?? 'medium';
    String selectedCategory = existingTask?.category ?? 'work';
    DateTime? selectedDueDate = existingTask?.dueDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (context) =>
          StatefulBuilder(
            builder: (context, setModalState) =>
                Container(
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 24,
                    bottom: MediaQuery
                        .of(context)
                        .viewInsets
                        .bottom + 24,
                  ),
                  decoration: BoxDecoration(
                    color: Theme
                        .of(context)
                        .colorScheme
                        .surface,
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
                              color: Theme
                                  .of(context)
                                  .colorScheme
                                  .outline
                                  .withOpacity(0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppConstants.spacingL),

                        // Title
                        Text(
                          existingTask == null ? 'Create Task' : 'Edit Task',
                          style: Theme
                              .of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppConstants.spacingL),

                        // Task Title Field
                        TextFormField(
                          controller: titleController,
                          decoration: InputDecoration(
                            labelText: 'Task Title',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusM),
                            ),
                            prefixIcon: const Icon(Icons.task),
                          ),
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: AppConstants.spacingM),

                        // Description Field
                        TextFormField(
                          controller: descriptionController,
                          decoration: InputDecoration(
                            labelText: 'Description (Optional)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                  AppConstants.radiusM),
                            ),
                            prefixIcon: const Icon(Icons.description),
                          ),
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                        const SizedBox(height: AppConstants.spacingL),

                        // Priority Selection
                        Text(
                          'Priority',
                          style: Theme
                              .of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppConstants.spacingM),
                        Row(
                          children: ['low', 'medium', 'high'].map((priority) {
                            final isSelected = selectedPriority == priority;
                            Color priorityColor;
                            switch (priority) {
                              case 'high':
                                priorityColor = Colors.red;
                                break;
                              case 'medium':
                                priorityColor = Colors.orange;
                                break;
                              default:
                                priorityColor = Colors.green;
                            }

                            return Expanded(
                              child: Container(
                                margin: EdgeInsets.only(
                                  right: priority != 'high' ? AppConstants
                                      .spacingS : 0,
                                ),
                                child: FilterChip(
                                  label: Text(priority.toUpperCase()),
                                  selected: isSelected,
                                  onSelected: (selected) {
                                    setModalState(() {
                                      selectedPriority = priority;
                                    });
                                  },
                                  backgroundColor: priorityColor.withOpacity(
                                      0.1),
                                  selectedColor: priorityColor.withOpacity(0.2),
                                  labelStyle: TextStyle(
                                    color: priorityColor,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: AppConstants.spacingL),

                        // Category Selection
                        Text(
                          'Category',
                          style: Theme
                              .of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppConstants.spacingM),
                        Wrap(
                          spacing: 8,
                          children: ['work', 'personal', 'urgent'].map((
                              category) {
                            final isSelected = selectedCategory == category;
                            return FilterChip(
                              label: Text(category.toUpperCase()),
                              selected: isSelected,
                              onSelected: (selected) {
                                setModalState(() {
                                  selectedCategory = category;
                                });
                              },
                              backgroundColor: Theme
                                  .of(context)
                                  .colorScheme
                                  .surfaceVariant,
                              selectedColor: Theme
                                  .of(context)
                                  .colorScheme
                                  .primaryContainer,
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? Theme
                                    .of(context)
                                    .colorScheme
                                    .onPrimaryContainer
                                    : Theme
                                    .of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: AppConstants.spacingL),

                        // Due Date Selection
                        Row(
                          children: [
                            Text(
                              'Due Date',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            if (selectedDueDate != null) ...[
                              Text(
                                '${selectedDueDate!.day}/${selectedDueDate!.month}/${selectedDueDate!.year}',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  setModalState(() {
                                    selectedDueDate = null;
                                  });
                                },
                                icon: const Icon(Icons.clear),
                                iconSize: 20,
                              ),
                            ] else
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final DateTime? picked = await _selectDueDateAsync(context, selectedDueDate);
                                  if (picked != null) {
                                    setModalState(() {
                                      selectedDueDate = picked;
                                    });
                                  }
                                },
                                icon: const Icon(Icons.calendar_today),
                                label: const Text('Set Due Date'),
                              ),
                          ],
                        ),

                        const SizedBox(height: AppConstants.spacingL),

                        // Action Buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                ),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: AppConstants.spacingM),
                            Expanded(
                              child: FilledButton(
                                onPressed: () {
                                  if (titleController.text.isNotEmpty) {
                                    _saveTask(
                                      titleController.text,
                                      // timeController.text, // Add this (even though we don't use it for tasks)
                                      descriptionController.text,
                                      selectedPriority,
                                      selectedCategory,
                                      selectedDueDate,
                                      existingTask,
                                    );
                                    Navigator.pop(context);
                                  }
                                },
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                ),
                                child: Text(existingTask == null
                                    ? 'Create'
                                    : 'Save'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  Future<DateTime?> _selectDueDateAsync(BuildContext context, DateTime? currentDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: currentDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Theme.of(context).colorScheme.surface,
              headerBackgroundColor: Theme.of(context).colorScheme.primaryContainer,
              headerForegroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          child: child!,
        );
      },
    );

    return picked;
  }


  void _saveTask(
      String title,
      String description,
      String priority,
      String category,
      DateTime? dueDate,
      TaskItem? existingTask,
      ) async {
    
    final isNew = existingTask == null;
    final String taskId = existingTask?.id ?? const Uuid().v4();
    
    final newTask = TaskItem(
      id: taskId,
      title: title,
      description: description,
      priority: priority,
      category: category,
      dueDate: dueDate,
      isCompleted: existingTask?.isCompleted ?? false,
      progress: existingTask?.progress ?? 0.0,
      tags: existingTask?.tags ?? [],
    );

    // Optimistic UI update
    setState(() {
      if (isNew) {
        _tasks.add(newTask);
      } else {
        final index = _tasks.indexWhere((t) => t.id == taskId);
        if (index >= 0) {
          _tasks[index] = newTask;
        }
      }
    });

    // Save to local DB
    if (isNew) {
      await _dbHelper.insert('tasks', {
        'id': newTask.id,
        'title': newTask.title,
        'description': newTask.description,
        'priority': newTask.priority,
        'category': newTask.category,
        'due_date': newTask.dueDate?.toIso8601String(),
        'is_completed': newTask.isCompleted ? 1 : 0,
        'progress': newTask.progress,
        'tags': jsonEncode(newTask.tags),
        'is_synced': _isOnline ? 1 : 0,
        'last_updated': DateTime.now().toIso8601String(),
      });
    } else {
       await _dbHelper.update('tasks', {
        'id': newTask.id,
        'title': newTask.title,
        'description': newTask.description,
        'priority': newTask.priority,
        'category': newTask.category,
        'due_date': newTask.dueDate?.toIso8601String(),
        'is_completed': newTask.isCompleted ? 1 : 0,
        'progress': newTask.progress,
        'tags': jsonEncode(newTask.tags),
        'is_synced': _isOnline ? 1 : 0,
        'last_updated': DateTime.now().toIso8601String(),
      }, 'id');
    }

    final taskData = {
      'id': taskId, // Send ID to backend
      'title': title,
      'description': description,
      'priority': priority,
      'category': category,
      'due_date': dueDate?.toIso8601String(),
    };

    if (!_isOnline) {
       await _dbHelper.addToSyncQueue(
        'task',
        isNew ? 'create' : 'update',
        taskId,
        jsonEncode(taskData),
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
        // CREATE
        response = await _dio.post(
          '/api/tasks',
          data: taskData,
          options: Options(
            headers: {
              ...ApiConfig.defaultHeaders,
              'Authorization': 'Bearer $token',
            },
          ),
        );
      } else {
        // UPDATE
        response = await _dio.put(
          '/api/tasks/$taskId',
          data: taskData,
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
           final newId = response.data['task_id'].toString();
           // Update local DB with new ID
           await _dbHelper.updateEntityId('tasks', taskId, newId);
           
           // Update in-memory list
           setState(() {
             final index = _tasks.indexWhere((t) => t.id == taskId);
             if (index >= 0) {
               _tasks[index] = _tasks[index].copyWith(id: newId);
             }
           });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isNew ? 'Task created!' : 'Task updated!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception(response.data['message'] ?? 'Failed to save task');
      }

    } catch (e) {
      print('❌ Error saving task: $e');
      
      // Queue for retry
       await _dbHelper.addToSyncQueue(
        'task',
        isNew ? 'create' : 'update',
        taskId,
        jsonEncode(taskData),
      );
       await _dbHelper.update('tasks', {'is_synced': 0}, 'id');

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

// Search and Filter
  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text('Search Tasks'),
            content: TextField(
              decoration: const InputDecoration(
                labelText: 'Search by title or description',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (query) {
                // TODO: Implement real-time search
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          Container(
            decoration: BoxDecoration(
              color: Theme
                  .of(context)
                  .colorScheme
                  .surface,
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
                    color: Theme
                        .of(context)
                        .colorScheme
                        .outline
                        .withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: AppConstants.spacingL),

                ListTile(
                  leading: const Icon(Icons.sort),
                  title: const Text('Sort by Priority'),
                  onTap: () {
                    // TODO: Implement sorting
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.filter_list),
                  title: const Text('Filter by Category'),
                  onTap: () {
                    // TODO: Implement category filter
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Filter by Due Date'),
                  onTap: () {
                    // TODO: Implement due date filter
                    Navigator.pop(context);
                  },
                ),

                const SizedBox(height: AppConstants.spacingL),
              ],
            ),
          ),
    );
  }

  void _clearAllFilters() {
    _selectedPriorities.clear();
    _selectedCategories.clear();
    _selectedDateRange = null;
    _progressRangeStart = 0.0;
    _progressRangeEnd = 1.0;
  }
  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedPriorities.isNotEmpty) count++;
    if (_selectedCategories.isNotEmpty) count++;
    if (_selectedDateRange != null) count++;
    if (_progressRangeStart > 0.0 || _progressRangeEnd < 1.0) count++;
    return count;
  }
}

