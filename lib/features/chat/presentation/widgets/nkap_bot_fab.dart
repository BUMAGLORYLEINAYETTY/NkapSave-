import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../providers/chat_controller.dart';

class NkapBotFab extends StatefulWidget {
  final VoidCallback onTap;
  const NkapBotFab({super.key, required this.onTap});

  @override
  State<NkapBotFab> createState() => _NkapBotFabState();
}

class _NkapBotFabState extends State<NkapBotFab> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  bool _pressed = false;
  final _controller = ChatController.instance;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);
    _controller.addListener(_onControllerChange);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _controller.removeListener(_onControllerChange);
    super.dispose();
  }

  void _onControllerChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasAlerts = _controller.hasPendingAlerts;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () { HapticFeedback.mediumImpact(); widget.onTap(); },
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) {
            final t = _pulse.value;
            return SizedBox(
              width: 64, height: 64,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 60, height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: AppColors.heroBrandGradient,
                    ),
                    border: Border.all(color: AppColors.primaryMid, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.38 + 0.18 * t),
                        blurRadius: 22 + 10 * t,
                        spreadRadius: 1 + 2 * t,
                      ),
                      const BoxShadow(
                        color: Color(0x59000000),
                        blurRadius: 14, offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.smart_toy_rounded, color: AppColors.heroFg, size: 26),
                  ),
                ),
                if (hasAlerts) Positioned(
                  top: -2, right: -2,
                  child: _alertBadge(t),
                ),
              ]),
            );
          },
        ),
      ),
    );
  }

  Widget _alertBadge(double t) {
    final scale = 1.0 + 0.08 * t;
    return Transform.scale(
      scale: scale,
      child: Container(
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: AppColors.surface1, width: 1.8),
          boxShadow: [BoxShadow(color: AppColors.accent.withOpacity(0.55), blurRadius: 8)],
        ),
        child: Center(
          child: Text(
            '!',
            style: AppTextStyles.label.copyWith(
              color: AppColors.heroFg, fontSize: 11, height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
