import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
    // Sample tasks with different priorities and categories
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
        TaskItem(
          id: '2',
          title: 'Grocery shopping',
          description: 'Buy essentials for the week',
          priority: 'low',
          category: 'personal',
          dueDate: DateTime.now().add(const Duration(days: 1)),
          progress: 0.0,
          tags: ['shopping', 'weekly'],
        ),
        TaskItem(
          id: '3',
          title: 'Review code submissions',
          description: 'Check and approve team code',
          priority: 'medium',
          category: 'work',
          dueDate: DateTime.now().add(const Duration(hours: 6)),
          progress: 0.3,
          tags: ['code', 'review'],
        ),
        TaskItem(
          id: '4',
          title: 'Gym workout',
          description: 'Evening cardio session',
          priority: 'medium',
          category: 'personal',
          isCompleted: true,
          progress: 1.0,
          tags: ['fitness', 'health'],
        ),
        TaskItem(
          id: '5',
          title: 'Fix critical bug',
          description: 'Database connection issue',
          priority: 'high',
          category: 'urgent',
          dueDate: DateTime.now().add(const Duration(hours: 3)),
          progress: 0.1,
          tags: ['bug', 'critical'],
        ),
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
      final priorityComparison = priorityOrder[a.priority]!.compareTo(priorityOrder[b.priority]!);

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
      backgroundColor: Theme.of(context).colorScheme.surface,
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
        backgroundColor: Theme.of(context).colorScheme.primary,
      ).animate().scale(delay: 600.ms),
      body: Column(
        children: [
          // Stats Card
          _buildStatsCard().animate().slideY(begin: -0.2, duration: 400.ms),

          // Category Filter
          _buildCategoryFilter().animate().slideX(begin: -0.2, duration: 500.ms),

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
        padding: AppConstants.cardPadding,
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
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Task Overview',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacingS),
                      Text(
                        '$completedTasks of $totalTasks completed',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Center(
                    child: Text(
                      '${(completionRate * 100).round()}%',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacingM),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'Pending',
                    pendingTasks.toString(),
                    Icons.pending_actions,
                    Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(width: AppConstants.spacingM),
                Expanded(
                  child: _buildStatItem(
                    'Completed',
                    completedTasks.toString(),
                    Icons.check_circle,
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
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
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
            color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
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
    ).animate(delay: (index * 100).ms).slideX(begin: 0.2).fadeIn();
  }

// ... Continue with the rest of the methods (create task, edit, delete, etc.)

