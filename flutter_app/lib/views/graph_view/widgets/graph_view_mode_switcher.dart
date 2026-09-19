import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

enum GraphViewMode { graph, list }

/// Segmented mode switcher for toggling between the interactive 2D canvas
/// and the information-dense categorized research list.
class GraphViewModeSwitcher extends StatelessWidget {
  final GraphViewMode currentMode;
  final ValueChanged<GraphViewMode> onModeChanged;
  final bool isDark;
  final bool isCompact;

  const GraphViewModeSwitcher({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
    required this.isDark,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark
        ? AppTheme.darkCard.withValues(alpha: 0.90)
        : AppTheme.lightSurface.withValues(alpha: 0.95);
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final activeBgColor = isDark
        ? AppTheme.darkBorder
        : AppTheme.uiBlueSoft;
    final activeTextColor = isDark
        ? AppTheme.darkTextPrimary
        : AppTheme.uiBlue;
    final inactiveTextColor = isDark
        ? AppTheme.darkTextSecondary
        : const Color(0xFF64748B);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption(
            mode: GraphViewMode.graph,
            label: 'Graph',
            icon: Icons.account_tree_outlined,
            activeBgColor: activeBgColor,
            activeTextColor: activeTextColor,
            inactiveTextColor: inactiveTextColor,
          ),
          _buildOption(
            mode: GraphViewMode.list,
            label: 'List',
            icon: Icons.format_list_bulleted_rounded,
            activeBgColor: activeBgColor,
            activeTextColor: activeTextColor,
            inactiveTextColor: inactiveTextColor,
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required GraphViewMode mode,
    required String label,
    IconData? icon,
    Widget? customIcon,
    required Color activeBgColor,
    required Color activeTextColor,
    required Color inactiveTextColor,
  }) {
    final isSelected = currentMode == mode;

    return Tooltip(
      message: '$label View',
      child: InkWell(
        onTap: () => onModeChanged(mode),
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 7 : 9,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: isSelected ? activeBgColor : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              customIcon ??
                  Icon(
                    icon,
                    size: 14,
                    color: isSelected ? activeTextColor : inactiveTextColor,
                  ),
              if (!isCompact) ...[
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? activeTextColor : inactiveTextColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
