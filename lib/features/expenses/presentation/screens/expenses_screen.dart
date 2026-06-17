import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shimmer/shimmer.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/download_helper.dart';
import '../../../../core/widgets/nkap_card.dart';
import '../../../../core/widgets/nkap_button.dart';
import 'statements_screen.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _fmt(double n) => n.abs()
    .toStringAsFixed(0)
    .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

String _compact(double n) {
  if (n.abs() >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
  if (n.abs() >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
  if (n.abs() >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
  return n.toStringAsFixed(0);
}

Color _hexColor(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

String _apiErr(Object e, [String fallback = 'Something went wrong']) {
  if (e is DioException) {
    final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
    if (detail is String) return detail;
  }
  return fallback;
}

void _toast(BuildContext ctx, String msg, {bool error = false}) {
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
    content: Text(msg, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
    backgroundColor:
        (error ? AppColors.danger : AppColors.primary).withOpacity(0.9),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

// ─── Models ──────────────────────────────────────────────────────────────────

class Txn {
  final String id, name, category, txnType, dateLabel, isoDate, source;
  final double amount, signedAmount;
  final String? note, paymentMethod, location;
  final Color color;
  const Txn({
    required this.id, required this.name, required this.category,
    required this.txnType, required this.dateLabel, required this.isoDate,
    required this.source, required this.amount, required this.signedAmount,
    this.note, this.paymentMethod, this.location, required this.color,
  });
  factory Txn.fromJson(Map<String, dynamic> j) => Txn(
        id:            j['id']            as String,
        name:          j['name']          as String,
        category:      j['category']      as String,
        txnType:       j['txn_type']      as String,
        amount:        (j['amount']       as num).toDouble(),
        signedAmount:  (j['signed_amount'] as num).toDouble(),
        note:          j['note']          as String?,
        paymentMethod: j['payment_method'] as String?,
        location:      j['location']      as String?,
        dateLabel:     j['date_label']    as String,
        isoDate:       j['iso_date']      as String,
        color:         _hexColor(j['color_hex'] as String),
        source:        j['source']        as String? ?? 'manual',
      );
  bool get isIncome => txnType == 'INCOME';
}

class CatSummary {
  final String name, txnType;
  final double amount, percent, deltaPct;
  final Color color;
  const CatSummary({
    required this.name, required this.txnType,
    required this.amount, required this.percent,
    required this.deltaPct, required this.color,
  });
  factory CatSummary.fromJson(Map<String, dynamic> j) => CatSummary(
        name:     j['name']     as String,
        txnType:  j['txn_type'] as String,
        amount:   (j['amount']  as num).toDouble(),
        percent:  (j['percent'] as num).toDouble(),
        deltaPct: (j['delta_pct'] as num).toDouble(),
        color:    _hexColor(j['color_hex'] as String),
      );
}

class BudgetRow {
  final String category, status;
  final double target, spent, percent;
  const BudgetRow({
    required this.category, required this.status,
    required this.target, required this.spent, required this.percent,
  });
  factory BudgetRow.fromJson(Map<String, dynamic> j) => BudgetRow(
        category: j['category'] as String,
        target:   (j['target']  as num).toDouble(),
        spent:    (j['spent']   as num).toDouble(),
        percent:  (j['percent'] as num).toDouble(),
        status:   j['status']   as String,
      );
}

class ExpensesData {
  final double totalExpense, totalIncome, net;
  final double spendingDelta, incomeDelta, savingsRate;
  final List<CatSummary> expenseCats, incomeCats;
  final List<Txn> transactions;
  final List<BudgetRow> budgets;
  final List<String> insights;
  const ExpensesData({
    required this.totalExpense, required this.totalIncome, required this.net,
    required this.spendingDelta, required this.incomeDelta, required this.savingsRate,
    required this.expenseCats, required this.incomeCats,
    required this.transactions, required this.budgets, required this.insights,
  });
  factory ExpensesData.fromJson(Map<String, dynamic> j) {
    final cats = (j['categories'] as List).cast<Map<String, dynamic>>()
        .map(CatSummary.fromJson).toList();
    return ExpensesData(
      totalExpense:   (j['total_expense']    as num).toDouble(),
      totalIncome:    (j['total_income']     as num).toDouble(),
      net:            (j['net']              as num).toDouble(),
      spendingDelta:  (j['spending_delta']   as num).toDouble(),
      incomeDelta:    (j['income_delta']     as num).toDouble(),
      savingsRate:    (j['savings_rate']     as num).toDouble(),
      expenseCats:    cats.where((c) => c.txnType == 'EXPENSE').toList(),
      incomeCats:     cats.where((c) => c.txnType == 'INCOME').toList(),
      transactions:   (j['transactions'] as List).cast<Map<String, dynamic>>()
                          .map(Txn.fromJson).toList(),
      budgets:        (j['budgets'] as List).cast<Map<String, dynamic>>()
                          .map(BudgetRow.fromJson).toList(),
      insights:       (j['insights'] as List).cast<String>(),
    );
  }
}

class TrendPoint {
  final DateTime date;
  final double income, expense;
  const TrendPoint({required this.date, required this.income, required this.expense});
  factory TrendPoint.fromJson(Map<String, dynamic> j) => TrendPoint(
        date:    DateTime.parse(j['date'] as String),
        income:  (j['income']  as num).toDouble(),
        expense: (j['expense'] as num).toDouble(),
      );
}

class Meta {
  final List<String> expenseCategories, incomeCategories, paymentMethods;
  const Meta({
    required this.expenseCategories,
    required this.incomeCategories,
    required this.paymentMethods,
  });
  factory Meta.fromJson(Map<String, dynamic> j) => Meta(
        expenseCategories: (j['expense_categories'] as List).cast<String>(),
        incomeCategories:  (j['income_categories']  as List).cast<String>(),
        paymentMethods:    (j['payment_methods']    as List).cast<String>(),
      );
}

// ─── Filters ─────────────────────────────────────────────────────────────────

enum _Range { thisMonth, thisWeek, today, thisYear, last30 }

class _Filters {
  _Range range;
  String? txnType;       // null = both
  String? category;      // null/'All' = all
  String search;
  _Filters({this.range = _Range.thisMonth, this.txnType, this.category, this.search = ''});

  (DateTime, DateTime) get window {
    final now = DateTime.now();
    DateTime from;
    switch (range) {
      case _Range.today:
        from = DateTime(now.year, now.month, now.day);
        break;
      case _Range.thisWeek:
        from = now.subtract(Duration(days: now.weekday - 1));
        from = DateTime(from.year, from.month, from.day);
        break;
      case _Range.last30:
        from = now.subtract(const Duration(days: 30));
        break;
      case _Range.thisYear:
        from = DateTime(now.year, 1, 1);
        break;
      case _Range.thisMonth:
        from = DateTime(now.year, now.month, 1);
        break;
    }
    return (from, now);
  }

  String get rangeLabel => switch (range) {
        _Range.today     => 'Today',
        _Range.thisWeek  => 'This week',
        _Range.thisMonth => 'This month',
        _Range.last30    => 'Last 30 days',
        _Range.thisYear  => 'This year',
      };
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String? _error;
  ExpensesData? _data;
  List<TrendPoint> _trend = const [];
  Meta? _meta;
  final _filters = _Filters();
  final _searchCtrl = TextEditingController();
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
  void dispose() {
    _fadeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final (from, to) = _filters.window;
      final results = await Future.wait([
        ApiService.getExpenses(
          from: from, to: to,
          txnType: _filters.txnType,
          category: _filters.category,
          search: _filters.search.isEmpty ? null : _filters.search,
        ),
        ApiService.getExpenseTrend(days: 30),
        if (_meta == null) ApiService.getExpenseMeta()
          else Future.value(<String, dynamic>{}),
      ]);
      if (!mounted) return;
      setState(() {
        _data  = ExpensesData.fromJson(results[0] as Map<String, dynamic>);
        _trend = ((results[1] as Map<String, dynamic>)['points'] as List)
            .cast<Map<String, dynamic>>().map(TrendPoint.fromJson).toList();
        if (_meta == null) {
          _meta = Meta.fromJson(results[2] as Map<String, dynamic>);
        }
        _loading = false;
      });
      _fadeCtrl.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _apiErr(e, 'Could not load expenses. Pull to refresh.');
      });
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
            : _error != null
                ? _buildError(_error!)
                : _buildBody(),
      ),
      floatingActionButton: (_loading || _error != null) ? null : FloatingActionButton.extended(
        heroTag: 'expenses_add_fab',
        onPressed: () => _showAddSheet(),
        backgroundColor: AppColors.primary,
        foregroundColor: const Color(0xFFFFFFFF),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text('Add', style: AppTextStyles.h4
            .copyWith(color: const Color(0xFFFFFFFF))),
        elevation: 0,
      ),
    );
  }

  Widget _buildBody() {
    final d = _data!;
    return FadeTransition(
      opacity: _fadeAnim,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          _buildAppBar(),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            sliver: SliverList(delegate: SliverChildListDelegate.fixed([
              _buildHero(d),
              const SizedBox(height: 14),
              _buildMetricsStrip(d),
              const SizedBox(height: 14),
              _buildFilterBar(),
              const SizedBox(height: 14),
              if (d.expenseCats.isNotEmpty || d.incomeCats.isNotEmpty) ...[
                _buildBarChartCard(d),
                const SizedBox(height: 14),
              ],
              if (_trend.isNotEmpty) ...[
                _buildTrendCard(d),
                const SizedBox(height: 14),
              ],
              if (d.budgets.isNotEmpty) ...[
                _buildBudgetsCard(d),
                const SizedBox(height: 14),
              ] else ...[
                _buildBudgetsPromo(),
                const SizedBox(height: 14),
              ],
              _buildInsightsCard(d),
              const SizedBox(height: 14),
              _buildTransactionsHeader(d),
              const SizedBox(height: 8),
              if (d.transactions.isEmpty)
                _buildEmptyTxn()
              else
                ...d.transactions.map(_buildTxnRow),
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
    title: Text('Transactions', style: AppTextStyles.h2),
    actions: [
      PopupMenuButton<String>(
        icon:  Icon(Icons.download_rounded,
            color: AppColors.text2, size: 20),
        color: AppColors.surface2,
        onSelected: _exportAs,
        itemBuilder: (_) => [
          PopupMenuItem(value: 'inbox', child: Row(children: [
            const Icon(Icons.inbox_rounded,
                color: AppColors.primary, size: 18),
            const SizedBox(width: 10),
            Text('My statements', style: AppTextStyles.h4),
          ])),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'pdf', child: Row(children: [
            const Icon(Icons.picture_as_pdf_rounded,
                color: AppColors.danger, size: 18),
            const SizedBox(width: 10),
            Text('PDF statement', style: AppTextStyles.body),
          ])),
          PopupMenuItem(value: 'xlsx', child: Row(children: [
            const Icon(Icons.table_chart_rounded,
                color: AppColors.primary, size: 18),
            const SizedBox(width: 10),
            Text('Excel (.xlsx)', style: AppTextStyles.body),
          ])),
          PopupMenuItem(value: 'csv', child: Row(children: [
            const Icon(Icons.description_rounded,
                color: AppColors.info, size: 18),
            const SizedBox(width: 10),
            Text('CSV', style: AppTextStyles.body),
          ])),
          const PopupMenuDivider(),
          PopupMenuItem(value: 'email', child: Row(children: [
            const Icon(Icons.email_rounded,
                color: AppColors.purple, size: 18),
            const SizedBox(width: 10),
            Text('Email last month\'s PDF', style: AppTextStyles.body),
          ])),
        ],
      ),
      IconButton(
        icon:  Icon(Icons.tune_rounded,
            color: AppColors.text2, size: 20),
        onPressed: _showAdvancedFilters,
      ),
      IconButton(
        icon:  Icon(Icons.refresh_rounded,
            color: AppColors.text2, size: 20),
        onPressed: _load,
      ),
    ],
  );

  // ── Hero ───────────────────────────────────────────────────────────────────

  Widget _buildHero(ExpensesData d) {
    final positive = d.net >= 0;
    final spendingUp = d.spendingDelta >= 0;
    final spendingColor = spendingUp ? AppColors.danger : AppColors.heroFg;
    // Stitch "Monthly Overview" treatment: brand-gradient hero, big net
    // figure, period badge, faint watermark icon — matching the hero
    // pattern used on the dashboard/savings screens.
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: AppColors.heroBrandGradient,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(children: [
        Positioned(
          right: -18, top: -18,
          child: Icon(Icons.account_balance_wallet_rounded,
              size: 110, color: AppColors.heroFg.withOpacity(0.08)),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Monthly Overview',
                style: AppTextStyles.label.copyWith(
                    color: AppColors.heroFgMuted, letterSpacing: 0.6)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.heroFg.withOpacity(0.14),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(_filters.rangeLabel.toUpperCase(),
                  style: AppTextStyles.chip.copyWith(
                      color: AppColors.heroFg, letterSpacing: 1)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '${d.net >= 0 ? "" : "-"}${_fmt(d.net.abs())}',
              style: AppTextStyles.balance.copyWith(
                  color: AppColors.heroFg, fontSize: 30, height: 1.05),
            ),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('XAF', style: AppTextStyles.h4
                  .copyWith(color: AppColors.heroFgMuted)),
            ),
          ]),
          const SizedBox(height: 2),
          Row(children: [
            Icon(positive ? Icons.savings_rounded : Icons.warning_rounded,
                size: 12, color: AppColors.heroFgMuted),
            const SizedBox(width: 4),
            Text('Net cash flow',
                style: AppTextStyles.bodyMuted
                    .copyWith(color: AppColors.heroFgMuted)),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _heroSubStat(
              label: 'Income',
              value: '${_compact(d.totalIncome)} F',
              delta: d.incomeDelta,
              up: d.incomeDelta >= 0,
              upColor: AppColors.heroFg,
              downColor: AppColors.danger,
            )),
            const SizedBox(width: 10),
            Expanded(child: _heroSubStat(
              label: 'Expenses',
              value: '${_compact(d.totalExpense)} F',
              delta: d.spendingDelta,
              up: spendingUp,
              upColor: AppColors.danger,
              downColor: spendingColor,
            )),
          ]),
        ]),
      ]),
    );
  }

  Widget _heroSubStat({
    required String label, required String value,
    required double delta, required bool up,
    required Color upColor, required Color downColor,
  }) {
    final color = up ? upColor : downColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.heroFg.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.heroFg.withOpacity(0.14)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppTextStyles.label.copyWith(
            color: AppColors.heroFgMuted, letterSpacing: 0.6)),
        const SizedBox(height: 4),
        Text(value, style: AppTextStyles.h3.copyWith(color: AppColors.heroFg)),
        const SizedBox(height: 4),
        if (delta != 0) Row(children: [
          Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 11, color: color),
          const SizedBox(width: 3),
          Text('${delta >= 0 ? "+" : ""}${(delta * 100).toStringAsFixed(0)}%',
              style: AppTextStyles.caption.copyWith(
                  color: color, fontWeight: FontWeight.w700)),
        ]) else Text('no prior data',
            style: AppTextStyles.caption.copyWith(color: AppColors.heroFgDim)),
      ]),
    );
  }

  // ── Metrics strip ──────────────────────────────────────────────────────────

  Widget _buildMetricsStrip(ExpensesData d) {
    final topExp = d.expenseCats.isNotEmpty ? d.expenseCats.first : null;
    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _MetricCard(
            icon: Icons.savings_rounded,
            label: 'Savings rate',
            value: '${(d.savingsRate * 100).toStringAsFixed(0)}%',
            color: d.savingsRate >= 0.2
                ? AppColors.primary
                : d.savingsRate >= 0 ? AppColors.info : AppColors.danger,
          ),
          const SizedBox(width: 10),
          _MetricCard(
            icon: Icons.receipt_long_rounded,
            label: 'Transactions',
            value: d.transactions.length.toString(),
            color: AppColors.info,
          ),
          const SizedBox(width: 10),
          if (topExp != null)
            _MetricCard(
              icon: Icons.local_fire_department_rounded,
              label: 'Top spend',
              value: topExp.name,
              color: topExp.color,
            ),
          const SizedBox(width: 10),
          _MetricCard(
            icon: Icons.flag_rounded,
            label: 'Budgets',
            value: d.budgets.length.toString(),
            color: AppColors.accent,
          ),
        ],
      ),
    );
  }

  // ── Filter bar ─────────────────────────────────────────────────────────────

  Widget _buildFilterBar() => Column(children: [
    Row(children: [
      Expanded(child: SizedBox(
        height: 40,
        child: TextField(
          controller: _searchCtrl,
          onSubmitted: (_) {
            _filters.search = _searchCtrl.text.trim();
            _load();
          },
          style: AppTextStyles.body,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search descriptions',
            hintStyle: AppTextStyles.body.copyWith(color: AppColors.text3),
            prefixIcon:  Icon(Icons.search_rounded,
                size: 17, color: AppColors.text3),
            suffixIcon: _searchCtrl.text.isEmpty ? null : IconButton(
              icon:  Icon(Icons.close_rounded,
                  size: 17, color: AppColors.text3),
              onPressed: () {
                _searchCtrl.clear();
                _filters.search = '';
                _load();
              },
            ),
            fillColor: AppColors.surface2,
            filled: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:  BorderSide(color: AppColors.border1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:  BorderSide(color: AppColors.border1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
        ),
      )),
    ]),
    const SizedBox(height: 10),
    SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _FilterChip(
            label: _filters.rangeLabel,
            icon: Icons.calendar_today_rounded,
            active: true,
            onTap: _pickRange,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: switch (_filters.txnType) {
              'EXPENSE' => 'Expenses',
              'INCOME'  => 'Income',
              _         => 'All types',
            },
            icon: Icons.swap_vert_rounded,
            active: _filters.txnType != null,
            onTap: _cycleType,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: _filters.category ?? 'All categories',
            icon: Icons.category_rounded,
            active: _filters.category != null,
            onTap: _pickCategory,
          ),
        ],
      ),
    ),
  ]);

  void _pickRange() async {
    final r = await showModalBottomSheet<_Range>(
      context: context, backgroundColor: AppColors.surface1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _DragHandle(),
          const SizedBox(height: 16),
          Text('Date range', style: AppTextStyles.h3),
          const SizedBox(height: 16),
          for (final r in _Range.values)
            ListTile(
              dense: true,
              leading:  Icon(Icons.event_rounded,
                  color: AppColors.text2, size: 18),
              title: Text(_labelForRange(r), style: AppTextStyles.body),
              trailing: _filters.range == r
                  ? const Icon(Icons.check_rounded,
                      color: AppColors.primary, size: 18)
                  : null,
              onTap: () => Navigator.pop(context, r),
            ),
        ]),
      ),
    );
    if (r != null) {
      setState(() => _filters.range = r);
      _load();
    }
  }

  String _labelForRange(_Range r) => switch (r) {
        _Range.today     => 'Today',
        _Range.thisWeek  => 'This week',
        _Range.thisMonth => 'This month',
        _Range.last30    => 'Last 30 days',
        _Range.thisYear  => 'This year',
      };

  void _cycleType() {
    final next = switch (_filters.txnType) {
      null      => 'EXPENSE',
      'EXPENSE' => 'INCOME',
      _         => null,
    };
    setState(() => _filters.txnType = next);
    _load();
  }

  void _pickCategory() async {
    if (_meta == null) return;
    final all = ['All', ..._meta!.expenseCategories, ..._meta!.incomeCategories];
    final picked = await showModalBottomSheet<String>(
      context: context, backgroundColor: AppColors.surface1,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
          child: Column(children: [
            _DragHandle(),
            const SizedBox(height: 16),
            Text('Filter by category', style: AppTextStyles.h3),
            const SizedBox(height: 16),
            Expanded(child: ListView(
              children: all.map((c) => ListTile(
                dense: true,
                leading: c == 'All'
                    ?  Icon(Icons.all_inbox_rounded,
                        color: AppColors.text2, size: 18)
                    : Container(width: 14, height: 14,
                        decoration: BoxDecoration(
                          color: _categoryDefaultColor(c),
                          borderRadius: BorderRadius.circular(4),
                        )),
                title: Text(c, style: AppTextStyles.body),
                trailing: (_filters.category ?? 'All') == c
                    ? const Icon(Icons.check_rounded,
                        color: AppColors.primary, size: 18)
                    : null,
                onTap: () => Navigator.pop(context, c == 'All' ? null : c),
              )).toList(),
            )),
          ]),
        ),
      ),
    );
    if (picked == null && _filters.category == null) return;
    setState(() => _filters.category = picked);
    _load();
  }

  void _showAdvancedFilters() {
    // Reserved for date-range custom picker, amount range, sort.
    _toast(context, 'More filters coming soon — tap the chips for now.');
  }

  Future<void> _exportAs(String choice) async {
    if (choice == 'inbox') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const StatementsScreen()),
      );
      return;
    }
    if (choice == 'email') {
      _toast(context, 'Emailing your statement…');
      try {
        final res = await ApiService.emailMyStatement();
        if (mounted) _toast(context, res['message'] as String? ?? 'Done.');
      } catch (e) {
        if (mounted) _toast(context, _apiErr(e), error: true);
      }
      return;
    }
    final (from, to) = _filters.window;
    _toast(context, 'Preparing ${choice.toUpperCase()}…');
    try {
      final file = await ApiService.exportExpenses(
        format: choice, from: from, to: to,
      );
      try {
        await downloadBytes(
          bytes: file.bytes,
          filename: file.filename,
          mimeType: file.mimeType,
        );
      } on UnsupportedError catch (e) {
        if (mounted) _toast(context, e.message ?? 'Not supported here', error: true);
      }
    } catch (e) {
      if (mounted) _toast(context, _apiErr(e), error: true);
    }
  }

  // ── Percentage bar chart ───────────────────────────────────────────────────

  Widget _buildBarChartCard(ExpensesData d) {
    final showIncome = _filters.txnType == 'INCOME';
    final cats = showIncome ? d.incomeCats : d.expenseCats;
    if (cats.isEmpty) return const SizedBox.shrink();
    final title = showIncome ? 'Income breakdown' : 'Spending breakdown';
    final totalLabel = showIncome
        ? '${_fmt(d.totalIncome)} FCFA'
        : '${_fmt(d.totalExpense)} FCFA';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: AppTextStyles.h3),
        Text(totalLabel, style: AppTextStyles.h4
            .copyWith(color: AppColors.primary)),
      ]),
      const SizedBox(height: 12),
      ...cats.map((c) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _CategoryBar(
          cat: c,
          onTap: () => _showCategoryDrill(c),
        ),
      )),
    ]);
  }

  // ── Income/Expense line chart ──────────────────────────────────────────────

  Widget _buildTrendCard(ExpensesData d) {
    final incomeSpots = <FlSpot>[];
    final expenseSpots = <FlSpot>[];
    double maxY = 0;
    for (var i = 0; i < _trend.length; i++) {
      incomeSpots.add(FlSpot(i.toDouble(), _trend[i].income));
      expenseSpots.add(FlSpot(i.toDouble(), _trend[i].expense));
      if (_trend[i].income  > maxY) maxY = _trend[i].income;
      if (_trend[i].expense > maxY) maxY = _trend[i].expense;
    }
    if (maxY == 0) maxY = 1; // avoid /0 in chart bounds.

    return NkapCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.show_chart_rounded,
              color: AppColors.info, size: 18),
          const SizedBox(width: 8),
          Text('Income vs Expense — 30d', style: AppTextStyles.h3),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          _LegendDot(color: AppColors.primary, label: 'Income'),
          const SizedBox(width: 14),
          _LegendDot(color: AppColors.danger,  label: 'Expense'),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child: LineChart(LineChartData(
            minY: 0, maxY: maxY * 1.1,
            gridData: FlGridData(
              show: true, drawVerticalLine: false,
              horizontalInterval: maxY / 3,
              getDrawingHorizontalLine: (_) => FlLine(
                color: AppColors.border1, strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: (_trend.length / 5).floorToDouble().clamp(1, 30),
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= _trend.length) return const SizedBox();
                  final t = _trend[i].date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${t.day}/${t.month}',
                        style: AppTextStyles.caption.copyWith(fontSize: 9)),
                  );
                },
              )),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: incomeSpots,
                isCurved: true, curveSmoothness: 0.25,
                color: AppColors.primary, barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.primary.withOpacity(0.12),
                ),
              ),
              LineChartBarData(
                spots: expenseSpots,
                isCurved: true, curveSmoothness: 0.25,
                color: AppColors.danger, barWidth: 2,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.danger.withOpacity(0.10),
                ),
              ),
            ],
          )),
        ),
      ]),
    );
  }

  // ── Budgets ────────────────────────────────────────────────────────────────

  Widget _buildBudgetsCard(ExpensesData d) => NkapCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.flag_rounded, color: AppColors.accent, size: 18),
        const SizedBox(width: 8),
        Text('Budgets', style: AppTextStyles.h3),
        const Spacer(),
        GestureDetector(
          onTap: _showBudgetsManager,
          child: Text('Manage', style: AppTextStyles.h4
              .copyWith(color: AppColors.primary)),
        ),
      ]),
      const SizedBox(height: 12),
      ...d.budgets.map((b) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _BudgetBar(budget: b),
      )),
    ]),
  );

  Widget _buildBudgetsPromo() => GestureDetector(
    onTap: _showBudgetsManager,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.accent.withOpacity(0.10),
          AppColors.accent.withOpacity(0.03),
        ]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withOpacity(0.22)),
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: AppColors.accentDim,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.accentMid),
          ),
          child: const Icon(Icons.flag_rounded,
              color: AppColors.accent, size: 19),
        ),
        const SizedBox(width: 13),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Set category budgets', style: AppTextStyles.h4
              .copyWith(color: AppColors.accent)),
          const SizedBox(height: 2),
          Text('Get warnings at 80%, 90%, and 100% of each limit',
              style: AppTextStyles.bodyMuted),
        ])),
        const Icon(Icons.arrow_forward_rounded,
            size: 18, color: AppColors.accent),
      ]),
    ),
  );

  // ── Insights ───────────────────────────────────────────────────────────────

  Widget _buildInsightsCard(ExpensesData d) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        AppColors.purple.withOpacity(0.10),
        AppColors.purple.withOpacity(0.03),
      ]),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.purple.withOpacity(0.2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: AppColors.purpleDim,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.purple.withOpacity(0.3)),
          ),
          child: const Icon(Icons.lightbulb_rounded,
              color: AppColors.purple, size: 15),
        ),
        const SizedBox(width: 10),
        Text('Insights', style: AppTextStyles.h4
            .copyWith(color: AppColors.purple)),
      ]),
      const SizedBox(height: 10),
      ...d.insights.map((t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.only(top: 5, right: 8),
            child: Icon(Icons.circle, size: 5, color: AppColors.purple),
          ),
          Expanded(child: Text(t, style: AppTextStyles.bodyMuted)),
        ]),
      )),
    ]),
  );

  // ── Transactions ───────────────────────────────────────────────────────────

  Widget _buildTransactionsHeader(ExpensesData d) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text('Recent Transactions', style: AppTextStyles.h3),
      Text('${d.transactions.length} found', style: AppTextStyles.caption),
    ]),
  );

  Widget _buildEmptyTxn() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
    margin: const EdgeInsets.only(top: 8),
    decoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.border1),
    ),
    child: Column(children: [
       Icon(Icons.receipt_long_outlined,
          size: 32, color: AppColors.text3),
      const SizedBox(height: 10),
      Text('No transactions in this view', style: AppTextStyles.h4),
      const SizedBox(height: 4),
      Text('Try a wider date range, or tap + to add one.',
          textAlign: TextAlign.center, style: AppTextStyles.caption),
    ]),
  );

  Widget _buildTxnRow(Txn t) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppColors.dangerDim,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_rounded, color: AppColors.danger),
      ),
      confirmDismiss: (_) async => await _confirmDelete(t),
      onDismissed: (_) => _deleteTxn(t),
      child: NkapCard(
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          // 40px circular tinted icon lead-in (Stitch transaction-row pattern).
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: t.color.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(t.isIncome
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
                size: 18, color: t.color),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.h4),
            const SizedBox(height: 2),
            Text(_txnSubtitle(t),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '${t.isIncome ? "+" : "-"}${_fmt(t.amount)} F',
              style: AppTextStyles.h4.copyWith(
                  color: t.isIncome ? AppColors.primary : AppColors.text1),
            ),
            const SizedBox(height: 2),
            Text(t.dateLabel, style: AppTextStyles.caption),
          ]),
        ]),
      ),
    ),
  );

  String _txnSubtitle(Txn t) {
    final parts = <String>[t.category];
    if (t.paymentMethod != null) parts.add(t.paymentMethod!);
    if (t.location != null && t.location!.isNotEmpty) parts.add(t.location!);
    return parts.join(' · ');
  }

  Future<bool> _confirmDelete(Txn t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface2,
        title: Text('Delete transaction?',
            style: GoogleFonts.hankenGrotesk(
                fontWeight: FontWeight.w800, color: AppColors.text1)),
        content: Text(
          '${t.name} — ${_fmt(t.amount)} FCFA. This will adjust your balance.',
          style: GoogleFonts.hankenGrotesk(color: AppColors.text2, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.hankenGrotesk(color: AppColors.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete',
                style: GoogleFonts.hankenGrotesk(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _deleteTxn(Txn t) async {
    try {
      await ApiService.deleteExpense(t.id);
      if (mounted) {
        _toast(context, 'Transaction removed.');
        _load();
      }
    } catch (e) {
      if (mounted) _toast(context, _apiErr(e), error: true);
    }
  }

  // ── Drill into a category ──────────────────────────────────────────────────

  void _showCategoryDrill(CatSummary c) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CategoryDrillSheet(
        category: c,
        windowRangeLabel: _filters.rangeLabel,
        filters: _filters,
        onChanged: _load,
      ),
    );
  }

  // ── Add sheet ──────────────────────────────────────────────────────────────

  void _showAddSheet({Txn? edit}) {
    if (_meta == null) {
      _toast(context, 'Loading…');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddTxnSheet(
        meta: _meta!,
        edit: edit,
        onSaved: _load,
      ),
    );
  }

  // ── Budget manager ─────────────────────────────────────────────────────────

  void _showBudgetsManager() {
    if (_meta == null) {
      _toast(context, 'Loading…');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _BudgetManagerSheet(
        meta: _meta!, onChanged: _load,
      ),
    );
  }

  // ── Skeleton + Error ───────────────────────────────────────────────────────

  Widget _buildSkeleton() => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
    children: [
      Shimmer.fromColors(
        baseColor: AppColors.surface4,
        highlightColor: AppColors.surface2,
        child: Column(children: [
          Container(height: 170, decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(22))),
          const SizedBox(height: 14),
          Container(height: 100, decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(18))),
          const SizedBox(height: 14),
          Container(height: 260, decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(20))),
          const SizedBox(height: 14),
          ...List.generate(4, (_) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(height: 68, decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(16))),
          )),
        ]),
      ),
    ],
  );

  Widget _buildError(String msg) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 120),
      Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.danger, size: 36),
          const SizedBox(height: 12),
          Text("Couldn't load", style: AppTextStyles.h3),
          const SizedBox(height: 6),
          Text(msg, textAlign: TextAlign.center,
              style: AppTextStyles.bodyMuted),
          const SizedBox(height: 20),
          NkapButton(label: 'Retry', onTap: _load),
        ]),
      )),
    ],
  );
}

// ─── Reused colour for the category chip in pickers ──────────────────────────

Color _categoryDefaultColor(String cat) {
  const map = {
    'Food':          0xFFFF7043,
    'Transport':     0xFF42A5F5,
    'Utilities':     0xFF26C6DA,
    'Rent':          0xFFA78BFA,
    'Healthcare':    0xFFEC407A,
    'Education':     0xFF66BB6A,
    'Business':      0xFFFFB627,
    'Entertainment': 0xFFAB47BC,
    'Shopping':      0xFFFF8A65,
    'Other':         0xFF78716C,
    'Salary':              0xFF12E8A4,
    'Business Income':     0xFF26A69A,
    'Investment Returns':  0xFF7CB342,
    'Gifts':               0xFFFFCA28,
    'Njangi Payout':       0xFFFFB627,
    'Other Income':        0xFF9E9E9E,
  };
  return Color(0xFF000000 | (map[cat] ?? 0xFF78716C));
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

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
    width: 130,
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border1),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
      Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 15, color: color),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: AppTextStyles.h3.copyWith(height: 1)),
        const SizedBox(height: 3),
        Text(label, style: AppTextStyles.caption),
      ]),
    ]),
  );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label, required this.icon,
    required this.active, required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.text3;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.primaryDim : AppColors.surface2,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
              color: active ? AppColors.primaryMid : AppColors.border2),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(label, style: AppTextStyles.label.copyWith(
              color: active ? AppColors.primary : AppColors.text2)),
          const SizedBox(width: 4),
          Icon(Icons.expand_more_rounded, size: 14, color: color),
        ]),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  final CatSummary cat;
  final VoidCallback onTap;
  const _CategoryBar({required this.cat, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final delta = cat.deltaPct;
    final hasDelta = delta != 0;
    final up = delta > 0;
    final isIncome = cat.txnType == 'INCOME';
    final deltaIsGood = isIncome ? up : !up;
    final deltaColor = deltaIsGood ? AppColors.primary : AppColors.danger;
    return NkapCard(
      radius: 16,
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        // 40px circular tinted icon lead-in (Stitch category-row pattern).
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: cat.color.withOpacity(0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(_categoryIcon(cat.name), color: cat.color, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(cat.name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.h4)),
            if (hasDelta) ...[
              Icon(up ? Icons.arrow_upward_rounded
                     : Icons.arrow_downward_rounded,
                  size: 11, color: deltaColor),
              const SizedBox(width: 2),
              Text('${up ? "+" : ""}${delta.toStringAsFixed(0)}%',
                  style: AppTextStyles.caption.copyWith(
                      color: deltaColor, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
            ],
            Text('${_fmt(cat.amount)} F', style: AppTextStyles.h4),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (cat.percent / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppColors.surface3,
              valueColor: AlwaysStoppedAnimation(cat.color),
            ),
          ),
        ])),
      ]),
    );
  }
}

IconData _categoryIcon(String cat) {
  const map = {
    'Food':                Icons.restaurant_rounded,
    'Transport':           Icons.directions_car_rounded,
    'Utilities':           Icons.bolt_rounded,
    'Rent':                Icons.home_work_rounded,
    'Healthcare':          Icons.health_and_safety_rounded,
    'Education':           Icons.school_rounded,
    'Business':            Icons.work_rounded,
    'Entertainment':       Icons.movie_rounded,
    'Shopping':            Icons.shopping_bag_rounded,
    'Data & Airtime':      Icons.signal_cellular_alt_rounded,
    'Other':               Icons.category_rounded,
    'Salary':              Icons.payments_rounded,
    'Business Income':     Icons.storefront_rounded,
    'Investment Returns':  Icons.trending_up_rounded,
    'Gifts':               Icons.card_giftcard_rounded,
    'Njangi Payout':       Icons.groups_rounded,
    'Other Income':        Icons.account_balance_wallet_rounded,
  };
  return map[cat] ?? Icons.category_rounded;
}

class _BudgetBar extends StatelessWidget {
  final BudgetRow budget;
  const _BudgetBar({required this.budget});

  @override
  Widget build(BuildContext context) {
    final color = switch (budget.status) {
      'exceeded' => AppColors.danger,
      'critical' => AppColors.danger,
      'warning'  => AppColors.accent,
      _          => AppColors.primary,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(
          color: _categoryDefaultColor(budget.category),
          borderRadius: BorderRadius.circular(3),
        )),
        const SizedBox(width: 8),
        Expanded(child: Text(budget.category,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: AppTextStyles.h4)),
        Text('${_fmt(budget.spent)} / ${_fmt(budget.target)} F',
            style: AppTextStyles.caption),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.18),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('${budget.percent.toStringAsFixed(0)}%',
              style: AppTextStyles.chip.copyWith(color: color)),
        ),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: (budget.percent / 100).clamp(0.0, 1.0),
          minHeight: 6,
          backgroundColor: AppColors.border1,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    ]);
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(
        color: color, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 6),
    Text(label, style: AppTextStyles.bodyMuted),
  ]);
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

// ─── Category drill-down sheet ───────────────────────────────────────────────

class _CategoryDrillSheet extends StatefulWidget {
  final CatSummary category;
  final String windowRangeLabel;
  final _Filters filters;
  final VoidCallback onChanged;
  const _CategoryDrillSheet({
    required this.category, required this.windowRangeLabel,
    required this.filters, required this.onChanged,
  });
  @override
  State<_CategoryDrillSheet> createState() => _CategoryDrillSheetState();
}

class _CategoryDrillSheetState extends State<_CategoryDrillSheet> {
  bool _loading = true;
  List<Txn> _txns = const [];
  String? _err;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final (from, to) = widget.filters.window;
    try {
      final res = await ApiService.getExpenses(
        from: from, to: to,
        txnType: widget.category.txnType,
        category: widget.category.name,
      );
      if (!mounted) return;
      setState(() {
        _txns = (res['transactions'] as List)
            .cast<Map<String, dynamic>>().map(Txn.fromJson).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _err = _apiErr(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration:  BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(children: [
          _DragHandle(),
          const SizedBox(height: 14),
          Row(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(
              color: c.color.withOpacity(0.18),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: c.color.withOpacity(0.3)),
            ), child: Center(child: Text('${c.percent.toStringAsFixed(0)}%',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 11, fontWeight: FontWeight.w800,
                    color: c.color)))),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: GoogleFonts.hankenGrotesk(
                  fontSize: 17, fontWeight: FontWeight.w800,
                  color: AppColors.text1)),
              Text('${_fmt(c.amount)} FCFA · ${widget.windowRangeLabel}',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 11, color: AppColors.text3)),
            ])),
          ]),
          const SizedBox(height: 16),
          Expanded(child: _loading
              ? const Center(child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2))
              : _err != null
                  ? Center(child: Text(_err!,
                      style: GoogleFonts.hankenGrotesk(color: AppColors.danger)))
                  : _txns.isEmpty
                      ? Center(child: Text(
                          'No transactions in this view.',
                          style: GoogleFonts.hankenGrotesk(color: AppColors.text3)))
                      : ListView.separated(
                          itemCount: _txns.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final t = _txns[i];
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.surface2,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.border1),
                              ),
                              child: Row(children: [
                                Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                  Text(t.name, maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.hankenGrotesk(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.text1)),
                                  const SizedBox(height: 2),
                                  Text('${t.dateLabel}${t.paymentMethod != null ? " · ${t.paymentMethod}" : ""}',
                                      style: GoogleFonts.hankenGrotesk(
                                          fontSize: 11,
                                          color: AppColors.text3)),
                                ])),
                                Text('${t.isIncome ? "+" : "-"}${_fmt(t.amount)} F',
                                    style: GoogleFonts.hankenGrotesk(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: t.isIncome
                                            ? AppColors.primary
                                            : AppColors.danger)),
                              ]),
                            );
                          },
                        )),
        ]),
      ),
    );
  }
}

// ─── Add Transaction Sheet ───────────────────────────────────────────────────

class _AddTxnSheet extends StatefulWidget {
  final Meta meta;
  final Txn? edit;
  final VoidCallback onSaved;
  const _AddTxnSheet({required this.meta, this.edit, required this.onSaved});
  @override
  State<_AddTxnSheet> createState() => _AddTxnSheetState();
}

class _AddTxnSheetState extends State<_AddTxnSheet> {
  late String _txnType;
  late String _category;
  late TextEditingController _nameCtrl, _amountCtrl, _noteCtrl, _locationCtrl;
  String? _paymentMethod;
  DateTime _date = DateTime.now();
  bool _busy = false;
  bool _scanning = false;
  double? _ocrConfidence;
  String? _voiceTranscript;

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _txnType  = e?.txnType ?? 'EXPENSE';
    _category = e?.category ?? widget.meta.expenseCategories.first;
    _nameCtrl     = TextEditingController(text: e?.name ?? '');
    _amountCtrl   = TextEditingController(
        text: e == null ? '' : e.amount.toStringAsFixed(0));
    _noteCtrl     = TextEditingController(text: e?.note ?? '');
    _locationCtrl = TextEditingController(text: e?.location ?? '');
    _paymentMethod = e?.paymentMethod;
    if (e != null) _date = DateTime.parse(e.isoDate).toLocal();
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _amountCtrl.dispose();
    _noteCtrl.dispose(); _locationCtrl.dispose();
    super.dispose();
  }

  List<String> get _cats => _txnType == 'INCOME'
      ? widget.meta.incomeCategories : widget.meta.expenseCategories;

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (name.isEmpty || amount == null || amount <= 0) {
      _toast(context, 'Enter a name and positive amount.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      if (widget.edit == null) {
        await ApiService.addExpense(
          name: name, category: _category, amount: amount,
          txnType: _txnType,
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          paymentMethod: _paymentMethod,
          location: _locationCtrl.text.trim().isEmpty
              ? null : _locationCtrl.text.trim(),
          txnDate: _date,
        );
      } else {
        await ApiService.updateExpense(
          id: widget.edit!.id,
          name: name, category: _category, amount: amount,
          txnType: _txnType,
          note: _noteCtrl.text.trim(),
          paymentMethod: _paymentMethod,
          location: _locationCtrl.text.trim(),
          txnDate: _date,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
      _toast(context, widget.edit == null ? 'Transaction added.' : 'Updated.');
      widget.onSaved();
    } catch (e) {
      setState(() => _busy = false);
      _toast(context, _apiErr(e), error: true);
    }
  }

  Future<void> _scanReceipt({required ImageSource source}) async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1600, imageQuality: 85,
      );
      if (picked == null) {
        if (mounted) setState(() => _scanning = false);
        return;
      }
      final bytes = await picked.readAsBytes();
      final res = await ApiService.ocrReceipt(
        bytes: bytes, filename: picked.name,
      );
      if (!mounted) return;
      _applyOcr(res);
    } catch (e) {
      if (mounted) {
        final msg = _apiErr(e);
        // Tesseract-not-installed shows as 503 — display a clear dialog.
        if (msg.toLowerCase().contains('not installed') ||
            msg.toLowerCase().contains('tesseract')) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.surface1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Text('Scanner not available',
                  style: GoogleFonts.hankenGrotesk(
                      fontWeight: FontWeight.w800, color: AppColors.text1)),
              content: Text(
                'The OCR engine (Tesseract) is not installed on the server.\n\n'
                'To enable receipt scanning:\n'
                '  brew install tesseract tesseract-lang\n\n'
                'For now, please fill in your expense manually.',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 13, color: AppColors.text2, height: 1.5)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Got it',
                      style: GoogleFonts.hankenGrotesk(
                          color: AppColors.primary, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          );
        } else {
          _toast(context, msg, error: true);
        }
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _applyOcr(Map<String, dynamic> r) {
    final vendor = r['vendor'] as String?;
    final total  = (r['total']    as num?)?.toDouble();
    final iso    = r['txn_date']  as String?;
    final conf   = ((r['confidence'] as num?) ?? 0).toDouble();
    setState(() {
      _txnType = 'EXPENSE';                       // receipts ⇒ expense.
      if (vendor != null && vendor.isNotEmpty) {
        _nameCtrl.text = vendor;
      }
      if (total != null && total > 0) {
        _amountCtrl.text = total.toStringAsFixed(0);
      }
      if (iso != null && iso.isNotEmpty) {
        try { _date = DateTime.parse(iso); } catch (_) {}
      }
      _ocrConfidence = conf;
    });

    // When OCR extracts both description and amount, show a confirmation
    // sheet so the user can save in one tap without hunting for the button.
    final hasAmount  = total != null && total > 0;
    final hasVendor  = vendor != null && vendor.isNotEmpty;
    if (hasAmount && hasVendor) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(99))),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: AppColors.primaryDim,
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.receipt_long_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Receipt scanned',
                    style: GoogleFonts.hankenGrotesk(
                        fontWeight: FontWeight.w800, fontSize: 15,
                        color: AppColors.text1)),
                Text('${(conf * 100).toStringAsFixed(0)}% confidence',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 11, color: AppColors.text3)),
              ])),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border1)),
              child: Column(children: [
                _ocrRow('Description', vendor),
                const SizedBox(height: 6),
                _ocrRow('Amount',
                    '${total.toStringAsFixed(0)} FCFA'),
                if (iso != null && iso.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _ocrRow('Date', iso),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            NkapButton(
              label: 'Save Expense',
              icon: Icons.check_rounded,
              onTap: () { Navigator.pop(ctx); _submit(); },
            ),
            const SizedBox(height: 8),
            Center(child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Edit before saving',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 12, color: AppColors.text3)),
            )),
          ]),
        ),
      );
    } else {
      _toast(context,
          'Receipt scanned — ${(conf * 100).toStringAsFixed(0)}% confidence. '
          '${hasAmount ? '' : 'Enter an amount and '}tap Add to save.');
    }
  }

  Widget _ocrRow(String label, String? value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 12, color: AppColors.text3)),
          Flexible(child: Text(value ?? '—',
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: AppColors.text1))),
        ],
      );

  Future<void> _listenForVoice() async {
    final transcript = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const _VoiceCaptureSheet(),
    );
    if (!mounted || transcript == null || transcript.trim().isEmpty) return;
    final parsed = _parseVoiceTxn(
      transcript,
      expenseCats: widget.meta.expenseCategories,
      incomeCats: widget.meta.incomeCategories,
      paymentMethods: widget.meta.paymentMethods,
    );
    setState(() {
      _voiceTranscript = transcript;
      if (parsed.txnType != null) _txnType = parsed.txnType!;
      if (parsed.amount != null) {
        _amountCtrl.text = parsed.amount!.toStringAsFixed(0);
      }
      if (parsed.description != null && parsed.description!.isNotEmpty) {
        _nameCtrl.text = parsed.description!;
      }
      if (parsed.category != null && _cats.contains(parsed.category)) {
        _category = parsed.category!;
      } else if (!_cats.contains(_category)) {
        _category = _cats.first;
      }
      if (parsed.paymentMethod != null) _paymentMethod = parsed.paymentMethod;
    });
    final missing = <String>[
      if (parsed.amount == null) 'amount',
      if (parsed.description == null || parsed.description!.isEmpty) 'description',
    ];
    if (missing.isEmpty) {
      _toast(context, 'Got it — review and tap Add.');
    } else {
      _toast(
        context,
        'Heard you. Please add ${missing.join(" & ")} before saving.',
        error: missing.contains('amount'),
      );
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => _date = d);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration:  BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _DragHandle(),
          const SizedBox(height: 16),
          Text(widget.edit == null ? 'Add transaction' : 'Edit transaction',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  color: AppColors.text1)),
          const SizedBox(height: 14),

          // Receipt scanner + voice input — only when creating.
          if (widget.edit == null) ...[
            _buildScanRow(),
            const SizedBox(height: 10),
            _buildVoiceRow(),
            const SizedBox(height: 14),
          ],

          // Type toggle
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              _typeBtn('EXPENSE', 'Expense', Icons.arrow_upward_rounded),
              _typeBtn('INCOME',  'Income',  Icons.arrow_downward_rounded),
            ]),
          ),
          const SizedBox(height: 16),

          _SheetField(
            controller: _nameCtrl, label: 'Description',
            hint: _txnType == 'INCOME' ? 'e.g. Salary May' : 'e.g. Coffee at Bao',
            icon: Icons.edit_note_rounded,
          ),
          const SizedBox(height: 12),

          _SheetField(
            controller: _amountCtrl, label: 'Amount (FCFA)',
            hint: 'e.g. 5000',
            icon: Icons.payments_rounded,
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),

          // Category picker
          Align(alignment: Alignment.centerLeft,
              child: Text('Category', style: GoogleFonts.hankenGrotesk(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: AppColors.text2))),
          const SizedBox(height: 7),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: _cats.map((c) {
                final sel = c == _category;
                final color = _categoryDefaultColor(c);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _category = c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: sel ? color.withOpacity(0.18) : AppColors.surface2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: sel ? color : AppColors.border2),
                      ),
                      child: Row(children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(
                          color: color, borderRadius: BorderRadius.circular(2),
                        )),
                        const SizedBox(width: 6),
                        Text(c, style: GoogleFonts.hankenGrotesk(
                            fontSize: 12,
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
                            color: sel ? color : AppColors.text2)),
                      ]),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // Payment method
          Align(alignment: Alignment.centerLeft,
              child: Text('Payment method', style: GoogleFonts.hankenGrotesk(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: AppColors.text2))),
          const SizedBox(height: 7),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final pm in widget.meta.paymentMethods)
              GestureDetector(
                onTap: () => setState(() => _paymentMethod =
                    _paymentMethod == pm ? null : pm),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _paymentMethod == pm
                        ? AppColors.primaryDim : AppColors.surface2,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: _paymentMethod == pm
                        ? AppColors.primaryMid : AppColors.border2),
                  ),
                  child: Text(pm, style: GoogleFonts.hankenGrotesk(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _paymentMethod == pm
                          ? AppColors.primary : AppColors.text2)),
                ),
              ),
          ]),
          const SizedBox(height: 14),

          // Date + location row
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border1),
                ),
                child: Row(children: [
                   Icon(Icons.event_rounded,
                      size: 17, color: AppColors.text3),
                  const SizedBox(width: 8),
                  Text('${_date.year}-${_date.month.toString().padLeft(2, "0")}-${_date.day.toString().padLeft(2, "0")}',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 13, color: AppColors.text1)),
                ]),
              ),
            )),
            const SizedBox(width: 10),
            Expanded(child: _SheetField(
              controller: _locationCtrl, label: '',
              hint: 'Location (opt.)',
              icon: Icons.place_outlined,
            )),
          ]),
          const SizedBox(height: 12),

          _SheetField(
            controller: _noteCtrl, label: 'Note (optional)',
            hint: 'Anything else',
            icon: Icons.notes_rounded,
          ),
          const SizedBox(height: 22),

          NkapButton(
            label: widget.edit == null ? 'Add transaction' : 'Save changes',
            icon: Icons.check_rounded,
            loading: _busy,
            onTap: _busy ? null : _submit,
          ),
        ]),
      ),
    );
  }

  Widget _buildScanRow() => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        AppColors.primary.withOpacity(0.10),
        AppColors.primary.withOpacity(0.03),
      ]),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.primary.withOpacity(0.25)),
    ),
    child: Row(children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: AppColors.primaryDim,
          borderRadius: BorderRadius.circular(11),
        ),
        child: _scanning
            ? const Padding(
                padding: EdgeInsets.all(9),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary),
              )
            : const Icon(Icons.document_scanner_rounded,
                color: AppColors.primary, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          _ocrConfidence == null
              ? 'Scan a receipt'
              : 'Scanned · ${(_ocrConfidence! * 100).toStringAsFixed(0)}% confidence',
          style: GoogleFonts.hankenGrotesk(
              fontWeight: FontWeight.w700, fontSize: 12.5,
              color: AppColors.primary)),
        const SizedBox(height: 2),
        Text(_ocrConfidence == null
                ? 'Auto-fill amount, vendor and date'
                : 'Review the fields below before saving',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 10.5, color: AppColors.text3)),
      ])),
      IconButton(
        icon: const Icon(Icons.photo_camera_rounded,
            color: AppColors.primary, size: 18),
        onPressed: _scanning
            ? null
            : () => _scanReceipt(source: ImageSource.camera),
        tooltip: 'Use camera',
      ),
      IconButton(
        icon: const Icon(Icons.photo_library_rounded,
            color: AppColors.primary, size: 18),
        onPressed: _scanning
            ? null
            : () => _scanReceipt(source: ImageSource.gallery),
        tooltip: 'Pick from gallery',
      ),
    ]),
  );

  Widget _buildVoiceRow() => GestureDetector(
    onTap: _listenForVoice,
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.purple.withOpacity(0.10),
          AppColors.purple.withOpacity(0.03),
        ]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.purple.withOpacity(0.25)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppColors.purpleDim,
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.mic_rounded,
              color: AppColors.purple, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            _voiceTranscript == null
                ? 'Speak to add'
                : 'Heard: "${_voiceTranscript!}"',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.hankenGrotesk(
                fontWeight: FontWeight.w700, fontSize: 12.5,
                color: AppColors.purple)),
          const SizedBox(height: 2),
          Text(_voiceTranscript == null
                  ? 'e.g. "Spent 5000 on coffee with momo"'
                  : 'Tap to capture again',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 10.5, color: AppColors.text3)),
        ])),
        const Icon(Icons.graphic_eq_rounded,
            color: AppColors.purple, size: 18),
      ]),
    ),
  );

  Widget _typeBtn(String value, String label, IconData icon) => Expanded(
    child: GestureDetector(
      onTap: () => setState(() {
        _txnType = value;
        // If the current category doesn't fit the type, switch to first.
        if (!_cats.contains(_category)) _category = _cats.first;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _txnType == value ? AppColors.primaryDim : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 15,
              color: _txnType == value ? AppColors.primary : AppColors.text3),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.hankenGrotesk(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: _txnType == value ? AppColors.primary : AppColors.text2)),
        ]),
      ),
    ),
  );
}

// ─── Budget manager sheet ────────────────────────────────────────────────────

class _BudgetManagerSheet extends StatefulWidget {
  final Meta meta;
  final VoidCallback onChanged;
  const _BudgetManagerSheet({required this.meta, required this.onChanged});
  @override
  State<_BudgetManagerSheet> createState() => _BudgetManagerSheetState();
}

class _BudgetManagerSheetState extends State<_BudgetManagerSheet> {
  bool _loading = true;
  Map<String, double> _amounts = {};   // category -> target

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final list = await ApiService.getBudgets();
      if (!mounted) return;
      setState(() {
        _amounts = {
          for (final b in list.cast<Map<String, dynamic>>())
            b['category'] as String: (b['amount'] as num).toDouble(),
        };
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast(context, _apiErr(e), error: true);
    }
  }

  Future<void> _editCategory(String cat) async {
    final ctrl = TextEditingController(
        text: _amounts[cat]?.toStringAsFixed(0) ?? '');
    final result = await showDialog<({double? amount, bool delete})>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface2,
        title: Text('Budget for $cat', style: GoogleFonts.hankenGrotesk(
            fontWeight: FontWeight.w800, color: AppColors.text1)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Monthly target in FCFA.', style: GoogleFonts.hankenGrotesk(
              fontSize: 12, color: AppColors.text3)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number, autofocus: true,
            style: GoogleFonts.hankenGrotesk(
                fontSize: 22, fontWeight: FontWeight.w800,
                color: AppColors.primary),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              suffixText: 'F',
              suffixStyle: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800),
            ),
          ),
        ]),
        actions: [
          if (_amounts.containsKey(cat))
            TextButton(
              onPressed: () => Navigator.pop(context,
                  (amount: null, delete: true)),
              child: Text('Remove', style: GoogleFonts.hankenGrotesk(
                  color: AppColors.danger, fontWeight: FontWeight.w700)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text('Cancel',
                style: GoogleFonts.hankenGrotesk(color: AppColors.text2)),
          ),
          TextButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.trim());
              if (v == null || v <= 0) {
                _toast(context, 'Enter a positive number.', error: true);
                return;
              }
              Navigator.pop(context, (amount: v, delete: false));
            },
            child: Text('Save', style: GoogleFonts.hankenGrotesk(
                color: AppColors.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (result == null) return;
    try {
      if (result.delete) {
        await ApiService.deleteBudget(cat);
        setState(() => _amounts.remove(cat));
      } else if (result.amount != null) {
        await ApiService.setBudget(category: cat, amount: result.amount!);
        setState(() => _amounts[cat] = result.amount!);
      }
      widget.onChanged();
    } catch (e) {
      if (mounted) _toast(context, _apiErr(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration:  BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(children: [
          _DragHandle(),
          const SizedBox(height: 14),
          Text('Manage budgets', style: GoogleFonts.hankenGrotesk(
              fontSize: 18, fontWeight: FontWeight.w800,
              color: AppColors.text1)),
          const SizedBox(height: 4),
          Text('Tap a category to set or update its monthly target.',
              textAlign: TextAlign.center,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 12, color: AppColors.text3)),
          const SizedBox(height: 14),
          Expanded(child: _loading
              ? const Center(child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2))
              : ListView.separated(
                  itemCount: widget.meta.expenseCategories.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final cat = widget.meta.expenseCategories[i];
                    final amount = _amounts[cat];
                    return GestureDetector(
                      onTap: () => _editCategory(cat),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.border1),
                        ),
                        child: Row(children: [
                          Container(width: 12, height: 12, decoration: BoxDecoration(
                            color: _categoryDefaultColor(cat),
                            borderRadius: BorderRadius.circular(3),
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: Text(cat,
                              style: GoogleFonts.hankenGrotesk(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.text1))),
                          Text(amount == null
                              ? 'No target'
                              : '${_fmt(amount)} F',
                              style: GoogleFonts.hankenGrotesk(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: amount == null
                                      ? AppColors.text3
                                      : AppColors.primary)),
                          const SizedBox(width: 8),
                           Icon(Icons.chevron_right_rounded,
                              size: 18, color: AppColors.text3),
                        ]),
                      ),
                    );
                  },
                )),
        ]),
      ),
    );
  }
}

// ─── Reusable input ──────────────────────────────────────────────────────────

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

// ─── Voice input ─────────────────────────────────────────────────────────────

class _ParsedTxn {
  final double? amount;
  final String? description;
  final String? category;
  final String? txnType;       // 'EXPENSE' | 'INCOME' | null
  final String? paymentMethod;
  const _ParsedTxn({
    this.amount, this.description, this.category,
    this.txnType, this.paymentMethod,
  });
}

// Keyword → category map. Hand-tuned for Cameroonian English/Pidgin
// vocabulary; falls back to "Other" / "Other Income" when nothing matches.
const Map<String, List<String>> _kCategoryKeywords = {
  'Food':          ['food', 'lunch', 'dinner', 'breakfast', 'coffee', 'eat',
                    'meal', 'snack', 'restaurant', 'drink', 'beer', 'chop',
                    'pizza', 'burger', 'water', 'juice'],
  'Transport':     ['transport', 'taxi', 'bus', 'fuel', 'gas', 'petrol',
                    'ride', 'uber', 'bolt', 'moto', 'bike', 'travel',
                    'fare'],
  'Utilities':     ['utility', 'utilities', 'electricity', 'eneo', 'water',
                    'camwater', 'internet', 'wifi', 'data', 'airtime',
                    'credit'],
  'Rent':          ['rent', 'landlord', 'house rent'],
  'Healthcare':    ['medicine', 'hospital', 'doctor', 'pharmacy',
                    'healthcare', 'clinic', 'drug', 'consultation'],
  'Education':     ['school', 'tuition', 'books', 'education', 'fees',
                    'class', 'course', 'university'],
  'Business':      ['business', 'supplies', 'stock'],
  'Entertainment': ['movie', 'cinema', 'concert', 'entertainment', 'party',
                    'game', 'netflix', 'spotify', 'club'],
  'Shopping':      ['clothes', 'shoes', 'shopping', 'shop', 'market',
                    'phone', 'gift'],
  'Salary':              ['salary', 'wage', 'paycheck', 'pay'],
  'Business Income':     ['business income', 'sale', 'sold', 'customer paid',
                          'client paid', 'revenue'],
  'Investment Returns':  ['investment', 'dividend', 'return', 'interest',
                          'profit'],
  'Gifts':               ['gift received', 'present', 'birthday money'],
  'Njangi Payout':       ['njangi', 'tontine', 'meeting'],
};

const Map<String, List<String>> _kPaymentKeywords = {
  'Cash':         ['cash', 'liquid'],
  'MTN MoMo':     ['momo', 'mtn', 'mobile money', 'm-money'],
  'Orange Money': ['orange money', 'orange', ' om '],
  'Bank':         ['bank', 'transfer', 'wire'],
  'Card':         ['card', 'visa', 'mastercard'],
};

const List<String> _kIncomeVerbs = [
  'received', 'receive', 'earned', 'earn', 'got paid', 'paid me',
  'salary', 'income', 'made', 'collected',
];

const List<String> _kExpenseVerbs = [
  'spent', 'spend', 'bought', 'buy', 'paid for', 'paid', 'gave',
  'cost', 'expense',
];

/// Parses a free-form spoken sentence into expense fields.
///
/// Examples it should handle:
///   "Spent 5000 francs on coffee with momo"
///   "Bought transport 2000"
///   "Received salary 150000"
///   "5k for taxi"
_ParsedTxn _parseVoiceTxn(
  String raw, {
  required List<String> expenseCats,
  required List<String> incomeCats,
  required List<String> paymentMethods,
}) {
  final text = raw.toLowerCase().trim();
  if (text.isEmpty) return const _ParsedTxn();

  // ── Amount ────────────────────────────────────────────────────────────
  // Matches "5000", "5,000", "5 000", "5.000", and "5k"/"5K" shorthand.
  double? amount;
  final kMatch = RegExp(r'(\d+(?:[.,]\d+)?)\s*[kK]\b').firstMatch(text);
  if (kMatch != null) {
    final base = double.tryParse(kMatch.group(1)!.replaceAll(',', '.'));
    if (base != null) amount = base * 1000;
  }
  amount ??= () {
    final m = RegExp(r'\b(\d{1,3}(?:[ .,]\d{3})+|\d{2,7})\b').firstMatch(text);
    if (m == null) return null;
    final cleaned = m.group(1)!.replaceAll(RegExp(r'[ .,]'), '');
    return double.tryParse(cleaned);
  }();

  // ── Txn type ──────────────────────────────────────────────────────────
  String? txnType;
  if (_kIncomeVerbs.any(text.contains)) txnType = 'INCOME';
  if (_kExpenseVerbs.any(text.contains)) txnType = 'EXPENSE';
  // Category-driven fallback if no verb was heard.
  if (txnType == null) {
    if (incomeCats.any((c) => text.contains(c.toLowerCase()))) {
      txnType = 'INCOME';
    } else {
      txnType = 'EXPENSE';
    }
  }

  // ── Category ──────────────────────────────────────────────────────────
  String? category;
  final candidates = txnType == 'INCOME' ? incomeCats : expenseCats;
  // 1. Explicit category name spoken verbatim.
  for (final c in candidates) {
    if (text.contains(c.toLowerCase())) { category = c; break; }
  }
  // 2. Keyword map.
  if (category == null) {
    for (final entry in _kCategoryKeywords.entries) {
      if (!candidates.contains(entry.key)) continue;
      if (entry.value.any((kw) => text.contains(kw))) {
        category = entry.key;
        break;
      }
    }
  }
  category ??= txnType == 'INCOME' ? 'Other Income' : 'Other';
  if (!candidates.contains(category)) category = candidates.first;

  // ── Payment method ────────────────────────────────────────────────────
  String? paymentMethod;
  for (final entry in _kPaymentKeywords.entries) {
    if (!paymentMethods.contains(entry.key)) continue;
    if (entry.value.any((kw) => ' $text '.contains(kw))) {
      paymentMethod = entry.key;
      break;
    }
  }

  // ── Description ───────────────────────────────────────────────────────
  // Strip verbs, amount, payment hints, and noise words.
  var desc = raw.trim();
  final stripPatterns = <RegExp>[
    RegExp(r'\b\d+(?:[.,]\d+)?\s*[kK]\b'),
    RegExp(r'\b\d{1,3}(?:[ .,]\d{3})+\b'),
    RegExp(r'\b\d{2,7}\b'),
    RegExp(r'\b(fcfa|xaf|francs?|cfa)\b', caseSensitive: false),
    RegExp(r'\b(spent|spend|bought|buy|paid|received|receive|earned|earn|got|add|gave|cost|for|on|with|using|via|by|of|the|a|an|to)\b',
        caseSensitive: false),
  ];
  for (final p in stripPatterns) {
    desc = desc.replaceAll(p, ' ');
  }
  for (final pm in _kPaymentKeywords.values.expand((v) => v)) {
    desc = desc.replaceAll(RegExp(RegExp.escape(pm), caseSensitive: false), ' ');
  }
  desc = desc.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Capitalize first letter for nicer display.
  if (desc.isNotEmpty) {
    desc = desc[0].toUpperCase() + desc.substring(1);
  }
  final description = desc.isEmpty ? null : desc;

  return _ParsedTxn(
    amount: amount,
    description: description,
    category: category,
    txnType: txnType,
    paymentMethod: paymentMethod,
  );
}

class _VoiceCaptureSheet extends StatefulWidget {
  const _VoiceCaptureSheet();
  @override
  State<_VoiceCaptureSheet> createState() => _VoiceCaptureSheetState();
}

class _VoiceCaptureSheetState extends State<_VoiceCaptureSheet>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  late AnimationController _pulseCtrl;
  bool _available = false;
  bool _listening = false;
  String _transcript = '';
  String? _error;
  double _level = 0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _init();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    if (_speech.isListening) _speech.stop();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _available = await _speech.initialize(
        onStatus: (s) {
          if (!mounted) return;
          if (s == 'done' || s == 'notListening') {
            setState(() => _listening = false);
          }
        },
        onError: (e) {
          if (!mounted) return;
          setState(() {
            _error = e.errorMsg;
            _listening = false;
          });
        },
      );
      if (mounted) {
        setState(() {});
        if (_available) _start();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _start() {
    setState(() {
      _error = null;
      _transcript = '';
      _listening = true;
    });
    _speech.listen(
      onResult: (r) {
        if (!mounted) return;
        setState(() => _transcript = r.recognizedWords);
      },
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
      onSoundLevelChange: (lvl) {
        if (!mounted) return;
        // speech_to_text reports dB-ish values, usually -2..10; clamp to 0..1.
        setState(() => _level = ((lvl + 2) / 12).clamp(0.0, 1.0));
      },
    );
  }

  Future<void> _stopAndUse() async {
    if (_speech.isListening) await _speech.stop();
    if (!mounted) return;
    Navigator.pop(context, _transcript.trim());
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.only(bottom: viewInsets),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _DragHandle(),
          const SizedBox(height: 14),
          Text('Speak your expense',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  color: AppColors.text1)),
          const SizedBox(height: 6),
          Text('Try: "Spent 5000 on coffee with momo"',
              textAlign: TextAlign.center,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 12, color: AppColors.text3)),
          const SizedBox(height: 24),

          // Pulsing mic
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) {
              final pulse = _listening
                  ? 1.0 + _level * 0.35 + _pulseCtrl.value * 0.05
                  : 1.0;
              return Transform.scale(
                scale: pulse,
                child: Container(
                  width: 96, height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.purple.withOpacity(
                        _listening ? 0.22 : 0.12),
                    border: Border.all(
                        color: AppColors.purple.withOpacity(
                            _listening ? 0.5 : 0.3),
                        width: 2),
                  ),
                  child: Icon(
                    _listening ? Icons.mic_rounded : Icons.mic_off_rounded,
                    color: AppColors.purple, size: 38,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 22),

          Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border1),
            ),
            child: Text(
              _error != null
                  ? 'Error: ${_error!}'
                  : (_transcript.isEmpty
                      ? (_listening ? 'Listening…' :
                          (_available ? 'Tap the mic to start.'
                                      : 'Speech recognition unavailable.'))
                      : _transcript),
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 14,
                  color: _error != null
                      ? AppColors.danger
                      : (_transcript.isEmpty
                          ? AppColors.text3
                          : AppColors.text1),
                  height: 1.4),
            ),
          ),
          const SizedBox(height: 22),

          Row(children: [
            Expanded(child: NkapButton(
              label: 'Cancel',
              outlined: true,
              onTap: () async {
                if (_speech.isListening) await _speech.stop();
                if (mounted) Navigator.pop(context);
              },
            )),
            const SizedBox(width: 12),
            Expanded(child: NkapButton(
              label: _listening
                  ? 'Stop & use'
                  : (_transcript.isEmpty ? 'Listen' : 'Use this'),
              icon: _listening
                  ? Icons.stop_rounded
                  : (_transcript.isEmpty
                      ? Icons.mic_rounded
                      : Icons.check_rounded),
              onTap: !_available
                  ? null
                  : (_listening
                      ? _stopAndUse
                      : (_transcript.isEmpty ? _start : _stopAndUse)),
            )),
          ]),
        ]),
      ),
    );
  }
}
