import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/user_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade, _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _fade  = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.6, curve: Curves.easeOut)));
    _scale = Tween<double>(begin: 0.7, end: 1).animate(
        CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.6, curve: Curves.elasticOut)));
    _ctrl.forward();

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      if (ApiService.isLoggedIn) {
        context.go('/home');
      } else if (UserPreferences.instance.introSeen) {
        context.go('/login');
      } else {
        context.go('/onboarding');
      }
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => FadeTransition(
            opacity: _fade,
            child: ScaleTransition(
              scale: _scale,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    gradient:  LinearGradient(
                      colors: [AppColors.surface3, AppColors.surface4],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.primaryMid, width: 1.5),
                    boxShadow: [BoxShadow(
                      color: AppColors.primary.withOpacity(0.25),
                      blurRadius: 30, spreadRadius: 4,
                    )],
                  ),
                  child: const Center(child: Text('N',
                      style: TextStyle(color: AppColors.primary, fontSize: 36, fontWeight: FontWeight.w900))),
                ),
                const SizedBox(height: 20),
                RichText(text:  TextSpan(children: [
                  TextSpan(text: 'Nkap', style: TextStyle(
                      color: AppColors.text1, fontSize: 28, fontWeight: FontWeight.w800)),
                  TextSpan(text: 'Save', style: TextStyle(
                      color: AppColors.primary, fontSize: 28, fontWeight: FontWeight.w800)),
                ])),
                const SizedBox(height: 8),
                 Text('Smart Finance for Cameroon',
                    style: TextStyle(color: AppColors.text3, fontSize: 13)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
