import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

class NkapCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? color;
  final VoidCallback? onTap;
  final double radius;

  const NkapCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.onTap,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color ?? AppColors.surface2,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: AppColors.border1),
        ),
        child: child,
      ),
    );
  }
}
