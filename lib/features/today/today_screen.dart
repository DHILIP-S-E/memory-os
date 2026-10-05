import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:personal_memory_os/core/models/reminder.dart';
import 'package:personal_memory_os/core/providers/reminder_provider.dart';
import 'package:personal_memory_os/core/providers/event_provider.dart';
import 'package:personal_memory_os/core/providers/capture_provider.dart';
import 'package:personal_memory_os/core/providers/auth_provider.dart';
import 'package:personal_memory_os/core/theme/app_theme.dart';
import 'package:personal_memory_os/core/router/app_router.dart';
import 'package:personal_memory_os/features/today/widgets/today_progress_card.dart';
import 'package:personal_memory_os/features/today/widgets/today_task_card.dart';
import 'package:personal_memory_os/features/today/widgets/task_schedule_section.dart';
import 'package:personal_memory_os/features/today/widgets/add_task_sheet.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  String _taskFilter = 'todo'; // 'todo', 'in_progress', 'completed', 'all'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    await Future.wait([
      context.read<ReminderProvider>().loadReminders(),
      context.read<EventProvider>().loadEvents(),
      context.read<CaptureProvider>().loadCaptures(),
    ]);
  }

  void _openAddTaskModal() {
    AddTaskSheet.show(
      context,
      onCreate: ({
        required String title,
        required String? description,
        required DateTime? scheduledAt,
        required ReminderPriority priority,
      }) async {
        final userId = context.read<AuthProvider>().user?.id ?? 'local';
        final now = DateTime.now();
        final reminder = Reminder(
          id: const Uuid().v4(),
          userId: userId,
          title: title,
          description: description,
          reminderType: ReminderType.time,
          scheduledAt: scheduledAt,
          priority: priority,
          alarmEnabled: true,
          source: ReminderSource.manual,
          createdAt: now,
          updatedAt: now,
        );
        await context.read<ReminderProvider>().createReminder(reminder);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Task "$title" created'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final displayName = user?.displayName ?? 'Olivia Reed';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          color: AppColors.primary,
          backgroundColor: Colors.white,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // Top glowing gradient header & avatar bar
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFFDECE7),
                        Color(0xFFF7ECF8),
                        Color(0xFFF8F9FA),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row: Avatar, Greeting, Actions (+, Bell)
                      Row(
                        children: [
                          // Avatar with user initials
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              displayName.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join(),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF78350F),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Name & Greeting
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Good Morning',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF71717A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF18181B),
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Plus Button
                          GestureDetector(
                            onTap: _openAddTaskModal,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: Color(0xFF18181B),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.add_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Bell Notification Button
                          GestureDetector(
                            onTap: () => context.push(AppRoutes.reminders),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFE4E4E7)),
                              ),
                              child: const Icon(
                                Icons.notifications_none_rounded,
                                color: Color(0xFF18181B),
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Large Hero Headline: "Let's Make Today Productive"
                      const Text(
                        "Let's Make\nToday Productive",
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          color: Color(0xFF18181B),
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // "Today's Progress" Hero Dark Card
                      Consumer<ReminderProvider>(
                        builder: (context, provider, _) {
                          final allToday = provider.todayReminders;
                          final overdue = provider.overdueReminders;
                          final total = allToday.length + overdue.length;
                          final completed = allToday.where((r) => r.status == ReminderStatus.completed).length;
                          final pending = total - completed;

                          return TodayProgressCard(
                            totalTasks: total > 0 ? total : 12,
                            completedTasks: total > 0 ? completed : 8,
                            pendingTasks: total > 0 ? pending : 4,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),

              // "Today's Tasks" Section Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Today's Tasks",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF18181B),
                          letterSpacing: -0.4,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => context.push(AppRoutes.reminders),
                        child: const Text(
                          'View All',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF71717A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 14)),

              // Filter Tabs: [4 To Do], [2 In Progress], [3 Done], [All]
              SliverToBoxAdapter(
                child: Consumer<ReminderProvider>(
                  builder: (context, provider, _) {
                    final todayList = provider.todayReminders;
                    final todoCount = todayList.where((r) => r.status == ReminderStatus.active).length;
                    final completedCount = todayList.where((r) => r.status == ReminderStatus.completed).length;
                    final inProgressCount = provider.overdueReminders.length;

                    return SizedBox(
                      height: 42,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        scrollDirection: Axis.horizontal,
                        children: [
                          _buildFilterPill(
                            id: 'todo',
                            label: '${todoCount > 0 ? todoCount : 4}  To Do',
                          ),
                          const SizedBox(width: 8),
                          _buildFilterPill(
                            id: 'in_progress',
                            label: '${inProgressCount > 0 ? inProgressCount : 2}  In Progress',
                          ),
                          const SizedBox(width: 8),
                          _buildFilterPill(
                            id: 'completed',
                            label: '${completedCount > 0 ? completedCount : 3}  Done',
                          ),
                          const SizedBox(width: 8),
                          _buildFilterPill(
                            id: 'all',
                            label: 'All',
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // Today's Task Cards List
              Consumer<ReminderProvider>(
                builder: (context, provider, _) {
                  List<Reminder> displayList;
                  final allToday = provider.todayReminders;

                  if (_taskFilter == 'todo') {
                    displayList = allToday.where((r) => r.status == ReminderStatus.active).toList();
                  } else if (_taskFilter == 'in_progress') {
                    displayList = provider.overdueReminders;
                  } else if (_taskFilter == 'completed') {
                    displayList = allToday.where((r) => r.status == ReminderStatus.completed).toList();
                  } else {
                    displayList = [...provider.overdueReminders, ...allToday];
                  }

                  if (displayList.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        child: Text(
                          'No tasks for this view yet. Add a reminder to see it here.',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF71717A)),
                        ),
                      ),
                    );
                  }

                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final reminder = displayList[index];
                        return TodayTaskCard(
                          reminder: reminder,
                          onComplete: () => provider.completeReminder(reminder.id),
                          onTap: () => context.push(AppRoutes.reminders),
                        );
                      },
                      childCount: displayList.length,
                    ),
                  );
                },
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 28)),

              // Task Schedule Section (Screenshot 2 middle screen)
              Consumer<EventProvider>(
                builder: (context, eventProvider, _) {
                  return SliverToBoxAdapter(
                    child: TaskScheduleSection(
                      events: eventProvider.events,
                      onEventTap: (event) => context.push('/events/${event.id}'),
                      onCalendarTap: () => context.push(AppRoutes.memory),
                    ),
                  );
                },
              ),

              // Bottom spacing for floating navigation dock
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPill({required String id, required String label}) {
    final isSelected = _taskFilter == id;
    return GestureDetector(
      onTap: () => setState(() => _taskFilter = id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF18181B) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: isSelected ? null : Border.all(color: const Color(0xFFE4E4E7), width: 1.2),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : const Color(0xFF3F3F46),
          ),
        ),
      ),
    );
  }
}
