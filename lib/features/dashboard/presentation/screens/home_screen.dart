import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/preferences/app_feature.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/user_preferences.dart';
import '../../../../core/widgets/nkap_card.dart';
import '../../../../core/widgets/nkap_chip.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';
import '../../../chat/presentation/nkapbot_screen.dart';
import '../../../chat/presentation/widgets/nkap_bot_fab.dart';
import '../widgets/app_drawer.dart';

/// A clean, real-data home screen. Every number on this page comes from
/// the backend — there's no mock data here. Anything we don't have a
/// real API for yet is intentionally absent rather than faked.
///
/// Layout follows the Stitch dashboard export: balance hero with quick
/// actions, smart feature cards, recent-activity rows, insight tiles.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _loading = true;
  String? _error;
  bool _balanceHidden = false;

  // Real backend payloads
  Map<String, dynamic>? _dashboard;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _njangi;
  Map<String, dynamic>? _savings;

  final _scaffoldKey = GlobalKey<ScaffoldState>();

  Set<AppFeature> get _features => UserPreferences.instance.enabledFeatures;
  bool get _hasExpenses => _features.contains(AppFeature.expenses);
  bool get _hasNjangi   => _features.contains(AppFeature.njangi);
  bool get _hasSavings  => _features.contains(AppFeature.savings);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Dashboard + profile are universal. Njangi / savings only fire when
      // the user has those features enabled — saves a round trip per skip.
      final calls = <Future<dynamic>>[
        ApiService.getDashboard(),
        ApiService.getMyProfile().catchError((_) => <String, dynamic>{}),
        if (_hasNjangi)
          ApiService.getNjangi().catchError((_) => <String, dynamic>{}),
        if (_hasSavings)
          ApiService.getSavings().catchError((_) => <String, dynamic>{}),
      ];
      final results = await Future.wait(calls);
      if (!mounted) return;
      setState(() {
        _dashboard = results[0] as Map<String, dynamic>;
        final p = results[1] as Map<String, dynamic>;
        _profile = p.isEmpty ? null : p;
        var idx = 2;
        if (_hasNjangi) {
          final n = results[idx++] as Map<String, dynamic>;
          _njangi = n.isEmpty ? null : n;
        } else {
          _njangi = null;
        }
        if (_hasSavings) {
          final s = results[idx++] as Map<String, dynamic>;
          _savings = s.isEmpty ? null : s;
        } else {
          _savings = null;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error   = 'Could not load your dashboard. Pull to retry.';
      });
    }
  }

  // ── Display helpers ─────────────────────────────────────────
  String _group(num n) => n.abs().toStringAsFixed(0).replaceAllMapped(
      RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},");

  String _fmtFcfa(num n) => '${_group(n)} FCFA';

  String get _firstName {
    final n = (_profile?['full_name'] ?? '').toString().trim();
    if (n.isEmpty) return 'there';
    return n.split(' ').first;
  }

  String get _avatarInitial {
    final n = (_profile?['full_name'] ?? '').toString().trim();
    if (n.isEmpty) return '?';
    return n[0].toUpperCase();
  }

  String get _avatarUrl =>
      ApiService.pictureUrl(_profile?['profile_picture'] as String?);

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  // ── Navigation helpers ──────────────────────────────────────
  Future<void> _openProfile() async {
    HapticFeedback.lightImpact();
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
    if (!mounted) return;
    final p = await ApiService.getMyProfile()
        .catchError((_) => <String, dynamic>{});
    if (!mounted) return;
    setState(() => _profile = p.isEmpty ? null : p);
  }

  void _openNotifications() {
    HapticFeedback.lightImpact();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  void _openNkapBot() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const NkapBotScreen()),
    );
  }

  void _go(String route) {
    HapticFeedback.selectionClick();
    context.go(route);
  }

  // ── Build ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.bg,
      drawer: AppDrawer(profile: _profile),
      floatingActionButton: _loading
          ? null
          : NkapBotFab(onTap: _openNkapBot),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface2,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _appBar(),
            SliverToBoxAdapter(child: _content()),
          ],
        ),
      ),
    );
  }

  // ── Top bar (Stitch: avatar + brand wordmark, surface chrome) ─
  SliverAppBar _appBar() => SliverAppBar(
    backgroundColor: AppColors.surface1,
    elevation: 0,
    pinned: true,
    expandedHeight: 0,
    toolbarHeight: 64,
    titleSpacing: 0,
    systemOverlayStyle: AppColors.isDark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark,
    leading: IconButton(
      icon: Icon(Icons.menu_rounded, color: AppColors.text1, size: 22),
      tooltip: 'Menu',
      onPressed: () => _scaffoldKey.currentState?.openDrawer(),
    ),
    title: Row(mainAxisSize: MainAxisSize.min, children: [
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openProfile,
        child: _avatar(),
      ),
      const SizedBox(width: 8),
      Flexible(child: Text(
        'NkapSave',
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.h2.copyWith(color: AppColors.primary),
      )),
    ]),
    actions: [
      IconButton(
        icon: Icon(_balanceHidden
            ? Icons.visibility_off_rounded
            : Icons.visibility_rounded,
            color: AppColors.primary, size: 20),
        tooltip: _balanceHidden ? 'Show balances' : 'Hide balances',
        onPressed: () {
          HapticFeedback.selectionClick();
          setState(() => _balanceHidden = !_balanceHidden);
        },
      ),
      IconButton(
        icon: Icon(Icons.notifications_none_rounded,
            color: AppColors.text2, size: 22),
        tooltip: 'Notifications',
        onPressed: _openNotifications,
      ),
      const SizedBox(width: 4),
    ],
  );

  Widget _avatar() {
    final url = _avatarUrl;
    return Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: url.isEmpty
            ? LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: AppColors.heroBrandGradient)
            : null,
        color: url.isEmpty ? null : AppColors.surface3,
        image: url.isEmpty
            ? null
            : DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
        border: Border.all(
            color: AppColors.primary.withOpacity(0.5), width: 1.5),
      ),
      child: url.isEmpty
          ? Center(child: Text(_avatarInitial,
              style: AppTextStyles.h4.copyWith(color: AppColors.heroFg)))
          : null,
    );
  }

  // ── Body content ────────────────────────────────────────────
  Widget _content() {
    if (_loading) return _skeleton();
    if (_error != null) return _errorState();

    return Column(children: [
      _greetingBlock(),
      _balanceHero(),
      if (_hasSavings) _savingsGoalCard(),
      if (_hasNjangi)  _njangiCard(),
      _recentActivity(),
      _insights(),
      const SizedBox(height: 28),
    ]);
  }

  Widget _greetingBlock() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_greeting()}, $_firstName 👋',
            style: AppTextStyles.h4.copyWith(color: AppColors.text2),
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text("Here's your money at a glance",
            style: AppTextStyles.caption,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    ),
  );

  // ── Balance hero (Stitch: green card, watermark, quick actions)
  Widget _balanceHero() {
    final d = _dashboard ?? {};
    final balance = (d['total_balance'] as num?)?.toDouble() ?? 0;

    final actions = <_QuickAction>[
      if (_hasExpenses)
        _QuickAction(Icons.bar_chart_rounded, 'Expenses',
            () => _go('/expenses')),
      if (_hasSavings)
        _QuickAction(Icons.savings_rounded, 'Savings',
            () => _go('/savings')),
      if (_hasNjangi)
        _QuickAction(Icons.group_rounded, 'Njangi',
            () => _go('/njangi')),
      _QuickAction(Icons.smart_toy_rounded, 'NkapBot', _openNkapBot),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: AppColors.heroBrandGradient,
          ),
          boxShadow: [
            BoxShadow(
                color: (AppColors.isDark ? Colors.black : AppColors.primary)
                    .withOpacity(AppColors.isDark ? 0.4 : 0.18),
                blurRadius: 28, offset: const Offset(0, 10)),
          ],
        ),
        child: Stack(children: [
          // Watermark wallet icon, top-right (Stitch opacity-10 deco).
          Positioned(
            top: -12, right: -8,
            child: Icon(Icons.account_balance_wallet_rounded,
                size: 120, color: AppColors.heroFg.withOpacity(0.08)),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Total Balance',
                  style: AppTextStyles.label
                      .copyWith(color: AppColors.heroFgMuted)),
              const SizedBox(height: 4),
              // Tap-to-hide micro-interaction (mirrors the Stitch export).
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _balanceHidden = !_balanceHidden);
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: _balanceHidden
                              ? '••••••'
                              : _group(balance),
                          style: AppTextStyles.balance),
                      TextSpan(
                          text: ' FCFA',
                          style: AppTextStyles.h3
                              .copyWith(color: AppColors.heroFgMuted)),
                    ]),
                    key: ValueKey(_balanceHidden),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(children: [
                for (var i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: _quickActionTile(actions[i])),
                ],
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _quickActionTile(_QuickAction a) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: a.onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.heroFg.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(a.icon, size: 22, color: AppColors.heroFg),
        const SizedBox(height: 4),
        Text(a.label,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: AppTextStyles.chip.copyWith(color: AppColors.heroFg)),
      ]),
    ),
  );

  // ── Savings goal card (Stitch "Financial Health" composition) ─
  Widget _savingsGoalCard() {
    final goals = (_savings?['goals'] as List?)?.cast<Map>() ?? const [];
    final active = goals.where((g) => g['is_completed'] != true).length;
    final totalSaved = (_savings?['total_saved'] as num?)?.toDouble()
        ?? goals.fold<double>(0,
            (s, g) => s + ((g['current'] as num?)?.toDouble() ?? 0));
    final totalTarget = goals.fold<double>(0,
            (s, g) => s + ((g['target'] as num?)?.toDouble() ?? 0));
    final progress = totalTarget > 0
        ? (totalSaved / totalTarget).clamp(0.0, 1.0)
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: NkapCard(
        radius: 16,
        color: AppColors.surface1,
        onTap: () => _go('/savings'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 40, height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentDim,
              ),
              child: const Icon(Icons.savings_rounded,
                  size: 20, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Savings Goals', style: AppTextStyles.h3),
              const SizedBox(height: 2),
              Text(active == 1 ? '1 active goal' : '$active active goals',
                  style: AppTextStyles.caption),
            ])),
            if (progress != null)
              NkapChip(
                label: '${(progress * 100).toStringAsFixed(0)}% SAVED',
                color: AppColors.accent,
                dimColor: AppColors.accentDim,
              ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Text('Total saved', style: AppTextStyles.bodyMuted),
            const Spacer(),
            Text(_balanceHidden ? '•••••' : _fmtFcfa(totalSaved),
                style: AppTextStyles.h4.copyWith(color: AppColors.primary)),
          ]),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppColors.surface3,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _balanceHidden
                  ? 'of ••••• target'
                  : 'of ${_fmtFcfa(totalTarget)} target',
              style: AppTextStyles.caption,
            ),
          ],
        ]),
      ),
    );
  }

  // ── Njangi card (same smart-card composition) ───────────────
  Widget _njangiCard() {
    final groups = (_njangi?['groups'] as List?)?.cast<Map>() ?? const [];
    final joined  = groups.length;
    final created = groups.where((g) => g['is_admin'] == true).length;
    final isMyTurn = groups.any((g) => g['is_my_turn'] == true);
    final trust = (_njangi?['trust_score'] as num?)?.toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: NkapCard(
        radius: 16,
        color: AppColors.surface1,
        onTap: () => _go('/njangi'),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.purpleDim,
            ),
            child: const Icon(Icons.group_rounded,
                size: 20, color: AppColors.purple),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('Njangi', style: AppTextStyles.h3),
            const SizedBox(height: 2),
            Text(
              [
                joined == 1 ? '1 group' : '$joined groups',
                if (created > 0) '$created created by you',
              ].join(' · '),
              style: AppTextStyles.caption,
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          ])),
          const SizedBox(width: 8),
          if (isMyTurn)
            const NkapChip(
              label: 'YOUR TURN',
              color: AppColors.primary,
              dimColor: AppColors.primaryDim,
            )
          else if (trust != null)
            NkapChip(
              label: 'TRUST ${trust.toStringAsFixed(0)}',
              color: AppColors.purple,
              dimColor: AppColors.purpleDim,
            ),
        ]),
      ),
    );
  }

  // ── Recent activity (Stitch: per-row cards, 40px icon circles)
  Widget _recentActivity() {
    final raw = ((_dashboard ?? const {})['recent_transactions'] as List?)
            ?.cast<Map>() ?? const [];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Recent Activity', style: AppTextStyles.h3),
          if (_hasExpenses)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _go('/expenses'),
              child: Text('See All',
                  style: AppTextStyles.h4
                      .copyWith(color: AppColors.primary)),
            ),
        ]),
        const SizedBox(height: 12),
        if (raw.isEmpty)
          NkapCard(
            radius: 16,
            color: AppColors.surface1,
            child: Center(child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No transactions yet.',
                  style: AppTextStyles.bodyMuted),
            )),
          )
        else
          for (var i = 0; i < raw.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _txCard(raw[i]),
          ],
      ]),
    );
  }

  Widget _txCard(Map t) {
    final name     = (t['name'] ?? '').toString();
    final category = (t['category'] ?? '').toString();
    final amount   = (t['amount'] as num?)?.toDouble() ?? 0;
    final date     = (t['date'] ?? '').toString();
    final hex      = (t['color_hex'] ?? '').toString();
    final isCredit = amount >= 0;
    final iconColor =
        hex.isEmpty ? (isCredit ? AppColors.primary : AppColors.text2)
                    : _hexColor(hex);

    return NkapCard(
      radius: 16,
      color: AppColors.surface1,
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: iconColor.withOpacity(0.12),
          ),
          child: Icon(
            isCredit ? Icons.south_west_rounded : Icons.north_east_rounded,
            size: 18, color: iconColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(name, style: AppTextStyles.h4,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text('$category · $date', style: AppTextStyles.caption,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            _balanceHidden
                ? '•••••'
                : '${isCredit ? '+' : '-'} ${_group(amount)}',
            style: AppTextStyles.h4.copyWith(
                color: isCredit ? AppColors.primary : AppColors.text1),
          ),
          const SizedBox(height: 2),
          Text('FCFA', style: AppTextStyles.caption),
        ]),
      ]),
    );
  }

  Color _hexColor(String hex) {
    final h = hex.replaceFirst('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return v == null ? AppColors.text3 : Color(v);
  }

  // ── Insights (Stitch bento grid + real weekly chart) ────────
  Widget _insights() {
    final d = _dashboard ?? {};
    final income   = (d['monthly_income']   as num?)?.toDouble() ?? 0;
    final expenses = (d['monthly_expenses'] as num?)?.toDouble() ?? 0;
    final saved    = (d['saved_this_month'] as num?)?.toDouble() ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text('This Month', style: AppTextStyles.h3),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _insightTile(
            icon: Icons.trending_up_rounded,
            iconColor: AppColors.primary,
            bg: AppColors.primaryDim,
            border: Border.all(color: AppColors.primaryMid),
            label: 'Income',
            value: _balanceHidden ? '•••••' : _fmtFcfa(income),
            valueColor: AppColors.primary,
          )),
          const SizedBox(width: 16),
          Expanded(child: _insightTile(
            icon: Icons.trending_down_rounded,
            iconColor: AppColors.text2,
            bg: AppColors.surface2,
            border: Border.all(color: AppColors.border1),
            label: 'Expenses',
            value: _balanceHidden ? '•••••' : _fmtFcfa(expenses),
            valueColor: AppColors.text1,
          )),
        ]),
        const SizedBox(height: 8),
        _insightTile(
          icon: Icons.savings_rounded,
          iconColor: AppColors.accent,
          bg: AppColors.accentDim,
          border: Border.all(color: AppColors.accentMid),
          label: 'Saved this month',
          value: _balanceHidden ? '•••••' : _fmtFcfa(saved),
          valueColor: AppColors.text1,
          horizontal: true,
        ),
        _weeklyChart(),
      ]),
    );
  }

  Widget _insightTile({
    required IconData icon,
    required Color iconColor,
    required Color bg,
    required Border border,
    required String label,
    required String value,
    required Color valueColor,
    bool horizontal = false,
  }) {
    final deco = BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(16),
      border: border,
    );
    if (horizontal) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: deco,
        child: Row(children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AppTextStyles.bodyMuted)),
          Text(value,
              style: AppTextStyles.h4.copyWith(color: valueColor)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: deco,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 26, color: iconColor),
        const SizedBox(height: 20),
        Text(label, style: AppTextStyles.label),
        const SizedBox(height: 4),
        Text(value,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: AppTextStyles.h3.copyWith(color: valueColor)),
      ]),
    );
  }

  // ── Weekly chart (real weekly_spend data, restyled) ─────────
  Widget _weeklyChart() {
    final week = ((_dashboard ?? const {})['weekly_spend'] as List?)
            ?.cast<Map>() ?? const [];
    if (week.isEmpty) return const SizedBox.shrink();

    final amounts =
        week.map((d) => (d['amount'] as num?)?.toDouble() ?? 0).toList();
    final hasData = amounts.any((a) => a > 0);
    final maxY    = hasData ? amounts.reduce((a, b) => a > b ? a : b) * 1.3 : 1.0;
    final total   = amounts.fold<double>(0, (s, a) => s + a);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: NkapCard(
        radius: 16,
        color: AppColors.surface1,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('This week', style: AppTextStyles.h4),
            Text(_balanceHidden ? '•••••' : _fmtFcfa(total),
                style: AppTextStyles.label
                    .copyWith(color: AppColors.primary)),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 110,
            child: hasData
                ? BarChart(BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxY,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        tooltipBgColor: AppColors.surface3,
                        tooltipRoundedRadius: 10,
                        getTooltipItem: (group, _, rod, __) => BarTooltipItem(
                          _fmtFcfa(rod.toY),
                          AppTextStyles.chip
                              .copyWith(color: AppColors.text1),
                        ),
                      ),
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      leftTitles:   const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles:  const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles:    const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true, reservedSize: 24,
                        getTitlesWidget: (value, _) {
                          final i = value.toInt();
                          if (i < 0 || i >= week.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              (week[i]['day'] ?? '').toString(),
                              style: AppTextStyles.caption,
                            ),
                          );
                        },
                      )),
                    ),
                    gridData: FlGridData(
                      show: true, drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(
                          color: AppColors.border1,
                          strokeWidth: 1, dashArray: [4, 4]),
                    ),
                    borderData: FlBorderData(show: false),
                    barGroups: [
                      for (var i = 0; i < amounts.length; i++)
                        BarChartGroupData(x: i, barRods: [
                          BarChartRodData(
                            toY: amounts[i], width: 18,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(6)),
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                AppColors.primary.withOpacity(0.55),
                                AppColors.primary,
                              ],
                            ),
                          ),
                        ]),
                    ],
                  ))
                : Center(child: Text('No spending recorded this week.',
                    style: AppTextStyles.bodyMuted)),
          ),
        ]),
      ),
    );
  }

  // ── States ──────────────────────────────────────────────────
  Widget _skeleton() => Shimmer.fromColors(
    baseColor: AppColors.surface4,
    highlightColor: AppColors.surface2,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Container(height: 36, width: double.infinity,
            decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12))),
        const SizedBox(height: 16),
        Container(height: 200,
            decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(16))),
        const SizedBox(height: 16),
        Container(height: 120,
            decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(16))),
        const SizedBox(height: 16),
        Container(height: 220,
            decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(16))),
      ]),
    ),
  );

  Widget _errorState() => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        Icon(Icons.cloud_off_rounded, size: 40, color: AppColors.text3),
        const SizedBox(height: 12),
        Text(_error ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMuted),
      ],
    ),
  );
}

class _QuickAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction(this.icon, this.label, this.onTap);
}
