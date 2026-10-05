import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:personal_memory_os/core/models/event.dart';
import 'package:url_launcher/url_launcher.dart';

class TaskScheduleSection extends StatefulWidget {
  final List<Event> events;
  final ValueChanged<Event> onEventTap;
  final VoidCallback onCalendarTap;

  const TaskScheduleSection({
    super.key,
    required this.events,
    required this.onEventTap,
    required this.onCalendarTap,
  });

  @override
  State<TaskScheduleSection> createState() => _TaskScheduleSectionState();
}

class _TaskScheduleSectionState extends State<TaskScheduleSection> {
  late DateTime _selectedDate;
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
  }

  List<DateTime> _getCurrentWeekDays() {
    final now = DateTime.now();
    // Monday as start of week
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    return List.generate(7, (i) => startOfWeek.add(Duration(days: i)));
  }

  @override
  Widget build(BuildContext context) {
    final weekDays = _getCurrentWeekDays();

    // Filter events for selected date
    final dateEvents = widget.events.where((e) {
      return e.startAt.year == _selectedDate.year &&
          e.startAt.month == _selectedDate.month &&
          e.startAt.day == _selectedDate.day;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: Task Schedule + Calendar button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Task\nSchedule',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                  color: Color(0xFF18181B),
                  letterSpacing: -0.5,
                ),
              ),
              InkWell(
                onTap: widget.onCalendarTap,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE4E4E7)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 14, color: Color(0xFF18181B)),
                      SizedBox(width: 6),
                      Text(
                        'Calendar',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF18181B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Horizontal week date strip
        SizedBox(
          height: 78,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: weekDays.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final date = weekDays[index];
              final isSelected = date.year == _selectedDate.year &&
                  date.month == _selectedDate.month &&
                  date.day == _selectedDate.day;

              return GestureDetector(
                onTap: () => setState(() => _selectedDate = date),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 50,
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF18181B) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: isSelected
                        ? null
                        : Border.all(color: const Color(0xFFE4E4E7), width: 1.2),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        DateFormat('E').format(date),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isSelected ? const Color(0xFFA1A1AA) : const Color(0xFF71717A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : const Color(0xFF18181B),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),

        // Category pills: All, Work, Personal
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              _buildCategoryPill('All', null),
              const SizedBox(width: 8),
              _buildCategoryPill('Work', Icons.work_outline_rounded),
              const SizedBox(width: 8),
              _buildCategoryPill('Personal', Icons.person_outline_rounded),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Timeline Subheader
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.wb_sunny_outlined, size: 14, color: Color(0xFFF59E0B)),
                  SizedBox(width: 6),
                  Text(
                    'Morning',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF18181B),
                    ),
                  ),
                ],
              ),
              Text(
                'Today',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF71717A),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Timeline items list
        if (dateEvents.isEmpty)
          Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Text(
            'Nothing scheduled today.',
            style: const TextStyle(fontSize: 13, color: Color(0xFF71717A)),
          ),
        )
        else
          ...dateEvents.map((e) => _buildEventTimelineItem(e)),
      ],
    );
  }

  Widget _buildCategoryPill(String category, IconData? icon) {
    final isSelected = _selectedCategory == category;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF18181B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? null
              : Border.all(color: const Color(0xFFE4E4E7), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : const Color(0xFF71717A),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              category,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : const Color(0xFF18181B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventTimelineItem(Event event) {
    final timeStr = DateFormat('h:mm\na').format(event.startAt.toLocal());
    final hasUrl = event.eventUrl != null && event.eventUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time column with dot & line
          SizedBox(
            width: 54,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timeStr,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF18181B),
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF18181B),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 1.5,
                  height: 48,
                  margin: const EdgeInsets.only(left: 3.25),
                  color: const Color(0xFFE4E4E7),
                ),
              ],
            ),
          ),
          // Event Card
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFF1F2F6), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF18181B),
                    ),
                  ),
                  if (event.description != null && event.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      event.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF71717A),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMiniAvatarStack(),
                      if (hasUrl)
                        InkWell(
                          onTap: () async {
                            final uri = Uri.tryParse(event.eventUrl!);
                            if (uri != null && await canLaunchUrl(uri)) {
                              await launchUrl(uri);
                            } else {
                              widget.onEventTap(event);
                            }
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.videocam_rounded, size: 14, color: Colors.white),
                                SizedBox(width: 4),
                                Text(
                                  'Meet',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        InkWell(
                          onTap: () => widget.onEventTap(event),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3E8FF),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'In Progress',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF9333EA),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniAvatarStack() {
    return SizedBox(
      width: 52,
      height: 24,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: _buildAvatar(const Color(0xFFF59E0B), 'J'),
          ),
          Positioned(
            left: 14,
            child: _buildAvatar(const Color(0xFF10B981), 'M'),
          ),
          Positioned(
            left: 28,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFF18181B),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              alignment: Alignment.center,
              child: const Text(
                '+4',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(Color color, String letter) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}
