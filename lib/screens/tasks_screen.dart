import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import '../core/config/api_config.dart';
import '../models/task_item.dart';
import '../core/constants/app_constants.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> with TickerProviderStateMixin {
  List<TaskItem> _tasks = [];
  String _selectedFilter = 'all'; // all, pending, completed
  late TabController _tabController;

  final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiConfig.baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
  ));

  final List<String> _categories = ['All', 'Work', 'Personal', 'Urgent'];
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSampleTasks();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadSampleTasks() {
    _loadTasksFromBackend();
  }

  Future<void> _loadTasksFromBackend() async {
    try {
      // Call your backend to get tasks
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

        setState(() {
          _tasks = tasksJson.map((taskData) {
            return TaskItem(
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
          }).toList();
        });

        print('✅ Loaded ${_tasks.length} tasks from backend');
      }
    } catch (e) {
      print('❌ Error loading tasks: $e');
      // Keep the sample tasks as fallback
      _loadSampleTasksFallback();
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

// Keep sample tasks as fallback
  void _loadSampleTasksFallback() {
    // Your existing hardcoded tasks code as fallback
    setState(() {
      _tasks = [
        TaskItem(
          id: '1',
          title: 'Complete project presentation',
          description: 'Prepare slides for quarterly review',
          priority: 'high',
          category: 'work',
          dueDate: DateTime.now().add(const Duration(days: 2)),
          progress: 0.7,
          tags: ['presentation', 'quarterly'],
        ),
        // ... other sample tasks
      ];
    });
  }

  List<TaskItem> get _filteredTasks {
    List<TaskItem> filtered = _tasks;

    // Filter by completion status
    switch (_selectedFilter) {
      case 'pending':
        filtered = filtered.where((task) => !task.isCompleted).toList();
        break;
      case 'completed':
        filtered = filtered.where((task) => task.isCompleted).toList();
        break;
    }

    // Filter by category
    if (_selectedCategory != 'All') {
      filtered = filtered.where((task) =>
      task.category.toLowerCase() == _selectedCategory.toLowerCase()).toList();
    }

    // Sort by priority and due date
    filtered.sort((a, b) {
      if (a.isCompleted != b.isCompleted) {
        return a.isCompleted ? 1 : -1; // Completed tasks go to bottom
      }

      // Sort by priority (high -> medium -> low)
      final priorityOrder = {'high': 0, 'medium': 1, 'low': 2};
      final priorityComparison = priorityOrder[a.priority]!.compareTo(
          priorityOrder[b.priority]!);

      if (priorityComparison != 0) return priorityComparison;

      // Then by due date (sooner first)
      if (a.dueDate != null && b.dueDate != null) {
        return a.dueDate!.compareTo(b.dueDate!);
      }

      return 0;
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme
          .of(context)
          .colorScheme
          .surface,
      appBar: AppBar(
        title: const Text('Tasks'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
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
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _showSearchDialog,
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterOptions,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateTaskBottomSheet,
        icon: const Icon(Icons.add_task),
        label: const Text('New Task'),
        backgroundColor: Theme
            .of(context)
            .colorScheme
            .primary,
      ).animate().scale(delay: 600.ms),
      body: Column(
        children: [
          // Stats Card
          _buildStatsCard().animate().slideY(begin: -0.2, duration: 400.ms),

          // Category Filter
          _buildCategoryFilter().animate().slideX(
              begin: -0.2, duration: 500.ms),

          // Tasks List
          Expanded(
            child: _buildTasksList(),
          ),
        ],
      ),
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

  Widget _buildCategoryFilter() {
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
              backgroundColor: Theme
                  .of(context)
                  .colorScheme
                  .surface,
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
                    .onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          );
        },
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
            style: Theme
                .of(context)
                .textTheme
                .titleMedium
                ?.copyWith(
              color: Theme
                  .of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms);
  }

  Widget _buildTaskCard(TaskItem task, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppConstants.spacingM),
      elevation: 0,
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
                                style: Theme
                                    .of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  decoration: task.isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: task.isCompleted
                                      ? Theme
                                      .of(context)
                                      .colorScheme
                                      .onSurfaceVariant
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),

                  // More options
                  PopupMenuButton(
                    itemBuilder: (context) =>
                    [
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
                    onSelected: (value) =>
                        _handleTaskAction(value as String, task),
                  ),
                ],
              ),

              // Task metadata
              const SizedBox(height: AppConstants.spacingM),
              Row(
                children: [
                  // Category chip
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: task.priorityColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      task.category,
                      style: Theme
                          .of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(
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
                          ? Theme
                          .of(context)
                          .colorScheme
                          .error
                          : Theme
                          .of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
                    const SizedBox(width: AppConstants.spacingS),
                    Text(
                      task.dueStatus,
                      style: Theme
                          .of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                        color: task.isOverdue
                            ? Theme
                            .of(context)
                            .colorScheme
                            .error
                            : Theme
                            .of(context)
                            .colorScheme
                            .onSurfaceVariant,
                        fontWeight: task.isOverdue ? FontWeight.w600 : null,
                      ),
                    ),
                  ],

                  const Spacer(),

                  // Progress indicator
                  if (task.progress > 0 && !task.isCompleted) ...[
                    Text(
                      '${(task.progress * 100).round()}%',
                      style: Theme
                          .of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                        color: Theme
                            .of(context)
                            .colorScheme
                            .primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingS),
                    SizedBox(
                      width: 40,
                      height: 4,
                      child: LinearProgressIndicator(
                        value: task.progress,
                        backgroundColor: Theme
                            .of(context)
                            .colorScheme
                            .outline
                            .withOpacity(0.2),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme
                              .of(context)
                              .colorScheme
                              .primary,
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
    ).animate(delay: (index * 100).ms).slideX(begin: 0.2).fadeIn();
  }

  // Task Actions
  void _toggleTaskCompletion(TaskItem task) {
    setState(() {
      final index = _tasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _tasks[index] = task.copyWith(
          isCompleted: !task.isCompleted,
          progress: !task.isCompleted ? 1.0 : task.progress,
        );
      }
    });
    // TODO: Update in database via backend
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

  void _deleteTask(TaskItem task) {
    showDialog(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: const Text('Delete Task'),
            content: Text('Delete "${task.title}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _tasks.removeWhere((t) => t.id == task.id);
                  });
                  Navigator.pop(context);
                  // TODO: Delete from database
                },
                style: TextButton.styleFrom(
                  foregroundColor: Theme
                      .of(context)
                      .colorScheme
                      .error,
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
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
                              style: Theme
                                  .of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            if (selectedDueDate != null) ...[
                              Text(
                                '${selectedDueDate!.day}/${selectedDueDate!
                                    .month}/${selectedDueDate!.year}',
                                style: Theme
                                    .of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                  color: Theme
                                      .of(context)
                                      .colorScheme
                                      .primary,
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
                                onPressed: () =>
                                    _selectDueDate(context, setModalState,
                                        selectedDueDate),
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

  void _selectDueDate(BuildContext context, StateSetter setModalState,
      DateTime? currentDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: currentDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            datePickerTheme: DatePickerThemeData(
              backgroundColor: Theme
                  .of(context)
                  .colorScheme
                  .surface,
              headerBackgroundColor: Theme
                  .of(context)
                  .colorScheme
                  .primaryContainer,
              headerForegroundColor: Theme
                  .of(context)
                  .colorScheme
                  .onPrimaryContainer,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setModalState(() {
        // Set selectedDueDate in the modal state
      });
      setState(() {
        // Update the main widget state if needed
      });
    }
  }

  void _saveTask(String title,
      String description,
      String priority,
      String category,
      DateTime? dueDate,
      TaskItem? existingTask,) {
    if (existingTask == null) {
      // Create new task
      final newTask = TaskItem(
        id: DateTime
            .now()
            .millisecondsSinceEpoch
            .toString(),
        title: title,
        description: description,
        priority: priority,
        category: category,
        dueDate: dueDate,
      );

      setState(() {
        _tasks.add(newTask);
      });
    } else {
      // Update existing task
      setState(() {
        final index = _tasks.indexWhere((t) => t.id == existingTask.id);
        if (index != -1) {
          _tasks[index] = existingTask.copyWith(
            title: title,
            description: description,
            priority: priority,
            category: category,
            dueDate: dueDate,
          );
        }
      });
    }
    // TODO: Save to database via backend
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
}

