import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

enum AppFeature {
  expenses(
    id: 'expenses',
    emoji: '💸',
    title: 'Expense Tracking',
    tagline: 'Track every FCFA',
    description: 'Log spending, set budgets, and scan receipts — see exactly where your money goes.',
    color: Color(0xFFFF7043),
    route: '/expenses',
    navLabel: 'Expenses',
    navIconActive: Icons.bar_chart_rounded,
    navIconOutline: Icons.bar_chart_outlined,
  ),
  savings(
    id: 'savings',
    emoji: '🎯',
    title: 'Savings Goals',
    tagline: 'Save with Mobile Money',
    description: 'Set targets, auto-save from every MTN or Orange Money transfer, and track progress.',
    color: AppColors.primary,
    route: '/savings',
    navLabel: 'Savings',
    navIconActive: Icons.savings_rounded,
    navIconOutline: Icons.savings_outlined,
  ),
  njangi(
    id: 'njangi',
    emoji: '👥',
    title: 'Njangi Management',
    tagline: 'Digital rotating savings',
    description: 'Manage your tontine groups, track contributions, and get notified for every turn.',
    color: AppColors.purple,
    route: '/njangi',
    navLabel: 'Njangi',
    navIconActive: Icons.group_rounded,
    navIconOutline: Icons.group_outlined,
  );

  final String id, emoji, title, tagline, description, route, navLabel;
  final Color color;
  final IconData navIconActive, navIconOutline;

  const AppFeature({
    required this.id,
    required this.emoji,
    required this.title,
    required this.tagline,
    required this.description,
    required this.color,
    required this.route,
    required this.navLabel,
    required this.navIconActive,
    required this.navIconOutline,
  });

  static AppFeature? fromId(String id) {
    for (final f in AppFeature.values) {
      if (f.id == id) return f;
    }
    return null;
  }
}

/// A single question asked during profile setup, scoped to a feature.
class ProfileQuestion {
  final String id;
  final AppFeature feature;
  final String question;
  final String? hint;
  final List<String> quickAnswers;
  final bool isNumeric;
  const ProfileQuestion({
    required this.id,
    required this.feature,
    required this.question,
    this.hint,
    this.quickAnswers = const [],
    this.isNumeric = false,
  });
}

/// Adaptive question catalog — only questions for selected features get asked.
class ProfileQuestionCatalog {
  static const all = <ProfileQuestion>[
    // ── Savings ─────────────────────────────────────────────
    ProfileQuestion(
      id: 'savings_for',
      feature: AppFeature.savings,
      question: 'What are you saving for?',
      hint: 'Tell me your biggest goal — I\'ll help you reach it.',
      quickAnswers: ['Tuition / school', 'New phone or laptop', 'Emergency fund', 'A trip', 'My own business'],
    ),
    ProfileQuestion(
      id: 'monthly_income',
      feature: AppFeature.savings,
      question: 'Roughly, what do you earn per month?',
      hint: 'In FCFA. This stays on your device — used to suggest realistic saving amounts.',
      quickAnswers: ['50,000', '150,000', '300,000', '500,000', '1,000,000'],
      isNumeric: true,
    ),

    // ── Expenses ────────────────────────────────────────────
    ProfileQuestion(
      id: 'spending_challenge',
      feature: AppFeature.expenses,
      question: 'What\'s your biggest spending challenge?',
      hint: 'I\'ll prioritise alerts and budgets around this area.',
      quickAnswers: ['Food & eating out', 'Transport', 'Bills & utilities', 'Shopping', 'Family obligations'],
    ),
    ProfileQuestion(
      id: 'budget_scope',
      feature: AppFeature.expenses,
      question: 'Are you budgeting for yourself or a business?',
      quickAnswers: ['Just me', 'Family budget', 'Personal + small business', 'Business only'],
    ),

    // ── Njangi ──────────────────────────────────────────────
    ProfileQuestion(
      id: 'njangi_count',
      feature: AppFeature.njangi,
      question: 'How many Njangi groups are you in right now?',
      quickAnswers: ['None yet', '1', '2', '3 or more'],
    ),
    ProfileQuestion(
      id: 'njangi_amount',
      feature: AppFeature.njangi,
      question: 'What\'s your typical contribution per round?',
      hint: 'In FCFA.',
      quickAnswers: ['5,000', '10,000', '25,000', '50,000', '100,000'],
      isNumeric: true,
    ),

  ];

  static List<ProfileQuestion> forFeatures(Set<AppFeature> features) =>
      all.where((q) => features.contains(q.feature)).toList();
}
