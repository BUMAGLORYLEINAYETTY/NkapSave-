import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/pin_screen.dart';
import '../../features/auth/presentation/screens/feature_selection_screen.dart';
import '../../features/auth/presentation/screens/profile_setup_screen.dart';
import '../../features/dashboard/presentation/screens/main_shell.dart';
import '../../features/dashboard/presentation/screens/home_screen.dart';
import '../../features/expenses/presentation/screens/expenses_screen.dart';
import '../../features/savings/presentation/screens/savings_screen.dart';
import '../../features/njangi/presentation/screens/njangi_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/profile/presentation/screens/kyc_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/chat/presentation/nkapbot_screen.dart';
import '../preferences/app_feature.dart';
import '../services/api_service.dart';
import '../services/user_preferences.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/splash',
    // Re-evaluate the redirect whenever auth state flips — login,
    // sign-out, or session expiry (401 → refresh fails → tokens
    // cleared). Without this, an expired session would leave the
    // user on a blank /home making 401 requests forever.
    refreshListenable: ApiService.authState,
    redirect: (context, state) {
      final loggedIn = ApiService.isLoggedIn;
      const authPaths = {
        '/login', '/register', '/splash', '/onboarding',
        '/feature-select', '/profile-setup',
      };
      final onAuthPage = authPaths.contains(state.matchedLocation);
      if (loggedIn && onAuthPage) return '/home';
      if (!loggedIn && !onAuthPage) return '/login';
      const routeFeatures = {
        '/expenses': AppFeature.expenses,
        '/savings': AppFeature.savings,
        '/njangi': AppFeature.njangi,
      };
      final feature = routeFeatures[state.matchedLocation];
      if (feature != null && !UserPreferences.instance.isEnabled(feature)) {
        return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash',     builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/login',      builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register',   builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/pin',        builder: (_, __) => const PinScreen()),
      GoRoute(path: '/feature-select', builder: (_, __) => const FeatureSelectionScreen()),
      GoRoute(path: '/profile-setup',  builder: (_, __) => const ProfileSetupScreen()),
      GoRoute(path: '/profile',       builder: (_, __) => const ProfileScreen()),
      GoRoute(path: '/kyc',           builder: (_, __) => const KycScreen()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/nkapbot',       builder: (_, __) => const NkapBotScreen()),
      ShellRoute(
        builder: (ctx, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/home',     builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/expenses', builder: (_, __) => const ExpensesScreen()),
          GoRoute(path: '/savings',  builder: (_, __) => const SavingsScreen()),
          GoRoute(path: '/njangi',   builder: (_, __) => const NjangiScreen()),
        ],
      ),
    ],
  );
}
