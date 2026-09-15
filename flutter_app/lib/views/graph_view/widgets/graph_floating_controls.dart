import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class GraphFloatingControls extends StatelessWidget {
  final bool isDark;
  final bool isBottomSheetOpen;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetZoom;
  final VoidCallback onOpenPaperList;
  final VoidCallback onToggleBottomSheet;

  const GraphFloatingControls({
    super.key,
    required this.isDark,
    required this.isBottomSheetOpen,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetZoom,
    required this.onOpenPaperList,
    required this.onToggleBottomSheet,
  });

  Widget _buildButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard.withValues(alpha: 0.92) : const Color(0xDDFFFFFF),
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 80 : 25),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, size: 20),
        color: isDark ? AppTheme.darkTextPrimary : AppTheme.primaryBlue,
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildButton(
          icon: Icons.add_rounded,
          tooltip: 'Zoom In',
          onPressed: onZoomIn,
        ),
        const SizedBox(height: 8),
        _buildButton(
          icon: Icons.remove_rounded,
          tooltip: 'Zoom Out',
          onPressed: onZoomOut,
        ),
        const SizedBox(height: 8),
        _buildButton(
          icon: Icons.center_focus_strong_rounded,
          tooltip: 'Reset Zoom & Center',
          onPressed: onResetZoom,
        ),
        const SizedBox(height: 8),
        _buildButton(
          icon: Icons.list_alt_rounded,
          tooltip: 'Open Paper List',
          onPressed: onOpenPaperList,
        ),
        const SizedBox(height: 8),
        _buildButton(
          icon: isBottomSheetOpen
              ? Icons.keyboard_arrow_down_rounded
              : Icons.keyboard_arrow_up_rounded,
          tooltip: isBottomSheetOpen ? 'Hide Details' : 'Show Details',
          onPressed: onToggleBottomSheet,
        ),
      ],
    );
  }
}
