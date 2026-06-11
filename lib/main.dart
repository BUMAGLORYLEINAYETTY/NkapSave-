import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/api_service.dart';
import 'core/services/fcm_service.dart';
import 'core/services/user_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Initial overlay style — the MaterialApp.themeMode watcher below will
  // update this whenever the user flips the theme in the drawer.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark, // dark icons for the cream canvas
    statusBarBrightness: Brightness.light,     // iOS
    systemNavigationBarColor: Color(0xFFF8F9FF),
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  await ApiService.init();
  try {
    await UserPreferences.instance.load();
  } catch (e) {
    debugPrint('[UserPreferences] load failed (continuing with defaults): $e');
  }
  await FcmService.instance.init();
  if (ApiService.isLoggedIn) {
    // Best-effort: sync this device's push token with the backend on launch.
    unawaited(FcmService.instance.syncTokenWithBackend());
  }

  runApp(const ProviderScope(child: NkapSaveApp()));
}

class NkapSaveApp extends StatelessWidget {
  const NkapSaveApp({super.key});
  @override
  Widget build(BuildContext context) {
    // Listen to UserPreferences so the MaterialApp rebuilds (and `themeMode`
    // updates) the moment the user picks a new theme in the drawer — no
    // restart needed.
    return AnimatedBuilder(
      animation: UserPreferences.instance,
      builder: (_, __) => MaterialApp.router(
        title: 'NkapSave',
        debugShowCheckedModeBanner: false,
        theme:     AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: UserPreferences.instance.themeMode,
        routerConfig: AppRouter.router,
        // Screens read AppColors.* directly (static getters, no Theme
        // dependency), so a themeMode change alone doesn't invalidate
        // their build. Re-keying the page subtree on every theme flip
        // forces Flutter to tear down and rebuild the live page, so
        // hard-coded palette references repaint with the new colors.
        builder: (context, child) => KeyedSubtree(
          key: ValueKey(UserPreferences.instance.themePreferenceId),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
