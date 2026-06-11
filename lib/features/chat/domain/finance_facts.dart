import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/auto_save_engine.dart';
import '../../../../core/services/user_preferences.dart';

class FinanceFacts extends ChangeNotifier {
  FinanceFacts._();
  static final FinanceFacts instance = FinanceFacts._();

  String displayName = 'Glory';

  double totalBalance = 1234500;
  double monthlyIncome = 350000;
  double monthlyExpenses = 222000;
  double savedThisMonth = 35000;
  int savingStreak = 12;

  final List<({String day, double amount})> weeklySpend = [
    (day: 'Mon', amount: 12000), (day: 'Tue', amount: 8500),
    (day: 'Wed', amount: 25000), (day: 'Thu', amount: 5000),
    (day: 'Fri', amount: 18000), (day: 'Sat', amount: 32000),
    (day: 'Sun', amount: 9000),
  ];

  final List<({String name, String category, double amount, String date, Color color})> transactions = [
    (name: 'Central Market',  category: 'Food & Drink', amount: -8500,  date: 'Today',  color: const Color(0xFFFF7043)),
    (name: 'Moto Taxi',       category: 'Transport',    amount: -1500,  date: 'Today',  color: const Color(0xFF42A5F5)),
    (name: 'MTN Salary',      category: 'Income',       amount: 350000, date: 'Apr 28', color: const Color(0xFF12E8A4)),
    (name: 'Chez Paul Rest.', category: 'Food & Drink', amount: -5000,  date: 'Apr 28', color: const Color(0xFFFF7043)),
    (name: 'CAMTEL Internet', category: 'Utilities',    amount: -15000, date: 'Apr 27', color: const Color(0xFFAB47BC)),
  ];

  final Map<String, ({double limit, Color color, String emoji})> budgets = {
    'Food & Drink': (limit: 60000, color: const Color(0xFFFF7043), emoji: '🍴'),
    'Transport':    (limit: 25000, color: const Color(0xFF42A5F5), emoji: '🚗'),
    'Utilities':    (limit: 40000, color: const Color(0xFFAB47BC), emoji: '⚡'),
    'Shopping':     (limit: 30000, color: const Color(0xFFEC407A), emoji: '🛍️'),
  };

  final List<({String name, String emoji, double current, double target, Color color, String deadline})> goals = [
    (name: 'New Laptop',   emoji: '💻', current: 285000, target: 600000, color: const Color(0xFF60A5FA), deadline: 'Sep 2026'),
    (name: 'Tuition Q3',   emoji: '🎓', current: 410000, target: 500000, color: const Color(0xFF12E8A4), deadline: 'Jul 2026'),
    (name: 'Yaoundé Trip', emoji: '✈️', current: 55000,  target: 250000, color: const Color(0xFFFFB627), deadline: 'Dec 2026'),
    (name: 'Emergency',    emoji: '🛡️', current: 180000, target: 300000, color: const Color(0xFFA78BFA), deadline: 'Ongoing'),
  ];

  final List<({String name, double amount, String due, IconData icon, Color color})> bills = [
    (name: 'ENEO Electricity', amount: 18500, due: 'Tomorrow', icon: Icons.bolt_rounded,  color: const Color(0xFFFFB627)),
    (name: 'CAMTEL Internet',  amount: 15000, due: 'In 3 days', icon: Icons.wifi_rounded, color: const Color(0xFF60A5FA)),
    (name: 'Family Njangi',    amount: 25000, due: 'Apr 30',   icon: Icons.group_rounded, color: const Color(0xFFA78BFA)),
  ];

  String njangiGroup = 'Family Nkap';
  int njangiMembers = 8;
  double njangiNextPayout = 125000;
  String njangiNextTurn = 'Your turn this month';
  bool njangiYourTurn = true;

  // ── Auto-save engine state ──────────────────────────────────
  final AutoSaveEngine _autoSaveEngine = AutoSaveEngine();

  /// Successful auto-save events, newest first. Capped at 50 entries.
  final List<({DateTime time, double amount, String destination, String reason, String triggerSource})>
      autoSaveEvents = [];

  /// Skip reasons for the last few attempts, newest first. Useful for
  /// telling the user why nothing happened.
  final List<({DateTime time, String reason})> autoSaveSkips = [];

  final List<({String name, String initials, Color color})> contacts = [
    (name: 'Marie',   initials: 'MA', color: const Color(0xFFEC407A)),
    (name: 'Paul',    initials: 'PA', color: const Color(0xFF60A5FA)),
    (name: 'Family',  initials: 'FA', color: const Color(0xFF12E8A4)),
    (name: 'Cedric',  initials: 'CE', color: const Color(0xFFFFB627)),
    (name: 'Estelle', initials: 'ES', color: const Color(0xFFA78BFA)),
  ];

  ({String name, String initials, Color color})? findContact(String query) {
    final q = query.toLowerCase().trim();
    for (final c in contacts) {
      if (c.name.toLowerCase() == q) return c;
    }
    for (final c in contacts) {
      if (c.name.toLowerCase().startsWith(q)) return c;
    }
    return null;
  }

  // ── Derived / lookups ───────────────────────────────────────
  double get weeklyTotal => weeklySpend.fold(0.0, (s, e) => s + e.amount);

  ({String day, double amount}) get weeklyTop => weeklySpend.reduce((a, b) => a.amount > b.amount ? a : b);

  double spentThisMonthFor(String category) =>
      transactions.where((t) => t.category == category && t.amount < 0)
                  .fold(0.0, (s, t) => s + t.amount.abs());

  double get savingsRate {
    final inc = monthlyIncome;
    return inc == 0 ? 0 : (savedThisMonth / inc).clamp(0.0, 1.0);
  }

  // Case-insensitive category lookup; returns canonical key if found.
  String? matchCategory(String input) {
    final s = input.toLowerCase().trim();
    for (final k in budgets.keys) {
      if (k.toLowerCase() == s || k.toLowerCase().split(' ').first == s) return k;
    }
    const aliases = <String, String>{
      'food': 'Food & Drink', 'drink': 'Food & Drink', 'restaurant': 'Food & Drink',
      'market': 'Food & Drink', 'eat': 'Food & Drink', 'meal': 'Food & Drink',
      'lunch': 'Food & Drink', 'breakfast': 'Food & Drink', 'dinner': 'Food & Drink',
      'taxi': 'Transport', 'moto': 'Transport', 'bus': 'Transport', 'fuel': 'Transport',
      'transport': 'Transport', 'gas': 'Transport',
      'internet': 'Utilities', 'electricity': 'Utilities', 'water': 'Utilities',
      'bill': 'Utilities', 'utility': 'Utilities', 'eneo': 'Utilities', 'camtel': 'Utilities',
      'clothes': 'Shopping', 'shop': 'Shopping', 'shopping': 'Shopping',
    };
    return aliases[s];
  }

  // ── Auto-save event ledger ──────────────────────────────────
  double get autoSavedThisMonth {
    final now = DateTime.now();
    return autoSaveEvents
        .where((e) => e.time.year == now.year && e.time.month == now.month)
        .fold(0.0, (s, e) => s + e.amount);
  }

  ({DateTime time, double amount, String destination, String reason, String triggerSource})? get lastAutoSave =>
      autoSaveEvents.isEmpty ? null : autoSaveEvents.first;

  /// Considers the auto-save rule for a freshly-recorded event and, if the
  /// engine approves, moves money from totalBalance into the destination
  /// goal (or generic Locked Savings). Returns the decision so callers can
  /// surface it to the user.
  AutoSaveDecision _runAutoSaveFor(AutoSaveEventKind kind, String triggerSource) {
    final config = UserPreferences.instance.autoSave;
    final decision = _autoSaveEngine.evaluate(
      config: config,
      kind: kind,
      availableBalance: totalBalance,
      recentEvents: autoSaveEvents.map((e) => e.time).toList(),
    );

    if (!decision.save) {
      autoSaveSkips.insert(0, (time: DateTime.now(), reason: decision.reason));
      if (autoSaveSkips.length > 10) autoSaveSkips.removeLast();
      // Don't notifyListeners for pure skips — the calling mutation already will.
      return decision;
    }

    // Consume skip-next exactly once.
    if (config.skipNext) {
      UserPreferences.instance.setAutoSave(config.copyWith(skipNext: false));
    }

    final destName = decision.destinationGoalName;
    if (destName != null) {
      final i = goals.indexWhere((g) => g.name.toLowerCase() == destName.toLowerCase());
      if (i >= 0) {
        final g = goals[i];
        goals[i] = (
          name: g.name, emoji: g.emoji,
          current: g.current + decision.amount,
          target: g.target, color: g.color, deadline: g.deadline,
        );
      } else {
        // Configured destination no longer exists; fall through to generic bucket.
      }
    }
    savedThisMonth += decision.amount;
    totalBalance -= decision.amount;

    autoSaveEvents.insert(0, (
      time: DateTime.now(),
      amount: decision.amount,
      destination: destName ?? 'Locked Savings',
      reason: decision.reason,
      triggerSource: triggerSource,
    ));
    if (autoSaveEvents.length > 50) autoSaveEvents.removeLast();
    return decision;
  }

  // ── Mutations ───────────────────────────────────────────────
  ({String name, String category, double amount, String date, Color color}) recordExpense({
    required double amount,
    required String category,
    String? name,
  }) {
    final canon = matchCategory(category) ?? 'Other';
    final color = budgets[canon]?.color ?? AppColors.text2;
    final entry = (
      name: name ?? canon,
      category: canon,
      amount: -amount.abs(),
      date: 'Today',
      color: color,
    );
    transactions.insert(0, entry);
    monthlyExpenses += amount.abs();
    totalBalance -= amount.abs();
    _runAutoSaveFor(AutoSaveEventKind.expense, entry.name);
    notifyListeners();
    return entry;
  }

  ({String name, String category, double amount, String date, Color color}) recordIncome({
    required double amount,
    String name = 'Income',
    String category = 'Income',
  }) {
    final entry = (
      name: name,
      category: category,
      amount: amount.abs(),
      date: 'Today',
      color: const Color(0xFF12E8A4),
    );
    transactions.insert(0, entry);
    monthlyIncome += amount.abs();
    totalBalance += amount.abs();
    _runAutoSaveFor(AutoSaveEventKind.income, entry.name);
    notifyListeners();
    return entry;
  }

  ({String category, double oldLimit, double newLimit, Color color}) setBudget({
    required String category,
    required double limit,
  }) {
    final canon = matchCategory(category) ?? category;
    final existing = budgets[canon];
    final color = existing?.color ?? const Color(0xFF60A5FA);
    final emoji = existing?.emoji ?? '📊';
    final old = existing?.limit ?? 0;
    budgets[canon] = (limit: limit, color: color, emoji: emoji);
    notifyListeners();
    return (category: canon, oldLimit: old, newLimit: limit, color: color);
  }

  ({String recipient, double amount, Color color}) sendMoney({
    required String recipient,
    required double amount,
  }) {
    final contact = findContact(recipient);
    final color = contact?.color ?? const Color(0xFF12E8A4);
    final entry = (
      name: 'Sent to ${contact?.name ?? recipient}',
      category: 'Transfer',
      amount: -amount.abs(),
      date: 'Today',
      color: color,
    );
    transactions.insert(0, entry);
    totalBalance -= amount.abs();
    monthlyExpenses += amount.abs();
    _runAutoSaveFor(AutoSaveEventKind.transfer, entry.name);
    notifyListeners();
    return (recipient: contact?.name ?? recipient, amount: amount.abs(), color: color);
  }

  ({String name, String emoji, double current, double target, Color color, String deadline}) createGoal({
    required String name,
    required double target,
    String emoji = '🎯',
  }) {
    final palette = [
      const Color(0xFF60A5FA), const Color(0xFF12E8A4),
      const Color(0xFFFFB627), const Color(0xFFA78BFA),
      const Color(0xFFEC407A),
    ];
    final color = palette[goals.length % palette.length];
    final entry = (
      name: name, emoji: emoji, current: 0.0, target: target,
      color: color, deadline: 'Set deadline',
    );
    goals.add(entry);
    notifyListeners();
    return entry;
  }
}
