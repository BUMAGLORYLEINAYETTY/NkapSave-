import 'package:flutter/material.dart';
import '../constants/app_text_styles.dart';

class NkapChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color dimColor;

  const NkapChip({
    super.key,
    required this.label,
    required this.color,
    required this.dimColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: dimColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: AppTextStyles.chip.copyWith(color: color)),
    );
  }
}
