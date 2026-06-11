import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class ChatTypingIndicator extends StatefulWidget {
  const ChatTypingIndicator({super.key});
  @override
  State<ChatTypingIndicator> createState() => _ChatTypingIndicatorState();
}

class _ChatTypingIndicatorState extends State<ChatTypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  double _dotOpacity(double t, int i) {
    final shifted = (t - i * 0.18) % 1.0;
    final fade = (1.0 - (shifted - 0.3).abs() * 2.5).clamp(0.25, 1.0);
    return fade;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 60, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: AppColors.heroBrandGradient),
            border: Border.all(color: AppColors.primaryMid),
          ),
          child: const Icon(Icons.smart_toy_rounded, color: AppColors.heroFg, size: 14),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            border: Border.all(color: AppColors.border1),
          ),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              return Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
                return Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 5),
                  child: Opacity(
                    opacity: _dotOpacity(_ctrl.value, i),
                    child: Container(
                      width: 7, height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: AppColors.primary,
                      ),
                    ),
                  ),
                );
              }));
            },
          ),
        ),
      ]),
    );
  }
}
