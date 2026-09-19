import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_theme.dart';
import '../../cubits/library/library_cubit.dart';
import '../../cubits/notification/notification_cubit.dart';
import '../../cubits/notification/notification_state.dart';
import '../graph_view/connected_graph_view.dart';
import '../research_monitoring/graph_updates_view.dart';

/// BottomSheet showing notification history and actions.
class NotificationsSheet extends StatelessWidget {
  const NotificationsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BlocProvider.value(
        value: context.read<NotificationCubit>(),
        child: const NotificationsSheet(),
      ),
    );
  }

  String _formatTimestamp(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _getTypeColor(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return const Color(0xFF10B981);
      case NotificationType.warning:
        return const Color(0xFFF59E0B);
      case NotificationType.error:
        return const Color(0xFFEF4444);
      case NotificationType.info:
        return const Color(0xFF3B82F6);
    }
  }

  IconData _getTypeIcon(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return Icons.check_circle_rounded;
      case NotificationType.warning:
        return Icons.warning_amber_rounded;
      case NotificationType.error:
        return Icons.error_outline_rounded;
      case NotificationType.info:
        return Icons.notifications_active_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cubit = context.read<NotificationCubit>();

    return BlocBuilder<NotificationCubit, NotificationState>(
      builder: (context, state) {
        final notifications = state.notifications;
        final unreadCount = notifications.where((n) => !n.isRead).length;

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.78,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.darkCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_outlined, size: 22),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Notifications',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF27272A)
                              : const Color(0xFF18181B),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$unreadCount',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (notifications.isNotEmpty) ...[
                      if (unreadCount > 0)
                        TextButton(
                          onPressed: () {
                            for (final n in notifications) {
                              if (!n.isRead) cubit.markAsRead(n.id);
                            }
                          },
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          child: const Text(
                            'Read all',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ),
                      IconButton(
                        tooltip: 'Clear all',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                        onPressed: () => cubit.clearAll(),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),

              // Content list
              if (notifications.isEmpty)
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 40,
                        horizontal: 24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_none_rounded,
                            size: 54,
                            color: isDark ? Colors.white30 : Colors.black26,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'All caught up!',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Updates about your graphs will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white38 : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: notifications.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final notif = notifications[index];
                      final color = _getTypeColor(notif.type);

                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          if (!notif.isRead) cubit.markAsRead(notif.id);
                          if (notif.relatedGraphId != null) {
                            Navigator.of(context).pop();
                            if (notif.category ==
                                NotificationCategory.researchUpdate) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => GraphUpdatesView(
                                    localGraphId: notif.relatedGraphId!,
                                    graphTitle: 'Saved graph',
                                  ),
                                ),
                              );
                              return;
                            }

                            final snapshot = context
                                .read<LibraryCubit>()
                                .getCachedGraph(notif.relatedGraphId!);
                            if (snapshot != null) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ConnectedGraphView(
                                    initialSnapshot: snapshot,
                                  ),
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'This graph is no longer available offline.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? (notif.isRead
                                      ? AppTheme.darkSurface.withValues(alpha: 0.5)
                                      : const Color(0xFF161618))
                                : (notif.isRead
                                      ? const Color(0xFFF8FAFC)
                                      : Colors.white),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0x22FFFFFF)
                                  : const Color(0xFFE5E5EA),
                              width: 0.75,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF242426)
                                          : const Color(0xFFF2F2F7),
                                      borderRadius: BorderRadius.circular(9),
                                      border: Border.all(
                                        color: isDark
                                            ? const Color(0x18FFFFFF)
                                            : const Color(0xFFE5E5EA),
                                        width: 0.5,
                                      ),
                                    ),
                                    child: Icon(
                                      _getTypeIcon(notif.type),
                                      size: 17,
                                      color: isDark
                                          ? Colors.white
                                          : const Color(0xFF1C1C1E),
                                    ),
                                  ),
                                  Positioned(
                                    top: -2,
                                    right: -2,
                                    child: Container(
                                      width: 7,
                                      height: 7,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isDark
                                              ? const Color(0xFF161618)
                                              : Colors.white,
                                          width: 1.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            notif.title,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: notif.isRead
                                                  ? FontWeight.w500
                                                  : FontWeight.w600,
                                              color: isDark
                                                  ? Colors.white
                                                  : const Color(0xFF0F172A),
                                            ),
                                          ),
                                        ),
                                        Text(
                                          _formatTimestamp(notif.timestamp),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: isDark
                                                ? const Color(0xFFA1A1AA)
                                                : const Color(0xFF71717A),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      notif.message,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? const Color(0xFF8E8E93)
                                            : const Color(0xFF636366),
                                      ),
                                    ),
                                    if (notif.relatedGraphId != null) ...[
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.account_tree_outlined,
                                            size: 13,
                                            color: isDark
                                                ? const Color(0xFFA1A1AA)
                                                : const Color(0xFF71717A),
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            'Tap to view graph',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? const Color(0xFFA1A1AA)
                                                  : const Color(0xFF71717A),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (!notif.isRead) ...[
                                const SizedBox(width: 8),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF2563EB),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
