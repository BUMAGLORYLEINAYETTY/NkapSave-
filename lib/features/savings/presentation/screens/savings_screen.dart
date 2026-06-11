import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:shimmer/shimmer.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:dio/dio.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/widgets/nkap_card.dart';
import '../../../../core/widgets/nkap_button.dart';
import '../../../../core/widgets/nkap_chip.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class SavingsGoal {
  final String id, name, emoji;
  final double target, current, remaining;
  final double percent;
  final bool isLocked, isCompleted;
  final int monthsLeft;
  final Color color;
  final DateTime? deadline;
  final String? note;
  const SavingsGoal({
    required this.id, required this.name, required this.emoji,
    required this.target, required this.current, required this.remaining,
    required this.percent, required this.isLocked, required this.isCompleted,
    required this.monthsLeft, required this.color,
    this.deadline, this.note,
  });
  factory SavingsGoal.fromJson(Map<String, dynamic> j, Color color) =>
      SavingsGoal(
        id:          j['id']           as String,
        name:        j['name']         as String,
        emoji:       j['emoji']        as String? ?? '🎯',
        target:      (j['target']      as num).toDouble(),
        current:     (j['current']     as num).toDouble(),
        remaining:   (j['remaining']   as num).toDouble(),
        percent:     (j['percent']     as num).toDouble(),
        isLocked:    j['is_locked']    as bool,
        isCompleted: j['is_completed'] as bool,
        monthsLeft:  j['months_left']  as int,
        color:       color,
        deadline:    j['deadline'] != null
            ? DateTime.tryParse(j['deadline'] as String)
            : null,
        note:        j['note'] as String?,
      );
  double get progress => (percent / 100).clamp(0.0, 1.0);
}

class AutoSaveConfig {
  final bool active;
  final int percent;
  final String provider;
  final double savedThisMonth;
  const AutoSaveConfig({
    required this.active, required this.percent,
    required this.provider, required this.savedThisMonth,
  });
  factory AutoSaveConfig.fromJson(Map<String, dynamic> j) => AutoSaveConfig(
        active:         j['auto_save_active']   as bool,
        percent:        j['auto_save_percent']  as int,
        provider:       j['auto_save_provider'] as String? ?? 'MTN Money',
        savedThisMonth: (j['saved_this_month']  as num).toDouble(),
      );
}

class SavingsSnapshot {
  final double totalSaved, totalTarget;
  final double overallPercent;
  final AutoSaveConfig autoSave;
  final List<SavingsGoal> goals;
  const SavingsSnapshot({
    required this.totalSaved, required this.totalTarget,
    required this.overallPercent,
    required this.autoSave, required this.goals,
  });
  factory SavingsSnapshot.fromJson(Map<String, dynamic> j) {
    const palette = [
      AppColors.primary, AppColors.info, AppColors.accent,
      AppColors.purple, AppColors.success,
    ];
    final list = (j['goals'] as List).cast<Map<String, dynamic>>();
    return SavingsSnapshot(
      totalSaved:     (j['total_saved']     as num).toDouble(),
      totalTarget:    (j['total_target']    as num).toDouble(),
      overallPercent: (j['overall_percent'] as num).toDouble(),
      autoSave:       AutoSaveConfig.fromJson(j),
      goals: [
        for (var i = 0; i < list.length; i++)
          SavingsGoal.fromJson(list[i], palette[i % palette.length])
      ],
    );
  }
}

class MoMoLink {
  final String id, provider, phone;
  final bool verified;
  const MoMoLink({
    required this.id, required this.provider,
    required this.phone, required this.verified,
  });
  factory MoMoLink.fromJson(Map<String, dynamic> j) => MoMoLink(
        id:       j['id']       as String,
        provider: j['provider'] as String,
        phone:    j['phone']    as String,
        verified: j['verified'] as bool,
      );
}

class AutoSavePlan {
  final String id, goalId, frequency;
  final int percent;
  final double amount;
  final bool active;
  final DateTime nextRunAt;
  final DateTime? lastRunAt;
  final int consecutiveFailures;
  final bool reminderEnabled;
  const AutoSavePlan({
    required this.id, required this.goalId,
    required this.percent, required this.amount,
    required this.frequency, required this.active,
    required this.nextRunAt, this.lastRunAt,
    required this.consecutiveFailures,
    this.reminderEnabled = true,
  });
  factory AutoSavePlan.fromJson(Map<String, dynamic> j) => AutoSavePlan(
        id:        j['id']      as String,
        goalId:    j['goal_id'] as String,
        percent:   j['percent'] as int,
        amount:    (j['amount'] as num).toDouble(),
        frequency: j['frequency'] as String,
        active:    j['active']   as bool,
        nextRunAt: DateTime.parse(j['next_run_at'] as String),
        lastRunAt: j['last_run_at'] != null
            ? DateTime.parse(j['last_run_at'] as String) : null,
        consecutiveFailures: j['consecutive_failures'] as int,
        reminderEnabled: j['reminder_enabled'] as bool? ?? true,
      );
}

class UpcomingRun {
  final String planId, goalId, goalName, goalEmoji, frequency;
  final double amount;
  final DateTime nextRunAt;
  const UpcomingRun({
    required this.planId, required this.goalId,
    required this.goalName, required this.goalEmoji,
    required this.amount, required this.frequency,
    required this.nextRunAt,
  });
  factory UpcomingRun.fromJson(Map<String, dynamic> j) => UpcomingRun(
        planId:    j['plan_id']    as String,
        goalId:    j['goal_id']    as String,
        goalName:  j['goal_name']  as String,
        goalEmoji: j['goal_emoji'] as String,
        amount:    (j['amount']    as num).toDouble(),
        frequency: j['frequency']  as String,
        nextRunAt: DateTime.parse(j['next_run_at'] as String),
      );
}

class ActivityItem {
  final String id, referenceId, status;
  final String? goalId, goalName, goalEmoji, reason;
  final double amount;
  final String currency;
  final DateTime initiatedAt;
  final DateTime? completedAt;
  const ActivityItem({
    required this.id, required this.referenceId, required this.status,
    this.goalId, this.goalName, this.goalEmoji, this.reason,
    required this.amount, required this.currency,
    required this.initiatedAt, this.completedAt,
  });
  factory ActivityItem.fromJson(Map<String, dynamic> j) => ActivityItem(
        id:           j['id'] as String,
        referenceId:  j['reference_id'] as String,
        status:       j['status']       as String,
        goalId:       j['goal_id']      as String?,
        goalName:     j['goal_name']    as String?,
        goalEmoji:    j['goal_emoji']   as String?,
        reason:       j['reason']       as String?,
        amount:       (j['amount']      as num).toDouble(),
        currency:     j['currency']     as String,
        initiatedAt:  DateTime.parse(j['initiated_at'] as String),
        completedAt:  j['completed_at'] != null
            ? DateTime.parse(j['completed_at'] as String) : null,
      );
}

class AllocationItem {
  final String goalId, goalName, goalEmoji;
  final double current, target, percentOfTotal;
  const AllocationItem({
    required this.goalId, required this.goalName, required this.goalEmoji,
    required this.current, required this.target, required this.percentOfTotal,
  });
  factory AllocationItem.fromJson(Map<String, dynamic> j) => AllocationItem(
        goalId:         j['goal_id']    as String,
        goalName:       j['goal_name']  as String,
        goalEmoji:      j['goal_emoji'] as String,
        current:        (j['current']   as num).toDouble(),
        target:         (j['target']    as num).toDouble(),
        percentOfTotal: (j['percent_of_total'] as num).toDouble(),
      );
}

class SavingsInsights {
  final double lifetimeSaved, monthlySaved, prevMonthSaved;
  final double monthlyDeltaPct;
  final int activePlans, completedGoals;
  final double lockedTotal, weeklyScheduled;
  final List<UpcomingRun> upcoming;
  final List<ActivityItem> recentActivity;
  final List<AllocationItem> allocation;
  const SavingsInsights({
    required this.lifetimeSaved, required this.monthlySaved,
    required this.prevMonthSaved, required this.monthlyDeltaPct,
    required this.activePlans, required this.completedGoals,
    required this.lockedTotal, required this.weeklyScheduled,
    required this.upcoming, required this.recentActivity,
    required this.allocation,
  });
  factory SavingsInsights.fromJson(Map<String, dynamic> j) => SavingsInsights(
        lifetimeSaved:    (j['lifetime_saved']    as num).toDouble(),
        monthlySaved:     (j['monthly_saved']     as num).toDouble(),
        prevMonthSaved:   (j['prev_month_saved']  as num).toDouble(),
        monthlyDeltaPct:  (j['monthly_delta_pct'] as num).toDouble(),
        activePlans:      j['active_plans']      as int,
        completedGoals:   j['completed_goals']   as int,
        lockedTotal:      (j['locked_total']     as num).toDouble(),
        weeklyScheduled:  (j['weekly_scheduled'] as num).toDouble(),
        upcoming: (j['upcoming'] as List)
            .cast<Map<String, dynamic>>()
            .map(UpcomingRun.fromJson).toList(),
        recentActivity: (j['recent_activity'] as List)
            .cast<Map<String, dynamic>>()
            .map(ActivityItem.fromJson).toList(),
        allocation: (j['allocation'] as List)
            .cast<Map<String, dynamic>>()
            .map(AllocationItem.fromJson).toList(),
      );
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _fmt(double n) => n.abs()
    .toStringAsFixed(0)
    .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

String _formatDeadline(DateTime d) {
  const months = [
    'Jan','Feb','Mar','Apr','May','Jun',
    'Jul','Aug','Sep','Oct','Nov','Dec',
  ];
  final days = d.difference(DateTime.now()).inDays;
  final base = '${d.day} ${months[d.month - 1]} ${d.year}';
  if (days < 0)  return '$base · ${days.abs()}d overdue';
  if (days == 0) return '$base · today';
  if (days == 1) return '$base · 1 day left';
  if (days <= 60) return '$base · $days days left';
  final monthsLeft = (days / 30).round();
  return '$base · ~$monthsLeft mo left';
}

String _compact(double n) {
  if (n.abs() >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
  if (n.abs() >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
  if (n.abs() >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
  return n.toStringAsFixed(0);
}

String _apiErr(Object e, [String fallback = 'Something went wrong']) {
  if (e is DioException) {
    final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
    if (detail is String) return detail;
  }
  return fallback;
}

String _relativeTime(DateTime t) {
  final diff = t.difference(DateTime.now());
  if (diff.isNegative) {
    final ago = -diff;
    if (ago.inMinutes < 1)  return 'just now';
    if (ago.inHours   < 1)  return '${ago.inMinutes}m ago';
    if (ago.inDays    < 1)  return '${ago.inHours}h ago';
    if (ago.inDays    < 7)  return '${ago.inDays}d ago';
    return '${(ago.inDays / 7).floor()}w ago';
  }
  if (diff.inMinutes < 1)  return 'in seconds';
  if (diff.inHours   < 1)  return 'in ${diff.inMinutes}m';
  if (diff.inDays    < 1)  return 'in ${diff.inHours}h';
  if (diff.inDays    < 7)  return 'in ${diff.inDays}d';
  return 'in ${(diff.inDays / 7).floor()}w';
}

String _freqShort(String f) =>
    {'daily': 'Daily', 'weekly': 'Weekly', 'monthly': 'Monthly'}[f] ?? f;

void _toast(BuildContext ctx, String msg, {bool error = false}) {
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
    content: Text(msg, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
    backgroundColor:
        (error ? AppColors.danger : AppColors.primary).withOpacity(0.9),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

// ─── Savings Screen ───────────────────────────────────────────────────────────

class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});
  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _loadError;
  SavingsSnapshot? _snapshot;
  SavingsInsights? _insights;
  MoMoLink? _link;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() { _fadeCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final results = await Future.wait([
        ApiService.getSavings(),
        ApiService.getSavingsInsights(),
        ApiService.getMoMoLink(),
      ]);
      if (!mounted) return;
      final snap = SavingsSnapshot.fromJson(results[0] as Map<String, dynamic>);
      setState(() {
        _snapshot = snap;
        _insights = SavingsInsights.fromJson(results[1] as Map<String, dynamic>);
        _link = results[2] == null
            ? null
            : MoMoLink.fromJson(results[2] as Map<String, dynamic>);
        _loading = false;
      });
      _fadeCtrl.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _loadError = _apiErr(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.surface1,
        onRefresh: _load,
        child: _loading
            ? _buildSkeleton()
            : _loadError != null
                ? _buildError(_loadError!)
                : _buildBody(),
      ),
      floatingActionButton: (_loading || _loadError != null) ? null : FloatingActionButton.extended(
        heroTag: 'savings_new_goal_fab',
        onPressed: _showAddGoalSheet,
        backgroundColor: AppColors.primary,
        foregroundColor: const Color(0xFFFFFFFF),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text('New Goal', style: GoogleFonts.hankenGrotesk(
            fontWeight: FontWeight.w800, fontSize: 13)),
        elevation: 0,
      ),
    );
  }

  Widget _buildBody() {
    final s = _snapshot!;
    final ins = _insights!;
    return FadeTransition(
      opacity: _fadeAnim,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          _buildAppBar(),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            sliver: SliverList(delegate: SliverChildListDelegate.fixed([
              Text('Savings Goals', style: AppTextStyles.h2),
              const SizedBox(height: 4),
              Text('Visualize your journey to financial freedom.',
                  style: AppTextStyles.bodyMuted),
              const SizedBox(height: 16),
              _buildHero(s, ins),
              const SizedBox(height: 16),
              _buildGoalsSection(s),
              const SizedBox(height: 16),
              _buildMetricsStrip(s, ins),
              const SizedBox(height: 14),
              if (_link == null) ...[
                _buildWalletBanner(),
                const SizedBox(height: 14),
              ],
              if (ins.upcoming.isNotEmpty) ...[
                _buildUpcomingCard(ins),
                const SizedBox(height: 14),
              ],
              if (ins.allocation.length >= 2) ...[
                _buildAllocationCard(ins),
                const SizedBox(height: 14),
              ],
              if (ins.recentActivity.isNotEmpty) ...[
                _buildActivityCard(ins),
                const SizedBox(height: 14),
              ],
              _buildTipCard(s, ins),
            ])),
          ),
        ],
      ),
    );
  }

  // ── App Bar ────────────────────────────────────────────────────────────────

  SliverAppBar _buildAppBar() => SliverAppBar(
    backgroundColor: AppColors.surface1,
    elevation: 0, pinned: true, toolbarHeight: 56,
    title: Text('Savings', style: GoogleFonts.hankenGrotesk(
        color: AppColors.text1, fontWeight: FontWeight.w800, fontSize: 18)),
    actions: [
      IconButton(
        icon:  Icon(Icons.refresh_rounded, color: AppColors.text2, size: 20),
        onPressed: _load,
      ),
    ],
  );

  // ── Hero ───────────────────────────────────────────────────────────────────

  Widget _buildHero(SavingsSnapshot s, SavingsInsights ins) {
    final pct = s.totalTarget > 0
        ? (s.totalSaved / s.totalTarget).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: AppColors.heroBrandGradient,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(children: [
        // Faint oversized wallet icon — decorative bento backdrop.
        Positioned(
          right: -16, bottom: -16,
          child: Icon(Icons.account_balance_wallet_rounded,
              size: 120, color: AppColors.heroFg.withOpacity(0.1)),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('TOTAL GOAL SAVINGS', style: GoogleFonts.hankenGrotesk(
              color: AppColors.heroFgMuted, fontSize: 11,
              letterSpacing: 1.2, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('${_fmt(s.totalSaved)} FCFA', style: AppTextStyles.balance),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.heroFg.withOpacity(0.16),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('${(pct * 100).toStringAsFixed(0)}% of total target',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: AppColors.heroFg)),
          ),
        ]),
      ]),
    );
  }

  // ── Metrics strip ──────────────────────────────────────────────────────────

  Widget _buildMetricsStrip(SavingsSnapshot s, SavingsInsights ins) {
    final activeGoals = s.goals.where((g) => !g.isCompleted).length;
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _MetricCard(
            icon: Icons.flag_rounded,
            label: 'Active Goals',
            value: activeGoals.toString(),
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          _MetricCard(
            icon: Icons.bolt_rounded,
            label: 'Active Plans',
            value: ins.activePlans.toString(),
            color: AppColors.accent,
          ),
          const SizedBox(width: 10),
          _MetricCard(
            icon: Icons.event_repeat_rounded,
            label: 'Next 7 days',
            value: '${_compact(ins.weeklyScheduled)} F',
            color: AppColors.info,
          ),
          const SizedBox(width: 10),
          _MetricCard(
            icon: Icons.emoji_events_rounded,
            label: 'Goals Done',
            value: ins.completedGoals.toString(),
            color: AppColors.purple,
          ),
        ],
      ),
    );
  }

  // ── Wallet banner ──────────────────────────────────────────────────────────

  Widget _buildWalletBanner() => GestureDetector(
    onTap: _showConnectWalletSheet,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.info.withOpacity(0.12),
          AppColors.info.withOpacity(0.04),
        ]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.info.withOpacity(0.25)),
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: AppColors.infoDim,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.account_balance_wallet_rounded,
              color: AppColors.info, size: 19),
        ),
        const SizedBox(width: 13),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Connect Mobile Money', style: GoogleFonts.hankenGrotesk(
              fontWeight: FontWeight.w700, fontSize: 13,
              color: AppColors.info)),
          const SizedBox(height: 2),
          Text('Link MTN or Orange via Campay to enable auto-save',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11, color: AppColors.text2)),
        ])),
        const Icon(Icons.arrow_forward_rounded,
            size: 18, color: AppColors.info),
      ]),
    ),
  );


  // ── Upcoming auto-saves ────────────────────────────────────────────────────

  Widget _buildUpcomingCard(SavingsInsights ins) => NkapCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.event_repeat_rounded,
            color: AppColors.info, size: 18),
        const SizedBox(width: 8),
        Text('Upcoming auto-saves', style: GoogleFonts.hankenGrotesk(
            fontWeight: FontWeight.w800, fontSize: 14,
            color: AppColors.text1)),
        const Spacer(),
        Text('${_fmt(ins.weeklyScheduled)} FCFA · 7d',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 11, color: AppColors.text3,
                fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 12),
      ...ins.upcoming.take(3).map((u) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(child: Text(u.goalEmoji,
                style: const TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(u.goalName, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: AppColors.text1)),
            const SizedBox(height: 2),
            Text('${_freqShort(u.frequency)} · ${_relativeTime(u.nextRunAt.toLocal())}',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 11, color: AppColors.text3)),
          ])),
          Text('${_fmt(u.amount)} F',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 13, fontWeight: FontWeight.w800,
                  color: AppColors.info)),
        ]),
      )),
      if (ins.upcoming.length > 3)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('+ ${ins.upcoming.length - 3} more in the next week',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11, color: AppColors.text3,
                  fontStyle: FontStyle.italic)),
        ),
    ]),
  );

  // ── Allocation donut ───────────────────────────────────────────────────────

  Widget _buildAllocationCard(SavingsInsights ins) {
    const palette = [
      AppColors.primary, AppColors.info, AppColors.accent,
      AppColors.purple, AppColors.success,
      Color(0xFFEC407A), Color(0xFFFF7043),
    ];
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < ins.allocation.length; i++) {
      final a = ins.allocation[i];
      sections.add(PieChartSectionData(
        value: a.percentOfTotal,
        color: palette[i % palette.length],
        radius: 22,
        showTitle: false,
      ));
    }
    return NkapCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.donut_large_rounded,
              color: AppColors.purple, size: 18),
          const SizedBox(width: 8),
          Text('Allocation', style: GoogleFonts.hankenGrotesk(
              fontWeight: FontWeight.w800, fontSize: 14,
              color: AppColors.text1)),
          const Spacer(),
          Text('Across ${ins.allocation.length} goals',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11, color: AppColors.text3)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          SizedBox(
            width: 110, height: 110,
            child: PieChart(PieChartData(
              sections: sections,
              centerSpaceRadius: 32,
              sectionsSpace: 2,
              startDegreeOffset: -90,
            )),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(children: [
            for (var i = 0; i < ins.allocation.length && i < 5; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: palette[i % palette.length],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    '${ins.allocation[i].goalEmoji} ${ins.allocation[i].goalName}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 12, color: AppColors.text2,
                        fontWeight: FontWeight.w600),
                  )),
                  Text('${ins.allocation[i].percentOfTotal.toStringAsFixed(0)}%',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 12, fontWeight: FontWeight.w800,
                          color: AppColors.text1)),
                ]),
              ),
          ])),
        ]),
      ]),
    );
  }

  // ── Goals section ──────────────────────────────────────────────────────────

  Widget _buildGoalsSection(SavingsSnapshot s) {
    if (s.goals.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border1),
        ),
        child: Column(children: [
           Icon(Icons.savings_outlined,
              size: 36, color: AppColors.text3),
          const SizedBox(height: 12),
          Text('No savings goals yet',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: AppColors.text1)),
          const SizedBox(height: 4),
          Text('Tap "New Goal" to set your first target.',
              textAlign: TextAlign.center,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 12, color: AppColors.text3)),
        ]),
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            const Icon(Icons.flag_rounded, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Text('Your Goals', style: GoogleFonts.hankenGrotesk(
                fontWeight: FontWeight.w800, fontSize: 14,
                color: AppColors.text1)),
          ]),
          Text('${s.goals.length} total · ${s.goals.where((g) => !g.isCompleted).length} active',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11, color: AppColors.text3)),
        ]),
      ),
      ...s.goals.map(_buildGoalCard),
    ]);
  }

  Widget _buildGoalCard(SavingsGoal g) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: GestureDetector(
      onTap: () => _showGoalDetail(g),
      child: NkapCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircularPercentIndicator(
              radius: 36, lineWidth: 5,
              percent: g.progress,
              center: Text(g.emoji, style: const TextStyle(fontSize: 18)),
              progressColor: g.color,
              backgroundColor: AppColors.border1,
              circularStrokeCap: CircularStrokeCap.round,
              animation: true, animationDuration: 800,
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(g.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.hankenGrotesk(
                        fontWeight: FontWeight.w700, fontSize: 13,
                        color: AppColors.text1))),
                const SizedBox(width: 6),
                Text('${g.percent.toStringAsFixed(0)}%',
                    style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w800,
                        fontSize: 14, color: g.color)),
              ]),
              const SizedBox(height: 4),
              Text('${_fmt(g.current)} / ${_fmt(g.target)} FCFA',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 11, color: AppColors.text3)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: g.progress, minHeight: 5,
                  backgroundColor: AppColors.border1,
                  valueColor: AlwaysStoppedAnimation(g.color),
                ),
              ),
            ])),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _GoalTag(
              icon: g.isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
              label: g.isLocked ? 'Locked' : 'Unlocked',
              color: g.isLocked ? AppColors.accent : AppColors.primary,
            ),
            const SizedBox(width: 6),
            if (g.isCompleted)
              _GoalTag(icon: Icons.emoji_events_rounded,
                  label: 'Done', color: AppColors.purple)
            else if (g.deadline != null) ...[
              _deadlineTag(g.deadline!),
              const SizedBox(width: 6),
              if (g.monthsLeft > 0)
                _GoalTag(
                  icon: Icons.schedule_rounded,
                  label: 'ETA ${g.monthsLeft}mo',
                  color: AppColors.info,
                ),
            ] else if (g.monthsLeft > 0)
              _GoalTag(
                icon: Icons.schedule_rounded,
                label: 'ETA ${g.monthsLeft}mo',
                color: AppColors.info,
              )
            else
              _GoalTag(
                icon: Icons.bolt_outlined,
                label: 'No plan',
                color: AppColors.text3,
              ),
            const Spacer(),
            Text(
              g.isCompleted
                  ? '🎉 Reached!'
                  : '${_fmt(g.remaining)} FCFA left',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11, color: AppColors.text3,
                  fontWeight: FontWeight.w600),
            ),
          ]),
        ]),
      ),
    ),
  );

  // ── Activity feed ──────────────────────────────────────────────────────────

  Widget _buildActivityCard(SavingsInsights ins) => NkapCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
         Icon(Icons.receipt_long_rounded,
            color: AppColors.text2, size: 18),
        const SizedBox(width: 8),
        Text('Recent activity', style: GoogleFonts.hankenGrotesk(
            fontWeight: FontWeight.w800, fontSize: 14,
            color: AppColors.text1)),
      ]),
      const SizedBox(height: 12),
      ...ins.recentActivity.take(5).map((a) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          _ActivityStatusIcon(status: a.status),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(a.goalEmoji ?? '🎯',
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Expanded(child: Text(a.goalName ?? 'Auto-save',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: AppColors.text1))),
            ]),
            const SizedBox(height: 2),
            Text(_activitySubtitle(a),
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 11, color: AppColors.text3)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${_fmt(a.amount)} ${a.currency}',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: _activityStatusColor(a.status))),
            const SizedBox(height: 2),
            Text(_activityStatusLabel(a.status),
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 10, color: AppColors.text3,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6)),
          ]),
        ]),
      )),
    ]),
  );

  String _activitySubtitle(ActivityItem a) {
    final when = a.completedAt ?? a.initiatedAt;
    final base = _relativeTime(when.toLocal());
    if (a.status == 'FAILED' && a.reason != null && a.reason!.isNotEmpty) {
      return '$base · ${a.reason}';
    }
    return base;
  }

  String _activityStatusLabel(String s) => switch (s) {
        'SUCCESSFUL' => 'SAVED',
        'PENDING'    => 'PENDING',
        'FAILED'     => 'FAILED',
        _            => s.toUpperCase(),
      };

  Color _activityStatusColor(String s) => switch (s) {
        'SUCCESSFUL' => AppColors.primary,
        'PENDING'    => AppColors.info,
        'FAILED'     => AppColors.danger,
        _            => AppColors.text2,
      };

  // ── Tip card ───────────────────────────────────────────────────────────────

  Widget _buildTipCard(SavingsSnapshot s, SavingsInsights ins) {
    final tip = _personalizedTip(s, ins);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.purple.withOpacity(0.1),
          AppColors.purple.withOpacity(0.03),
        ]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.purple.withOpacity(0.2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppColors.purpleDim,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppColors.purple.withOpacity(0.3)),
          ),
          child: const Icon(Icons.lightbulb_rounded,
              color: AppColors.purple, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tip for you', style: GoogleFonts.hankenGrotesk(
              fontWeight: FontWeight.w800, fontSize: 12,
              color: AppColors.purple)),
          const SizedBox(height: 4),
          Text(tip, style: GoogleFonts.hankenGrotesk(
              fontSize: 12, color: AppColors.text2, height: 1.5)),
        ])),
      ]),
    );
  }

  String _personalizedTip(SavingsSnapshot s, SavingsInsights ins) {
    if (s.goals.isEmpty) {
      return 'Start by creating your first goal. An emergency fund of 3 months of expenses is a great target.';
    }
    if (_link == null) {
      return 'Connect your MTN or Orange wallet to unlock automatic saving — no more relying on willpower.';
    }
    if (ins.activePlans == 0) {
      return 'You have goals but no auto-save plans yet. Tap any goal → "Set Up Auto-Save" to start.';
    }
    final losing = ins.recentActivity.where((a) => a.status == 'FAILED').length;
    if (losing >= 2) {
      return '$losing recent auto-saves failed. Check your MoMo balance or update the linked number.';
    }
    if (ins.monthlyDeltaPct < 0) {
      return "You're saving ${ins.monthlyDeltaPct.abs().toStringAsFixed(0)}% less than last month. Consider bumping a plan up by 5% to get back on track.";
    }
    final slowestGoal = s.goals
        .where((g) => !g.isCompleted && g.monthsLeft > 0)
        .toList()
      ..sort((a, b) => b.monthsLeft.compareTo(a.monthsLeft));
    if (slowestGoal.isNotEmpty && slowestGoal.first.monthsLeft > 12) {
      final g = slowestGoal.first;
      return '${g.name} will take ${g.monthsLeft} months at your current rate. Increase its auto-save % to reach it sooner.';
    }
    return "You're on track. Keep it up — small, consistent saves beat occasional big ones.";
  }

  // ── Add Goal Sheet ─────────────────────────────────────────────────────────

  void _showAddGoalSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _NewGoalWizard(
        walletLabel: _link == null
            ? null
            : '${_link!.provider} · ${_link!.phone}',
        onCreated: () async {
          if (!mounted) return;
          _toast(context, 'Goal created!');
          await _load();
        },
      ),
    );
  }

  // ── Goal Detail Sheet (existing per-goal plan management) ─────────────────

  void _showGoalDetail(SavingsGoal g) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _GoalDetailSheet(
        goal: g,
        hasWallet: _link?.verified ?? false,
        onChanged: _load,
        onPromptConnectWallet: _showConnectWalletSheet,
      ),
    );
  }

  void _showConnectWalletSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ConnectWalletSheet(
        existing: _link,
        onChanged: _load,
      ),
    );
  }

  // ── Skeleton + Error ───────────────────────────────────────────────────────

  Widget _buildSkeleton() => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
    children: [
      Shimmer.fromColors(
        baseColor: AppColors.surface2,
        highlightColor: AppColors.surface3,
        child: Column(children: [
          Container(height: 180, decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(22))),
          const SizedBox(height: 14),
          Container(height: 100, decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(18))),
          const SizedBox(height: 14),
          Container(height: 230, decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(20))),
          const SizedBox(height: 14),
          Container(height: 160, decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(20))),
          const SizedBox(height: 14),
          ...List.generate(2, (_) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(height: 110, decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(20))),
          )),
        ]),
      ),
    ],
  );

  Widget _buildError(String msg) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 120),
      Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.danger, size: 36),
            const SizedBox(height: 12),
            Text("Couldn't load savings",
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 16, fontWeight: FontWeight.w800,
                    color: AppColors.text1)),
            const SizedBox(height: 6),
            Text(msg, textAlign: TextAlign.center,
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 20),
            NkapButton(label: 'Retry', onTap: _load),
          ]),
        ),
      ),
    ],
  );
}

// ─── Hero micro-stat ─────────────────────────────────────────────────────────

class _MicroStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MicroStat({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(label, style: GoogleFonts.hankenGrotesk(
        fontSize: 9.5, color: AppColors.text3,
        fontWeight: FontWeight.w700, letterSpacing: 0.8)),
    const SizedBox(height: 4),
    Text(value, style: GoogleFonts.hankenGrotesk(
        fontSize: 13.5, color: color,
        fontWeight: FontWeight.w800)),
  ]);
}

// ─── Metric card ─────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _MetricCard({
    required this.icon, required this.label,
    required this.value, required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: 132,
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border1),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
      Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: GoogleFonts.hankenGrotesk(
            fontSize: 18, fontWeight: FontWeight.w800,
            color: AppColors.text1, height: 1)),
        const SizedBox(height: 3),
        Text(label, style: GoogleFonts.hankenGrotesk(
            fontSize: 11, color: AppColors.text3,
            fontWeight: FontWeight.w600)),
      ]),
    ]),
  );
}

// ─── Goal tag (status chip) ──────────────────────────────────────────────────

/// Builds an urgency-coloured tag for a goal's deadline.
/// Past due → red; ≤7 days → amber; ≤30 days → primary; otherwise neutral info.
Widget _deadlineTag(DateTime deadline) {
  final days = deadline.difference(DateTime.now()).inDays;
  late final IconData icon;
  late final Color color;
  late final String label;
  if (days < 0) {
    icon = Icons.error_outline_rounded;
    color = AppColors.danger;
    label = 'Past due';
  } else if (days == 0) {
    icon = Icons.today_rounded;
    color = AppColors.danger;
    label = 'Due today';
  } else if (days <= 7) {
    icon = Icons.event_busy_rounded;
    color = AppColors.accent;
    label = '$days day${days == 1 ? '' : 's'} left';
  } else if (days <= 30) {
    icon = Icons.event_rounded;
    color = AppColors.primary;
    label = '$days days left';
  } else {
    icon = Icons.event_available_rounded;
    color = AppColors.info;
    final months = (days / 30).round();
    label = months <= 1 ? '$days days left' : '~$months mo left';
  }
  return _GoalTag(icon: icon, label: label, color: color);
}

class _GoalTag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _GoalTag({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 11, color: color),
      const SizedBox(width: 4),
      Text(label, style: GoogleFonts.hankenGrotesk(
          fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    ]),
  );
}

// ─── Activity status icon ────────────────────────────────────────────────────

class _ActivityStatusIcon extends StatelessWidget {
  final String status;
  const _ActivityStatusIcon({required this.status});
  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status) {
      'SUCCESSFUL' => (Icons.check_rounded, AppColors.primary),
      'PENDING'    => (Icons.schedule_rounded, AppColors.info),
      'FAILED'     => (Icons.close_rounded, AppColors.danger),
      _            => (Icons.help_outline_rounded, AppColors.text3),
    };
    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }
}

// ─── Goal Detail Sheet ───────────────────────────────────────────────────────

class _GoalDetailSheet extends StatefulWidget {
  final SavingsGoal goal;
  final bool hasWallet;
  final VoidCallback onChanged;
  final VoidCallback onPromptConnectWallet;
  const _GoalDetailSheet({
    required this.goal, required this.hasWallet,
    required this.onChanged, required this.onPromptConnectWallet,
  });
  @override
  State<_GoalDetailSheet> createState() => _GoalDetailSheetState();
}

class _GoalDetailSheetState extends State<_GoalDetailSheet> {
  AutoSavePlan? _plan;
  bool _loadingPlan = true;
  bool _busy = false;

  @override
  void initState() { super.initState(); _loadPlan(); }

  Future<void> _loadPlan() async {
    try {
      final res = await ApiService.getAutoSavePlan(widget.goal.id);
      if (!mounted) return;
      setState(() {
        _plan = res == null
            ? null
            : AutoSavePlan.fromJson(res['plan'] as Map<String, dynamic>);
        _loadingPlan = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _plan = null; _loadingPlan = false; });
    }
  }

  Future<void> _togglePlanActive() async {
    if (_plan == null) return;
    setState(() => _busy = true);
    try {
      final res = await ApiService.updateAutoSavePlan(
        goalId: widget.goal.id, active: !_plan!.active,
      );
      setState(() { _plan = AutoSavePlan.fromJson(res); _busy = false; });
      widget.onChanged();
    } catch (e) {
      setState(() => _busy = false);
      _toast(context, _apiErr(e), error: true);
    }
  }

  Future<void> _cancelPlan() async {
    setState(() => _busy = true);
    try {
      await ApiService.deleteAutoSavePlan(widget.goal.id);
      setState(() { _plan = null; _busy = false; });
      _toast(context, 'Auto-save cancelled.');
      widget.onChanged();
    } catch (e) {
      setState(() => _busy = false);
      _toast(context, _apiErr(e), error: true);
    }
  }

  Future<void> _withdraw() async {
    setState(() => _busy = true);
    try {
      final res = await ApiService.withdrawGoal(widget.goal.id);
      if (!mounted) return;
      Navigator.pop(context);
      _toast(context,
          'Withdrew ${_fmt((res['payout'] as num).toDouble())} FCFA '
          '(penalty ${_fmt((res['penalty'] as num).toDouble())})');
      widget.onChanged();
    } catch (e) {
      setState(() => _busy = false);
      _toast(context, _apiErr(e), error: true);
    }
  }

  Future<void> _deleteGoal() async {
    setState(() => _busy = true);
    try {
      await ApiService.deleteGoal(widget.goal.id);
      if (!mounted) return;
      Navigator.pop(context);
      _toast(context, 'Goal deleted.');
      widget.onChanged();
    } catch (e) {
      setState(() => _busy = false);
      _toast(context, _apiErr(e), error: true);
    }
  }

  void _openPlanSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AutoSavePlanSheet(
        goal: widget.goal, existing: _plan,
      ),
    );
    if (created == true) {
      await _loadPlan();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.goal;
    return Container(
      decoration:  BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _DragHandle(),
          const SizedBox(height: 20),
          Text(g.emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 10),
          Text(g.name, style: GoogleFonts.hankenGrotesk(
              fontSize: 20, fontWeight: FontWeight.w800,
              color: AppColors.text1)),
          const SizedBox(height: 6),
          Text('${g.percent.toStringAsFixed(0)}% Complete',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 13, color: g.color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          CircularPercentIndicator(
            radius: 60, lineWidth: 8,
            percent: g.progress,
            center: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_fmt(g.current), style: GoogleFonts.hankenGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w800,
                  color: AppColors.text1)),
              Text('FCFA', style: GoogleFonts.hankenGrotesk(
                  fontSize: 10, color: AppColors.text3)),
            ]),
            progressColor: g.color,
            backgroundColor: AppColors.border1,
            circularStrokeCap: CircularStrokeCap.round,
            animation: true,
          ),
          const SizedBox(height: 20),
          _DetailRow(label: 'Target',    value: '${_fmt(g.target)} FCFA'),
          _DetailRow(label: 'Saved',     value: '${_fmt(g.current)} FCFA'),
          _DetailRow(label: 'Remaining', value: '${_fmt(g.remaining)} FCFA'),
          _DetailRow(label: 'Status',
              value: g.isLocked ? '🔒 Locked' : '🔓 Unlocked'),
          if (g.deadline != null)
            _DetailRow(label: 'Deadline',
                value: _formatDeadline(g.deadline!)),
          if (g.note != null && g.note!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border1),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                 Icon(Icons.format_quote_rounded,
                    size: 16, color: AppColors.text3),
                const SizedBox(width: 8),
                Expanded(child: Text(g.note!,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 12, color: AppColors.text2,
                        height: 1.4, fontStyle: FontStyle.italic))),
              ]),
            ),
          ],
          const SizedBox(height: 20),
          _buildAutoSaveSection(),
          const SizedBox(height: 20),
          if (!g.isCompleted) Row(children: [
            Expanded(child: NkapButton(
              label: 'Withdraw', outlined: true,
              color: AppColors.danger,
              loading: _busy,
              onTap: _busy ? null : _confirmWithdraw,
            )),
            const SizedBox(width: 12),
            Expanded(child: NkapButton(
              label: _plan == null ? 'Set Up Auto-Save' : 'Edit Plan',
              icon: Icons.bolt_rounded,
              onTap: _busy ? null : () {
                if (!widget.hasWallet) {
                  Navigator.pop(context);
                  widget.onPromptConnectWallet();
                  return;
                }
                _openPlanSheet();
              },
            )),
          ]) else NkapButton(
            label: 'Delete Goal',
            outlined: true,
            color: AppColors.danger,
            onTap: _busy ? null : _confirmDelete,
          ),
        ]),
      ),
    );
  }

  Widget _buildAutoSaveSection() {
    if (_loadingPlan) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: CircularProgressIndicator(strokeWidth: 2,
            color: AppColors.primary),
      );
    }
    if (_plan == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border1),
        ),
        child: Row(children: [
           Icon(Icons.bolt_outlined, color: AppColors.text3, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(
              'No auto-save on this goal yet. Set one up to save automatically.',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 12, color: AppColors.text3))),
        ]),
      );
    }
    final p = _plan!;
    final next = p.nextRunAt.toLocal();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryDim,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryMid),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.bolt_rounded, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Text('Auto-Save Plan', style: GoogleFonts.hankenGrotesk(
              fontSize: 13, fontWeight: FontWeight.w800,
              color: AppColors.primary)),
          const Spacer(),
          NkapChip(
            label: p.active ? 'ACTIVE' : 'PAUSED',
            color: p.active ? AppColors.primary : AppColors.text3,
            dimColor: p.active ? AppColors.primaryDim : AppColors.border2,
          ),
        ]),
        const SizedBox(height: 10),
        Text('${_fmt(p.amount)} FCFA · ${_freqShort(p.frequency)} · ${p.percent}%',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 13, fontWeight: FontWeight.w700,
                color: AppColors.text1)),
        const SizedBox(height: 4),
        Text(
          p.active
              ? 'Next run: ${next.year}-${_pad2(next.month)}-${_pad2(next.day)} ${_pad2(next.hour)}:${_pad2(next.minute)}'
              : 'Paused — resume to keep saving',
          style: GoogleFonts.hankenGrotesk(fontSize: 11, color: AppColors.text3),
        ),
        if (p.consecutiveFailures > 0) ...[
          const SizedBox(height: 4),
          Text('⚠ ${p.consecutiveFailures} recent failure${p.consecutiveFailures != 1 ? "s" : ""}',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11, color: AppColors.danger,
                  fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: NkapButton(
            label: p.active ? 'Pause' : 'Resume',
            outlined: true,
            loading: _busy,
            onTap: _busy ? null : _togglePlanActive,
          )),
          const SizedBox(width: 8),
          Expanded(child: NkapButton(
            label: 'Cancel',
            outlined: true,
            color: AppColors.danger,
            onTap: _busy ? null : _cancelPlan,
          )),
        ]),
      ]),
    );
  }

  String _pad2(int n) => n.toString().padLeft(2, '0');

  void _confirmWithdraw() => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface2,
      title: Text('Withdraw early?', style: GoogleFonts.hankenGrotesk(
          fontWeight: FontWeight.w800, color: AppColors.text1)),
      content: Text(
        'Early withdrawal applies a 10% penalty. Your progress will reset to zero.',
        style: GoogleFonts.hankenGrotesk(color: AppColors.text2, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Keep saving', style: GoogleFonts.hankenGrotesk(color: AppColors.text2)),
        ),
        TextButton(
          onPressed: () { Navigator.pop(context); _withdraw(); },
          child: Text('Withdraw', style: GoogleFonts.hankenGrotesk(
              color: AppColors.danger, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );

  void _confirmDelete() => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface2,
      title: Text('Delete goal?', style: GoogleFonts.hankenGrotesk(
          fontWeight: FontWeight.w800, color: AppColors.text1)),
      content: Text(
        'This will remove the goal and return any saved funds.',
        style: GoogleFonts.hankenGrotesk(color: AppColors.text2, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.hankenGrotesk(color: AppColors.text2)),
        ),
        TextButton(
          onPressed: () { Navigator.pop(context); _deleteGoal(); },
          child: Text('Delete', style: GoogleFonts.hankenGrotesk(
              color: AppColors.danger, fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

// ─── Connect Wallet Sheet ────────────────────────────────────────────────────

class _ConnectWalletSheet extends StatefulWidget {
  final MoMoLink? existing;
  final VoidCallback onChanged;
  const _ConnectWalletSheet({this.existing, required this.onChanged});
  @override
  State<_ConnectWalletSheet> createState() => _ConnectWalletSheetState();
}

class _ConnectWalletSheetState extends State<_ConnectWalletSheet> {
  late final TextEditingController _phoneCtrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _phoneCtrl = TextEditingController(text: widget.existing?.phone ?? '');
  }

  @override
  void dispose() { _phoneCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 9) {
      _toast(context, 'Enter a valid phone number.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiService.linkMoMo(phone);
      if (!mounted) return;
      Navigator.pop(context);
      _toast(context, 'Mobile money wallet linked.');
      widget.onChanged();
    } catch (e) {
      setState(() => _busy = false);
      _toast(context, _apiErr(e), error: true);
    }
  }

  Future<void> _unlink() async {
    setState(() => _busy = true);
    try {
      await ApiService.unlinkMoMo();
      if (!mounted) return;
      Navigator.pop(context);
      _toast(context, 'Wallet unlinked. Auto-save paused.');
      widget.onChanged();
    } catch (e) {
      setState(() => _busy = false);
      _toast(context, _apiErr(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _DragHandle(),
          const SizedBox(height: 16),
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: AppColors.infoDim,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.account_balance_wallet_rounded,
                color: AppColors.info, size: 26),
          ),
          const SizedBox(height: 14),
          Text(widget.existing == null ? 'Connect Mobile Money' : 'Manage Wallet',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  color: AppColors.text1)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Link your MTN MoMo or Orange Money number via Campay. We never see your PIN — you approve every transaction inside the operator\'s own flow.',
              textAlign: TextAlign.center,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 12, color: AppColors.text3, height: 1.5),
            ),
          ),
          const SizedBox(height: 22),
          _SheetField(
            controller: _phoneCtrl,
            label: 'Mobile money number',
            hint: '237 6XX XXX XXX',
            icon: Icons.phone_rounded,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('MTN: 67/65/68 · Orange: 69/65',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 10.5, color: AppColors.text3)),
          ),
          const SizedBox(height: 24),
          NkapButton(
            label: widget.existing == null ? 'Link Wallet' : 'Update',
            icon: Icons.check_rounded,
            loading: _busy,
            onTap: _busy ? null : _submit,
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: 10),
            NkapButton(
              label: 'Unlink',
              outlined: true,
              color: AppColors.danger,
              onTap: _busy ? null : _unlink,
            ),
          ],
        ]),
      ),
    );
  }
}

// ─── Auto-Save Plan Setup Sheet (1..100 via custom input) ────────────────────

class _AutoSavePlanSheet extends StatefulWidget {
  final SavingsGoal goal;
  final AutoSavePlan? existing;
  const _AutoSavePlanSheet({required this.goal, this.existing});
  @override
  State<_AutoSavePlanSheet> createState() => _AutoSavePlanSheetState();
}

class _AutoSavePlanSheetState extends State<_AutoSavePlanSheet> {
  late String _frequency;
  late final TextEditingController _amountCtrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _frequency = widget.existing?.frequency ?? 'weekly';
    _amountCtrl = TextEditingController(
      text: widget.existing?.amount.toStringAsFixed(0) ?? '',
    );
  }

  @override
  void dispose() { _amountCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount < 100) {
      _toast(context, 'Enter an amount of at least 100 FCFA.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      if (widget.existing == null) {
        await ApiService.createAutoSavePlan(
          goalId: widget.goal.id,
          percent: 1, frequency: _frequency,
          amount: amount,
        );
      } else {
        await ApiService.updateAutoSavePlan(
          goalId: widget.goal.id,
          percent: 1, frequency: _frequency,
          amount: amount,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _busy = false);
      _toast(context, _apiErr(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _DragHandle(),
          const SizedBox(height: 16),
          Text(widget.existing == null ? 'Set Up Auto-Save' : 'Edit Auto-Save',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  color: AppColors.text1)),
          const SizedBox(height: 4),
          Text('For ${widget.goal.emoji} ${widget.goal.name}',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 12, color: AppColors.text3)),
          const SizedBox(height: 22),

          Align(alignment: Alignment.centerLeft,
            child: Text('Frequency', style: GoogleFonts.hankenGrotesk(
                fontSize: 12, fontWeight: FontWeight.w700,
                color: AppColors.text2))),
          const SizedBox(height: 8),
          Row(children: [
            _FreqBtn(label: 'Daily',   value: 'daily',
                selected: _frequency == 'daily',
                onTap: () => setState(() => _frequency = 'daily')),
            const SizedBox(width: 8),
            _FreqBtn(label: 'Weekly',  value: 'weekly',
                selected: _frequency == 'weekly',
                onTap: () => setState(() => _frequency = 'weekly')),
            const SizedBox(width: 8),
            _FreqBtn(label: 'Monthly', value: 'monthly',
                selected: _frequency == 'monthly',
                onTap: () => setState(() => _frequency = 'monthly')),
          ]),
          const SizedBox(height: 18),

          Align(alignment: Alignment.centerLeft,
            child: Text('Amount per ${_frequency.replaceAll("ly", "")} run (FCFA)',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: AppColors.text2))),
          const SizedBox(height: 8),
          _SheetField(
            controller: _amountCtrl,
            label: '',
            hint: 'e.g. 5000',
            icon: Icons.payments_rounded,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 6),
          Text(
            'Each run, NkapSave asks your mobile money operator to debit this amount via Campay. '
            'You approve each payment with your PIN on your phone.',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 11, color: AppColors.text3, height: 1.5),
          ),
          const SizedBox(height: 24),
          NkapButton(
            label: widget.existing == null ? 'Start Auto-Save' : 'Update Plan',
            icon: Icons.bolt_rounded,
            loading: _busy,
            onTap: _busy ? null : _submit,
          ),
        ]),
      ),
    );
  }
}

// ─── Small UI helpers ────────────────────────────────────────────────────────

class _FreqBtn extends StatelessWidget {
  final String label, value;
  final bool selected;
  final VoidCallback onTap;
  const _FreqBtn({required this.label, required this.value,
      required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryDim : AppColors.surface3,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? AppColors.primaryMid : AppColors.border2),
        ),
        child: Center(child: Text(label, style: GoogleFonts.hankenGrotesk(
            fontSize: 12.5, fontWeight: FontWeight.w700,
            color: selected ? AppColors.primary : AppColors.text2))),
      ),
    ),
  );
}

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 40, height: 4,
      decoration: BoxDecoration(
          color: AppColors.border2,
          borderRadius: BorderRadius.circular(99)),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final String label, value;
  const _DetailRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: GoogleFonts.hankenGrotesk(
          fontSize: 13, color: AppColors.text3)),
      Text(value, style: GoogleFonts.hankenGrotesk(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: AppColors.text1)),
    ]),
  );
}

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final IconData icon;
  final TextInputType? keyboardType;
  const _SheetField({required this.controller, required this.label,
      required this.hint, required this.icon, this.keyboardType});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (label.isNotEmpty) ...[
        Text(label, style: GoogleFonts.hankenGrotesk(
            fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text2)),
        const SizedBox(height: 7),
      ],
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: GoogleFonts.hankenGrotesk(fontSize: 14, color: AppColors.text1),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, size: 18, color: AppColors.text3),
        ),
      ),
    ],
  );
}

// ─── New Goal Wizard ─────────────────────────────────────────────────────────

class _NewGoalWizard extends StatefulWidget {
  final String? walletLabel;
  final Future<void> Function() onCreated;
  const _NewGoalWizard({required this.walletLabel, required this.onCreated});
  @override
  State<_NewGoalWizard> createState() => _NewGoalWizardState();
}

class _NewGoalWizardState extends State<_NewGoalWizard> {
  final _page = PageController();
  int _step = 0;

  // Step 1 ─ what & when
  String _emoji = '🎯';
  final _nameCtrl = TextEditingController();
  final _targetCtrl = TextEditingController();
  DateTime? _deadline;
  final _noteCtrl = TextEditingController();

  // Step 2 ─ how you save
  final _amountCtrl = TextEditingController();
  String _frequency = 'weekly';
  bool _reminder = true;

  bool _busy = false;
  static const _emojis = ['🎯','🏠','🚗','📱','✈️','🎓','💼','💍','🏋️','🌍','🛡️','💍','🍼','🎁'];

  @override
  void dispose() {
    _page.dispose();
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    _noteCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  String _fmtFcfa(double n) =>
      '${n.abs().toStringAsFixed(0).replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "${m[1]},")} FCFA';

  double get _target => double.tryParse(_targetCtrl.text.trim()) ?? 0;
  double get _amount => double.tryParse(_amountCtrl.text.trim()) ?? 0;
  int get _periodDays => switch (_frequency) {
    'daily'   => 1,
    'weekly'  => 7,
    'monthly' => 30,
    _ => 7,
  };

  // ── Validation per step ──────────────────────────────────────
  bool get _step1Valid =>
      _nameCtrl.text.trim().isNotEmpty &&
      _target > 0 &&
      _deadline != null &&
      _deadline!.isAfter(DateTime.now().subtract(const Duration(days: 1)));

  bool get _step2Valid => _amount >= 100;

  ({String label, bool onTrack, int daysToHit, int daysAhead, double needed})? _projection() {
    if (_target <= 0 || _amount <= 0 || _deadline == null) return null;
    final periodsNeeded = (_target / _amount).ceil();
    final daysToHit = periodsNeeded * _periodDays;
    final daysUntilDeadline = _deadline!.difference(DateTime.now()).inDays;
    final onTrack = daysToHit <= daysUntilDeadline;
    final periodsByDeadline = (daysUntilDeadline / _periodDays).floor();
    final neededPerPeriod = periodsByDeadline > 0 ? (_target / periodsByDeadline).ceilToDouble() : _target;
    return (
      label: _frequency,
      onTrack: onTrack,
      daysToHit: daysToHit,
      daysAhead: daysUntilDeadline - daysToHit,
      needed: neededPerPeriod,
    );
  }

  // ── Navigation ───────────────────────────────────────────────
  void _next() {
    if (_step == 0 && !_step1Valid) {
      _toast('Fill in name, target, and pick a deadline in the future.');
      return;
    }
    if (_step == 1 && !_step2Valid) {
      _toast('Enter a deduction amount of at least 100 FCFA.');
      return;
    }
    HapticFeedback.selectionClick();
    if (_step < 2) {
      setState(() => _step++);
      _page.animateToPage(_step,
          duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _step--);
    _page.animateToPage(_step,
        duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.hankenGrotesk(color: AppColors.text1)),
      backgroundColor: error ? AppColors.danger : AppColors.surface3,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    String? goalId;
    try {
      final res = await ApiService.createGoal(
        name: _nameCtrl.text.trim(),
        emoji: _emoji,
        target: _target,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        deadline: _deadline,
      );
      goalId = (res?['id'] ?? res?['goal_id'])?.toString();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(_friendlyError(e, fallback: 'Could not create the goal.'),
          error: true);
      return;
    }

    // Plan creation requires a verified MoMo wallet on the backend.
    // If we don't have one, save the goal alone and tell the user clearly —
    // they can configure the plan from goal details after linking their wallet.
    if (widget.walletLabel == null || goalId == null || goalId.isEmpty) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      await widget.onCreated();
      if (!mounted) return;
      _toast(widget.walletLabel == null
          ? 'Goal saved. Link your MoMo wallet to start auto-save deductions.'
          : 'Goal saved (auto-save plan not attached).');
      return;
    }

    try {
      await ApiService.createAutoSavePlan(
        goalId: goalId,
        percent: 1,
        frequency: _frequency,
        amount: _amount,
        reminderEnabled: _reminder,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop();
      await widget.onCreated();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(_friendlyError(e,
          fallback: 'Goal was created, but the auto-save plan failed. '
              'Open the goal and try Set Up Auto-Save again.'),
          error: true);
    }
  }

  String _friendlyError(Object e, {required String fallback}) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map) {
        final detail = data['detail'];
        if (detail is String && detail.isNotEmpty) return detail;
        if (detail is List && detail.isNotEmpty) {
          final first = detail.first;
          if (first is Map && first['msg'] is String) {
            return first['msg'] as String;
          }
        }
      }
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.96,
      expand: false,
      builder: (_, scroll) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(children: [
            _handle(),
            _topBar(),
            _progressStrip(),
            Expanded(
              child: PageView(
                controller: _page,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _step = i),
                children: [
                  _step1(scroll),
                  _step2(scroll),
                  _step3(scroll),
                ],
              ),
            ),
            _bottomBar(),
          ]),
        ),
      ),
    );
  }

  Widget _handle() => Container(
    margin: const EdgeInsets.only(top: 10, bottom: 6),
    width: 40, height: 4,
    decoration: BoxDecoration(
      color: AppColors.border3, borderRadius: BorderRadius.circular(99)),
  );

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
    child: Row(children: [
      Expanded(child: Text(
        _step == 0 ? 'New Savings Goal'
            : _step == 1 ? 'How you save'
            : 'Confirm',
        style: GoogleFonts.hankenGrotesk(
            fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.text1),
      )),
      IconButton(
        icon: Icon(Icons.close_rounded, color: AppColors.text2, size: 22),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ]),
  );

  Widget _progressStrip() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
    child: Row(children: List.generate(3, (i) {
      final active = i <= _step;
      return Expanded(child: Padding(
        padding: EdgeInsets.only(right: i == 2 ? 0 : 6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: 4,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.border2,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ));
    })),
  );

  // ── Step 1: what & when ──────────────────────────────────────
  Widget _step1(ScrollController scroll) => ListView(
    controller: scroll,
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    children: [
      _label('Choose an icon'),
      const SizedBox(height: 8),
      SizedBox(
        height: 52,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _emojis.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final sel = _emojis[i] == _emoji;
            return GestureDetector(
              onTap: () { HapticFeedback.selectionClick();
                setState(() => _emoji = _emojis[i]); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: sel ? AppColors.primaryDim : AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: sel ? AppColors.primary : AppColors.border2),
                ),
                child: Center(child: Text(_emojis[i],
                    style: const TextStyle(fontSize: 22))),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 16),
      _SheetField(controller: _nameCtrl, label: 'Goal Name',
          hint: 'e.g. Emergency Fund', icon: Icons.flag_rounded),
      const SizedBox(height: 14),
      _SheetField(controller: _targetCtrl, label: 'Target Amount (FCFA)',
          hint: 'e.g. 500000',
          icon: Icons.savings_rounded,
          keyboardType: TextInputType.number),
      const SizedBox(height: 14),
      _label('Deadline'),
      const SizedBox(height: 7),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _pickDeadline,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border2),
          ),
          child: Row(children: [
            Icon(Icons.event_rounded, size: 18, color: AppColors.text3),
            const SizedBox(width: 12),
            Expanded(child: Text(
              _deadline == null
                  ? 'Pick a date'
                  : '${_deadline!.day}/${_deadline!.month}/${_deadline!.year}'
                    ' (${_deadline!.difference(DateTime.now()).inDays} days from now)',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 14,
                  color: _deadline == null ? AppColors.text3 : AppColors.text1,
                  fontWeight: FontWeight.w600),
            )),
            Icon(Icons.chevron_right_rounded, color: AppColors.text3),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      _label('Why are you saving this? (optional)'),
      const SizedBox(height: 7),
      TextField(
        controller: _noteCtrl,
        maxLines: 3, maxLength: 140,
        style: GoogleFonts.hankenGrotesk(fontSize: 13.5, color: AppColors.text1),
        decoration: const InputDecoration(
          hintText: 'I\'ll remind you of this when motivation dips.',
          counterText: '',
        ),
      ),
      const SizedBox(height: 8),
    ],
  );

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now.add(const Duration(days: 90)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: Colors.black,
            surface: AppColors.surface2,
            onSurface: AppColors.text1,
          ),
          dialogBackgroundColor: AppColors.surface1,
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  // ── Step 2: how you save ─────────────────────────────────────
  Widget _step2(ScrollController scroll) => ListView(
    controller: scroll,
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
    children: [
      if (widget.walletLabel != null)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.primary.withOpacity(0.25)),
          ),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: AppColors.primaryDim, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primaryMid)),
              child: const Icon(Icons.account_balance_wallet_rounded,
                  size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Saving from', style: GoogleFonts.hankenGrotesk(
                  fontSize: 10, color: AppColors.text3, fontWeight: FontWeight.w700)),
              Text(widget.walletLabel!, style: GoogleFonts.hankenGrotesk(
                  fontSize: 13, color: AppColors.text1, fontWeight: FontWeight.w700)),
            ])),
          ]),
        )
      else
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accent.withOpacity(0.25)),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.accent, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'No verified MoMo wallet linked. We\'ll save the goal '
              'but skip the auto-save plan — link your wallet from the '
              'savings screen and set up the plan from the goal details.',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11.5, color: AppColors.text2, height: 1.4),
            )),
          ]),
        ),
      const SizedBox(height: 18),
      _label('Deduction Amount (FCFA)'),
      const SizedBox(height: 7),
      _SheetField(controller: _amountCtrl, label: '',
          hint: 'e.g. 5000',
          icon: Icons.payments_rounded,
          keyboardType: TextInputType.number),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final preset in const [1000.0, 2500.0, 5000.0, 10000.0, 25000.0])
          _amountPreset(preset),
      ]),
      const SizedBox(height: 22),
      _label('How often?'),
      const SizedBox(height: 8),
      Row(children: [
        _FreqBtn(label: 'Daily',   value: 'daily',
            selected: _frequency == 'daily',
            onTap: () => setState(() => _frequency = 'daily')),
        const SizedBox(width: 8),
        _FreqBtn(label: 'Weekly',  value: 'weekly',
            selected: _frequency == 'weekly',
            onTap: () => setState(() => _frequency = 'weekly')),
        const SizedBox(width: 8),
        _FreqBtn(label: 'Monthly', value: 'monthly',
            selected: _frequency == 'monthly',
            onTap: () => setState(() => _frequency = 'monthly')),
      ]),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border1),
        ),
        child: Row(children: [
          const Icon(Icons.notifications_active_rounded,
              size: 18, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Remind me before each deduction',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text1)),
            const SizedBox(height: 2),
            Text('A heads-up the day before so you can ensure funds are available.',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 11, color: AppColors.text3, height: 1.4)),
          ])),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: _reminder,
              activeColor: AppColors.accent,
              activeTrackColor: AppColors.accent.withOpacity(0.35),
              onChanged: (v) => setState(() => _reminder = v),
            ),
          ),
        ]),
      ),
    ],
  );

  Widget _amountPreset(double v) => InkWell(
    borderRadius: BorderRadius.circular(99),
    onTap: () { _amountCtrl.text = v.toStringAsFixed(0);
      HapticFeedback.selectionClick(); setState(() {}); },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface2, borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.border2),
      ),
      child: Text(_fmtFcfa(v),
          style: GoogleFonts.hankenGrotesk(
              color: AppColors.text2, fontSize: 11.5, fontWeight: FontWeight.w600)),
    ),
  );

  // ── Step 3: confirm with live projection ─────────────────────
  Widget _step3(ScrollController scroll) {
    final p = _projection();
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color: AppColors.primaryDim,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.primaryMid),
                ),
                child: Center(child: Text(_emoji,
                    style: const TextStyle(fontSize: 26))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_nameCtrl.text.trim().isEmpty ? '—' : _nameCtrl.text.trim(),
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text1)),
                const SizedBox(height: 2),
                Text('Target ${_fmtFcfa(_target)}',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 11.5, color: AppColors.text3)),
              ])),
            ]),
            const SizedBox(height: 14),
            _summaryRow(Icons.event_rounded, 'Deadline',
                _deadline == null
                    ? '—'
                    : '${_deadline!.day}/${_deadline!.month}/${_deadline!.year}'),
            _summaryRow(Icons.payments_rounded, 'Deduction',
                '${_fmtFcfa(_amount)} · ${_frequency[0].toUpperCase()}${_frequency.substring(1)}'),
            _summaryRow(Icons.notifications_active_rounded, 'Reminder',
                _reminder ? 'On — 1 day before' : 'Off'),
            if (_noteCtrl.text.trim().isNotEmpty)
              _summaryRow(Icons.format_quote_rounded, 'Note',
                  _noteCtrl.text.trim()),
          ]),
        ),
        const SizedBox(height: 14),
        if (p != null) _projectionCard(p),
      ],
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: AppColors.text3),
      const SizedBox(width: 9),
      SizedBox(
        width: 84,
        child: Text(label, style: GoogleFonts.hankenGrotesk(
            fontSize: 11.5, color: AppColors.text3, fontWeight: FontWeight.w600)),
      ),
      Expanded(child: Text(value, style: GoogleFonts.hankenGrotesk(
          fontSize: 12.5, color: AppColors.text1, fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _projectionCard(({String label, bool onTrack, int daysToHit, int daysAhead, double needed}) p) {
    final color = p.onTrack ? AppColors.primary : AppColors.accent;
    final periodLabel = _frequency == 'daily' ? 'days'
        : _frequency == 'weekly' ? 'weeks'
        : 'months';
    final periodsNeeded = _amount > 0 ? (_target / _amount).ceil() : 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          color.withOpacity(0.14), color.withOpacity(0.04),
        ]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(p.onTrack
              ? Icons.trending_up_rounded
              : Icons.warning_amber_rounded,
              color: color, size: 20),
          const SizedBox(width: 8),
          Text('Projection',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 12, color: color,
                  fontWeight: FontWeight.w800, letterSpacing: 1)),
        ]),
        const SizedBox(height: 10),
        if (p.onTrack)
          Text(
            'At ${_fmtFcfa(_amount)} $_frequency, you\'ll hit '
            '${_fmtFcfa(_target)} in $periodsNeeded $periodLabel — '
            '${p.daysAhead} ${p.daysAhead == 1 ? "day" : "days"} before your deadline. ✅',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 13, color: AppColors.text1, height: 1.5,
                fontWeight: FontWeight.w600),
          )
        else
          Text(
            'At this pace you won\'t make the deadline. '
            'Bump to about ${_fmtFcfa(p.needed)} $_frequency to hit '
            '${_fmtFcfa(_target)} on time. ⚠️',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 13, color: AppColors.text1, height: 1.5,
                fontWeight: FontWeight.w600),
          ),
      ]),
    );
  }

  Widget _label(String s) => Align(alignment: Alignment.centerLeft,
    child: Text(s, style: GoogleFonts.hankenGrotesk(
        fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text2)));

  // ── Bottom navigation ────────────────────────────────────────
  Widget _bottomBar() {
    final isLast = _step == 2;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          border: Border(top: BorderSide(color: AppColors.border1)),
        ),
        child: Row(children: [
          Expanded(
            flex: _step == 0 ? 0 : 1,
            child: _step == 0
                ? const SizedBox.shrink()
                : OutlinedButton(
                    onPressed: _busy ? null : _back,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.text2,
                      side: BorderSide(color: AppColors.border2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('Back',
                        style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700)),
                  ),
          ),
          if (_step != 0) const SizedBox(width: 10),
          Expanded(flex: 2,
            child: NkapButton(
              label: isLast ? 'Create Goal' : 'Next',
              icon: isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
              loading: _busy,
              onTap: _busy ? null : _next,
            ),
          ),
        ]),
      ),
    );
  }
}
