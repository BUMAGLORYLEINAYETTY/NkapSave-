import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

class NkapButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool loading;
  final bool outlined;
  final Color? color;
  final double radius;

  const NkapButton({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.loading = false,
    this.outlined = false,
    this.color,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    final disabled = onTap == null;
    // Gradient companion: the brand pairs violet→magenta; any custom colour
    // just lightens toward white so the hack works for accents too.
    final cEnd = c == AppColors.primary
        ? AppColors.magenta
        : Color.lerp(c, Colors.white, 0.16)!;
    // Filled brand/accent buttons carry white labels (RE-NEO look). Outlined
    // buttons tint with the colour itself.
    const fg = Color(0xFFFFFFFF);

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 54,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          gradient: outlined || disabled
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c, cEnd],
                ),
          color: outlined
              ? Colors.transparent
              : disabled
                  ? AppColors.surface3
                  : null,
          borderRadius: BorderRadius.circular(radius),
          border: outlined ? Border.all(color: c, width: 1.5) : null,
          boxShadow: outlined || disabled
              ? null
              : [
                  BoxShadow(
                    color: c.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: fg,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 18,
                        color: outlined
                            ? c
                            : disabled
                                ? AppColors.text3
                                : fg,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: GoogleFonts.hankenGrotesk(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: outlined
                              ? c
                              : disabled
                                  ? AppColors.text3
                                  : fg,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
