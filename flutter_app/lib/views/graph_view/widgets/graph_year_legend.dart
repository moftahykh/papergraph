import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Compact, disciplined scientific graph legend.
///
/// Explains relationship edge types, node semantic rings, size mapping,
/// and publication timeline without visual clutter.
class GraphYearLegend extends StatefulWidget {
  final int minYear;
  final int maxYear;
  final bool isDark;

  const GraphYearLegend({
    super.key,
    required this.minYear,
    required this.maxYear,
    this.isDark = true,
  });

  @override
  State<GraphYearLegend> createState() => _GraphYearLegendState();
}

class _GraphYearLegendState extends State<GraphYearLegend> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bgColor = isDark
        ? AppTheme.darkCard.withValues(alpha: 0.94)
        : Colors.white.withValues(alpha: 0.94);
    final borderColor = isDark ? AppTheme.darkBorder : const Color(0xFFE2E8F0);
    final textColor = isDark
        ? AppTheme.darkTextSecondary
        : const Color(0xFF64748B);
    final labelColor = isDark
        ? AppTheme.darkTextPrimary
        : const Color(0xFF0F172A);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 50 : 15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primary row: Compact relationships + Time bounds
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Min Year
              Text(
                '${widget.minYear}',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: textColor,
                ),
              ),
              const SizedBox(width: 4),
              Text('→', style: TextStyle(fontSize: 10, color: textColor)),
              const SizedBox(width: 4),
              // Max Year
              Text(
                '${widget.maxYear}',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: textColor,
                ),
              ),
              const SizedBox(width: 12),

              // Citation indicator
              Container(
                width: 10,
                height: 2.5,
                color: isDark
                    ? AppTheme.citationBlueDark
                    : AppTheme.citationBlue,
              ),
              const SizedBox(width: 3),
              Icon(
                Icons.arrow_right_alt,
                size: 14,
                color: isDark
                    ? AppTheme.citationBlueDark
                    : AppTheme.citationBlue,
              ),
              const SizedBox(width: 3),
              Text(
                'Citation',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
              ),
              const SizedBox(width: 12),

              // Similarity indicator
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 3,
                    height: 2,
                    color: isDark
                        ? AppTheme.similarityCyanDark
                        : AppTheme.similarityCyan,
                  ),
                  const SizedBox(width: 2),
                  Container(
                    width: 3,
                    height: 2,
                    color: isDark
                        ? AppTheme.similarityCyanDark
                        : AppTheme.similarityCyan,
                  ),
                  const SizedBox(width: 2),
                  Container(
                    width: 3,
                    height: 2,
                    color: isDark
                        ? AppTheme.similarityCyanDark
                        : AppTheme.similarityCyan,
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Text(
                'Similarity',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
              ),
              const SizedBox(width: 6),

              // Info / expand button
              InkWell(
                onTap: () => setState(() => _isExpanded = !_isExpanded),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    _isExpanded
                        ? Icons.expand_less_rounded
                        : Icons.info_outline_rounded,
                    size: 14,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),

          // Expanded details (Node semantics & size mapping)
          if (_isExpanded) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: borderColor, width: 0.8)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Origin Node
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark
                            ? AppTheme.originGreenDark
                            : AppTheme.originGreen,
                        width: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Starting paper',
                    style: TextStyle(fontSize: 10, color: textColor),
                  ),
                  const SizedBox(width: 12),

                  // Selected Node
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark
                            ? AppTheme.actionPurpleDark
                            : AppTheme.actionPurple,
                        width: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Selected',
                    style: TextStyle(fontSize: 10, color: textColor),
                  ),
                  const SizedBox(width: 12),

                  // Size mapping
                  Icon(Icons.bubble_chart_outlined, size: 12, color: textColor),
                  const SizedBox(width: 4),
                  Text(
                    'Size = Citations',
                    style: TextStyle(fontSize: 10, color: textColor),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
