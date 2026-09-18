import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../cubits/notification/notification_cubit.dart';
import '../../cubits/notification/notification_state.dart';
import '../../core/theme/app_theme.dart';
import 'paper_graph_mark.dart';

/// A sleek, floating in-app notification banner overlay.
/// Placed globally via MaterialApp.builder so notifications can be shown
/// anywhere without interrupting navigation or modal flows.
class NotificationToastOverlay extends StatefulWidget {
  final Widget child;

  const NotificationToastOverlay({super.key, required this.child});

  @override
  State<NotificationToastOverlay> createState() =>
      _NotificationToastOverlayState();
}

class _NotificationToastOverlayState extends State<NotificationToastOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _fadeAnimation;

  Timer? _autoDismissTimer;
  InAppNotification? _currentToast;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _offsetAnimation =
        Tween<Offset>(begin: const Offset(0, -0.6), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animController,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _showToast(InAppNotification toast) {
    _autoDismissTimer?.cancel();
    setState(() {
      _currentToast = toast;
    });

    _animController.forward(from: 0.0);

    _autoDismissTimer = Timer(const Duration(seconds: 4), () {
      _hideToast();
    });
  }

  void _hideToast() {
    if (!mounted) return;
    _autoDismissTimer?.cancel();
    _animController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _currentToast = null;
        });
        context.read<NotificationCubit>().dismissToast();
      }
    });
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

    return BlocListener<NotificationCubit, NotificationState>(
      listenWhen: (previous, current) =>
          current.latestToast != null &&
          current.latestToast?.id != previous.latestToast?.id,
      listener: (context, state) {
        final toast = state.latestToast;
        if (toast != null) {
          _showToast(toast);
        }
      },
      child: Directionality(
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        child: Stack(
          children: [
            widget.child,
            if (_currentToast != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: SlideTransition(
                      position: _offsetAnimation,
                      child: FadeTransition(
                        opacity: _fadeAnimation,
                        child: Dismissible(
                          key: Key(_currentToast!.id),
                          direction: DismissDirection.horizontal,
                          onDismissed: (_) => _hideToast(),
                          child: Material(
                            color: Colors.transparent,
                            child: Container(
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppTheme.darkCard.withValues(alpha: 0.96)
                                    : Colors.white.withValues(alpha: 0.97),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _getTypeColor(
                                    _currentToast!.type,
                                  ).withValues(alpha: 0.35),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: isDark ? 0.4 : 0.12,
                                    ),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: _getTypeColor(
                                        _currentToast!.type,
                                      ).withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child:
                                        _currentToast!.category ==
                                            NotificationCategory.researchUpdate
                                        ? PaperGraphMark(
                                            size: 20,
                                            isDark: isDark,
                                          )
                                        : Icon(
                                            _getTypeIcon(
                                              _currentToast!.type,
                                            ),
                                            size: 20,
                                            color: _getTypeColor(
                                              _currentToast!.type,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _currentToast!.title,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: isDark
                                                ? AppTheme.darkTextPrimary
                                                : const Color(0xFF0F172A),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _currentToast!.message,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w400,
                                            color: isDark
                                                ? AppTheme.darkTextSecondary
                                                : const Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: _hideToast,
                                    child: Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                        color: isDark
                                            ? Colors.white54
                                            : Colors.black45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
