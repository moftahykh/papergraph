import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../widgets/paper_graph_mark.dart';

class GraphErrorView extends StatelessWidget {
  final String message;
  final bool isDark;
  final VoidCallback onRetry;
  final VoidCallback onGoBack;

  const GraphErrorView({
    super.key,
    required this.message,
    required this.isDark,
    required this.onRetry,
    required this.onGoBack,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161618) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? const Color(0x22FFFFFF) : const Color(0xFFE5E5EA),
            width: 0.75,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 50 : 10),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF242426) : const Color(0xFFF2F2F7),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? const Color(0x18FFFFFF) : const Color(0xFFE5E5EA),
                  width: 0.5,
                ),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 24,
                color: isDark ? Colors.white : const Color(0xFF1C1C1E),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Unable to Generate Graph',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppTheme.darkTextPrimary
                    : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppTheme.darkTextSecondary
                    : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: onGoBack,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Go Back'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? Colors.white : const Color(0xFF18181B),
                    foregroundColor: isDark ? const Color(0xFF09090B) : Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class GraphEmptyStateView extends StatelessWidget {
  final bool isDark;
  final VoidCallback onExplore;

  const GraphEmptyStateView({
    super.key,
    required this.isDark,
    required this.onExplore,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurface : AppTheme.lightSurface,
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
              ),
            ),
            child: Center(
              child: PaperGraphMark(size: 56, isDark: isDark),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No Graph Loaded',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark
                  ? AppTheme.darkTextPrimary
                  : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Select a seed paper or enter a DOI to synthesize a new literature graph.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? AppTheme.darkTextSecondary
                  : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onExplore,
            icon: const Icon(Icons.search_rounded, size: 16),
            label: const Text('Explore Literature'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? Colors.white : const Color(0xFF18181B),
              foregroundColor: isDark ? const Color(0xFF09090B) : Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
