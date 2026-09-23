import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/services/hive_service.dart';
import '../../cubits/graph/graph_cubit.dart';
import '../../cubits/graph/graph_state.dart';
import '../../cubits/library/library_cubit.dart';
import '../../cubits/notification/notification_cubit.dart';
import '../../cubits/notification/notification_state.dart';
import '../graph_view/connected_graph_view.dart';
import 'paper_graph_mark.dart';

/// Minimalist iOS / Pro-app style in-app notification banner.
///
/// Follows modern Apple HIG and pro productivity app aesthetics (Linear, Things 3):
/// - Neutral monochrome palette (obsidian dark / pure warm white light).
/// - Deferential, non-intrusive presentation without neon borders or flashy progress bars.
/// - Unmistakable tactile action and fluid swipe-to-dismiss.
class NotificationToastOverlay extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  const NotificationToastOverlay({
    super.key,
    required this.child,
    this.navigatorKey,
  });

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
  bool _isPaused = false;
  DateTime? _toastShownAt;

  static const Duration _toastDuration = Duration(milliseconds: 6500);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _offsetAnimation =
        Tween<Offset>(begin: const Offset(0, -0.1), end: Offset.zero).animate(
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
    _isPaused = false;
    _toastShownAt = DateTime.now();

    setState(() {
      _currentToast = toast;
    });

    _animController.forward(from: 0.0);

    _autoDismissTimer = Timer(_toastDuration, () {
      _hideToast();
    });
  }

  void _pauseTimer() {
    if (_isPaused || _currentToast == null) return;
    _isPaused = true;
    _autoDismissTimer?.cancel();
  }

  void _resumeTimer() {
    if (!_isPaused || _currentToast == null) return;
    _isPaused = false;
    final elapsed = _toastShownAt != null
        ? DateTime.now().difference(_toastShownAt!)
        : Duration.zero;
    final remaining = _toastDuration - elapsed;
    if (remaining.inMilliseconds <= 200) {
      _hideToast();
      return;
    }
    _autoDismissTimer = Timer(remaining, _hideToast);
  }

  void _hideToast() {
    if (!mounted) return;
    _autoDismissTimer?.cancel();
    _animController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _currentToast = null;
          _isPaused = false;
        });
        context.read<NotificationCubit>().dismissToast();
      }
    });
  }

  Future<void> _openRelatedGraph() async {
    final toast = _currentToast;
    final graphId = toast?.relatedGraphId;
    if (graphId == null || graphId.trim().isEmpty) {
      _hideToast();
      return;
    }

    _hideToast();

    // 1. Check LibraryCubit in-memory cache
    var snapshot = context.read<LibraryCubit>().getCachedGraph(graphId);

    // 2. Check local Hive storage
    snapshot ??= HiveService.getCachedGraph(graphId);

    // 3. Check root GraphCubit active state
    if (snapshot == null) {
      final rootState = context.read<GraphCubit>().state;
      if (rootState is GraphLoaded && rootState.snapshot.graphId == graphId) {
        snapshot = rootState.snapshot;
      }
    }

    if (!mounted) return;

    if (snapshot != null) {
      final nav =
          widget.navigatorKey?.currentState ?? Navigator.maybeOf(context);
      if (nav != null) {
        unawaited(
          nav.push(
            MaterialPageRoute(
              builder: (_) => ConnectedGraphView(initialSnapshot: snapshot),
            ),
          ),
        );
        return;
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('This graph is no longer available offline.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  IconData _getTypeIcon(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return Icons.bubble_chart_outlined;
      case NotificationType.warning:
        return Icons.warning_amber_rounded;
      case NotificationType.error:
        return Icons.error_outline_rounded;
      case NotificationType.info:
        return Icons.notifications_none_rounded;
    }
  }

  Color _getStatusDotColor(NotificationType type) {
    switch (type) {
      case NotificationType.success:
        return const Color(0xFF10B981);
      case NotificationType.warning:
        return const Color(0xFFF59E0B);
      case NotificationType.error:
        return const Color(0xFFEF4444);
      case NotificationType.info:
        return const Color(0xFF5269F4);
    }
  }

  String _getCategoryKicker(InAppNotification toast) {
    switch (toast.category) {
      case NotificationCategory.graphReady:
        return toast.type == NotificationType.warning
            ? 'GRAPH READY — LIMITED DATA'
            : 'LITERATURE GRAPH READY';
      case NotificationCategory.researchUpdate:
        return 'RESEARCH UPDATE';
      case NotificationCategory.general:
        return 'NOTIFICATION';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return BlocListener<NotificationCubit, NotificationState>(
      listenWhen: (previous, current) =>
          current.latestToast?.id != previous.latestToast?.id ||
          (previous.latestToast != null && current.latestToast == null),
      listener: (context, state) {
        final toast = state.latestToast;
        if (toast != null) {
          _showToast(toast);
        } else if (_currentToast != null) {
          _hideToast();
        }
      },
      child: Directionality(
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        child: Stack(
          children: [
            widget.child,
            if (_currentToast != null)
              Positioned(
                top: 10,
                left: 14,
                right: 14,
                child: SafeArea(
                  child: SlideTransition(
                    position: _offsetAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Dismissible(
                        key: Key(_currentToast!.id),
                        direction: DismissDirection.horizontal,
                        onDismissed: (_) => _hideToast(),
                        child: Listener(
                          onPointerDown: (_) => _pauseTimer(),
                          onPointerUp: (_) => _resumeTimer(),
                          onPointerCancel: (_) => _resumeTimer(),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _currentToast!.relatedGraphId == null
                                  ? null
                                  : _openRelatedGraph,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  10,
                                  8,
                                  10,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF161618)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0x22FFFFFF)
                                        : const Color(0xFFE5E5EA),
                                    width: 0.75,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withAlpha(
                                        isDark ? 80 : 16,
                                      ),
                                      blurRadius: 20,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    // Minimal monochrome icon badge with status dot
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
                                            borderRadius: BorderRadius.circular(
                                              9,
                                            ),
                                            border: Border.all(
                                              color: isDark
                                                  ? const Color(0x18FFFFFF)
                                                  : const Color(0xFFE5E5EA),
                                              width: 0.5,
                                            ),
                                          ),
                                          child:
                                              _currentToast!.category ==
                                                  NotificationCategory
                                                      .researchUpdate
                                              ? PaperGraphMark(
                                                  size: 18,
                                                  isDark: isDark,
                                                )
                                              : Icon(
                                                  _getTypeIcon(
                                                    _currentToast!.type,
                                                  ),
                                                  size: 18,
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
                                              color: _getStatusDotColor(
                                                _currentToast!.type,
                                              ),
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
                                    const SizedBox(width: 11),
                                    // Content
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _getCategoryKicker(_currentToast!),
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.7,
                                              color: isDark
                                                  ? const Color(0xFFA1A1AA)
                                                  : const Color(0xFF71717A),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _currentToast!.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? Colors.white
                                                  : const Color(0xFF1C1C1E),
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            _currentToast!.message,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              height: 1.25,
                                              color: isDark
                                                  ? const Color(0xFF8E8E93)
                                                  : const Color(0xFF636366),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Minimal iOS-style CTA & dismiss icon
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_currentToast!.relatedGraphId !=
                                            null) ...[
                                          InkWell(
                                            onTap: _openRelatedGraph,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 4,
                                                  ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'Open',
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: isDark
                                                          ? Colors.white
                                                          : const Color(
                                                              0xFF1C1C1E,
                                                            ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 1),
                                                  Icon(
                                                    Icons.chevron_right_rounded,
                                                    size: 16,
                                                    color: isDark
                                                        ? const Color(
                                                            0xFFA1A1AA,
                                                          )
                                                        : const Color(
                                                            0xFF8E8E93,
                                                          ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Container(
                                            width: 0.75,
                                            height: 18,
                                            margin: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            color: isDark
                                                ? const Color(0x1EFFFFFF)
                                                : const Color(0xFFE5E5EA),
                                          ),
                                        ],
                                        InkWell(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          onTap: _hideToast,
                                          child: Padding(
                                            padding: const EdgeInsets.all(4.0),
                                            child: Icon(
                                              Icons.close_rounded,
                                              size: 16,
                                              color: isDark
                                                  ? const Color(0xFF71717A)
                                                  : const Color(0xFF8E8E93),
                                            ),
                                          ),
                                        ),
                                      ],
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
              ),
          ],
        ),
      ),
    );
  }
}
