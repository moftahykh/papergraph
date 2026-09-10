import 'package:flutter/material.dart';

class GraphYearLegend extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final bgColor = isDark
        ? const Color(0xDD0F172A)
        : const Color(0xEEFFFFFF);
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final textColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 80 : 25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Year Gradient Spectrum Bar
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$minYear',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 120,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF10B981), // Mint Teal
                      Color(0xFF06B6D4), // Sky Cyan
                      Color(0xFF2563EB), // Electric Blue
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$maxYear',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Edge Types Legend
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Citation Arrow Indicator
              Container(
                width: 14,
                height: 2,
                color: const Color(0xFF3B82F6),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_right_alt,
                size: 14,
                color: Color(0xFF3B82F6),
              ),
              const SizedBox(width: 4),
              Text(
                'Citation',
                style: TextStyle(fontSize: 10, color: textColor),
              ),
              const SizedBox(width: 14),
              // Similarity Dashed Indicator
              Row(
                children: [
                  Container(width: 4, height: 2, color: const Color(0xFF06B6D4)),
                  const SizedBox(width: 2),
                  Container(width: 4, height: 2, color: const Color(0xFF06B6D4)),
                  const SizedBox(width: 2),
                  Container(width: 4, height: 2, color: const Color(0xFF06B6D4)),
                ],
              ),
              const SizedBox(width: 4),
              Text(
                'Similarity',
                style: TextStyle(fontSize: 10, color: textColor),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
