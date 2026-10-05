import 'package:flutter/material.dart';

class TodayProgressCard extends StatelessWidget {
  final int totalTasks;
  final int completedTasks;
  final int pendingTasks;

  const TodayProgressCard({
    super.key,
    required this.totalTasks,
    required this.completedTasks,
    required this.pendingTasks,
  });

  @override
  Widget build(BuildContext context) {
    final int displayTotal = totalTasks;
    final int displayCompleted = completedTasks;
    final int displayPending = pendingTasks;
    final double percent =
        displayTotal > 0 ? (displayCompleted / displayTotal).clamp(0.0, 1.0) : 0.0;
    final int displayPercent = (percent * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B), // Dark card matching Screenshot 2
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's Progress",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              // Circular progress ring
              SizedBox(
                width: 96,
                height: 96,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 90,
                      height: 90,
                      child: CircularProgressIndicator(
                        value: percent,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor: const Color(0xFF2C2D35),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFA3E635), // Lime green accent from screenshot
                        ),
                      ),
                    ),
                    Text(
                      '$displayPercent%',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 28),
              // Stats list
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatRow(
                      icon: Icons.assignment_outlined,
                      count: displayTotal,
                      label: 'Total Task',
                    ),
                    const SizedBox(height: 10),
                    _buildStatRow(
                      icon: Icons.task_alt_rounded,
                      count: displayCompleted,
                      label: 'Completed Task',
                    ),
                    const SizedBox(height: 10),
                    _buildStatRow(
                      icon: Icons.timelapse_rounded,
                      count: displayPending,
                      label: 'Pending Task',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow({
    required IconData icon,
    required int count,
    required String label,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: const Color(0xFF27272A),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: const Color(0xFFA1A1AA)),
        ),
        const SizedBox(width: 10),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: Color(0xFFA1A1AA),
            ),
          ),
        ),
      ],
    );
  }
}
