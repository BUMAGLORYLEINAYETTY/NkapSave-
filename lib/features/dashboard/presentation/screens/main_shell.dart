import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/preferences/app_feature.dart';
import '../../../../core/services/user_preferences.dart';
import '../../../../features/dashboard/presentation/screens/home_screen.dart';
import '../../../../features/expenses/presentation/screens/expenses_screen.dart';
import '../../../../features/savings/presentation/screens/savings_screen.dart';
import '../../../../features/njangi/presentation/screens/njangi_screen.dart';

class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  @override
  void initState() {
    super.initState();
    UserPreferences.instance.addListener(_onPrefsChanged);
  }

  @override
  void dispose() {
    UserPreferences.instance.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  /// Returns the [tabs] currently enabled. Home is always present.
  List<_Tab> _visibleTabs() {
    final enabled = UserPreferences.instance.enabledFeatures;
    return [
      const _Tab(
        route: '/home', label: 'Home',
        screen: HomeScreen(),
        active: Icons.home_rounded, outline: Icons.home_outlined,
      ),
      if (enabled.contains(AppFeature.expenses)) const _Tab(
        route: '/expenses', label: 'Expenses',
        screen: ExpensesScreen(),
        active: Icons.bar_chart_rounded, outline: Icons.bar_chart_outlined,
      ),
      if (enabled.contains(AppFeature.savings)) const _Tab(
        route: '/savings', label: 'Savings',
        screen: SavingsScreen(),
        active: Icons.savings_rounded, outline: Icons.savings_outlined,
      ),
      if (enabled.contains(AppFeature.njangi)) const _Tab(
        route: '/njangi', label: 'Njangi',
        screen: NjangiScreen(),
        active: Icons.group_rounded, outline: Icons.group_outlined,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _visibleTabs();
    final location = GoRouterState.of(context).matchedLocation;
    var index = tabs.indexWhere((t) => location.startsWith(t.route));
    if (index < 0) index = 0;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(index: index, children: [for (final t in tabs) t.screen]),
      bottomNavigationBar: Container(
        decoration:  BoxDecoration(
          color: AppColors.surface1,
          border: Border(top: BorderSide(color: AppColors.border1)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                for (var i = 0; i < tabs.length; i++)
                  Expanded(child: _NavItem(
                    tab: tabs[i],
                    active: i == index,
                    onTap: () => context.go(tabs[i].route),
                  )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab {
  final String route, label;
  final Widget screen;
  final IconData active, outline;
  const _Tab({
    required this.route, required this.label,
    required this.screen,
    required this.active, required this.outline,
  });
}

class _NavItem extends StatelessWidget {
  final _Tab tab;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({required this.tab, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryDim : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? tab.active : tab.outline,
              size: 20,
              color: active ? AppColors.primary : AppColors.text3,
            ),
            const SizedBox(height: 2),
            Text(tab.label, style: AppTextStyles.caption.copyWith(
              color: active ? AppColors.primary : AppColors.text3,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            )),
          ],
        ),
      ),
    ),
  );
}
