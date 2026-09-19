import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Compact, grouped canvas control dock.
///
/// Combines primary zoom controls and secondary viewport focus actions
/// in a disciplined, unified surface instead of scattered floating buttons.
class GraphFloatingControls extends StatelessWidget {
  final bool isDark;
  final bool isBottomSheetOpen;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetZoom;
  final VoidCallback onOpenPaperList;
  final VoidCallback onToggleBottomSheet;
  final VoidCallback? onFocusSelected;
  final bool hasSelectedNode;

  const GraphFloatingControls({
    super.key,
    required this.isDark,
    required this.isBottomSheetOpen,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetZoom,
    required this.onOpenPaperList,
    required this.onToggleBottomSheet,
    this.onFocusSelected,
    this.hasSelectedNode = false,
  });

  Widget _buildControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? iconColor,
    bool highlight = false,
  }) {
    final activeColor = iconColor ?? (isDark ? AppTheme.darkTextPrimary : const Color(0xFF1E293B));

    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: Material(
        color: highlight
            ? (isDark ? AppTheme.actionPurple.withAlpha(40) : const Color(0xFFEEF2FF))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              icon,
              size: 19,
              color: highlight
                  ? (isDark ? AppTheme.actionPurpleDark : AppTheme.actionPurple)
                  : activeColor,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark
        ? AppTheme.darkCard.withValues(alpha: 0.94)
        : Colors.white.withValues(alpha: 0.96);
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0);
    final dividerColor = isDark ? AppTheme.darkBorder.withAlpha(120) : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 60 : 20),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Primary Zoom In & Out
          _buildControlButton(
            icon: Icons.add_rounded,
            tooltip: 'Zoom In',
            onPressed: onZoomIn,
          ),
          const SizedBox(height: 2),
          _buildControlButton(
            icon: Icons.remove_rounded,
            tooltip: 'Zoom Out',
            onPressed: onZoomOut,
          ),

          // Divider between primary and secondary controls
          Container(
            width: 24,
            height: 1,
            margin: const EdgeInsets.symmetric(vertical: 4),
            color: dividerColor,
          ),

          // Focus Selected Node or Reset
          _buildControlButton(
            icon: Icons.center_focus_strong_rounded,
            tooltip: hasSelectedNode ? 'Focus on Selected Paper' : 'Reset View & Center',
            highlight: hasSelectedNode,
            onPressed: hasSelectedNode && onFocusSelected != null
                ? onFocusSelected!
                : onResetZoom,
          ),

          const SizedBox(height: 2),

          // List View Trigger
          _buildControlButton(
            icon: Icons.list_alt_rounded,
            tooltip: 'Open Categorized Paper List',
            onPressed: onOpenPaperList,
          ),

          const SizedBox(height: 2),

          // Toggle Bottom Sheet Details
          _buildControlButton(
            icon: isBottomSheetOpen
                ? Icons.keyboard_arrow_down_rounded
                : Icons.keyboard_arrow_up_rounded,
            tooltip: isBottomSheetOpen ? 'Hide Details' : 'Show Details',
            onPressed: onToggleBottomSheet,
          ),
        ],
      ),
    );
  }
}
