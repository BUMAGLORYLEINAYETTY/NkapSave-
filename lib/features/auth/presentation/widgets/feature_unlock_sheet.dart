import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/preferences/app_feature.dart';
import '../../../../core/services/user_preferences.dart';
import '../../../../core/widgets/nkap_button.dart';

/// Shown after the user enables a previously-disabled feature from the
/// Profile screen. Gives a brief contextual intro before the tab appears.
Future<void> showFeatureUnlockSheet(BuildContext context, AppFeature feature) {
  HapticFeedback.mediumImpact();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.55),
    useSafeArea: true,
    builder: (_) => _FeatureUnlockSheet(feature: feature),
  );
}

class _FeatureUnlockSheet extends StatefulWidget {
  final AppFeature feature;
  const _FeatureUnlockSheet({required this.feature});
  @override
  State<_FeatureUnlockSheet> createState() => _FeatureUnlockSheetState();
}

class _FeatureUnlockSheetState extends State<_FeatureUnlockSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..forward();
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  List<({IconData icon, String title, String body})> _highlights() {
    switch (widget.feature) {
      case AppFeature.expenses:
        return const [
          (icon: Icons.receipt_long_rounded, title: 'Smart logging',
              body: 'Tell NkapBot "I spent 5,000 on taxi" — it categorises and records automatically.'),
          (icon: Icons.pie_chart_rounded, title: 'Live budgets',
              body: 'Set monthly limits per category and get alerts before you go over.'),
          (icon: Icons.bolt_rounded, title: 'Spending insights',
              body: 'Weekly summaries showing exactly where your money is going.'),
        ];
      case AppFeature.savings:
        return const [
          (icon: Icons.flag_rounded, title: 'Goals that move',
              body: 'Set targets like "New laptop — 600,000" and watch progress fill up.'),
          (icon: Icons.electric_bolt_rounded, title: 'Auto-save',
              body: 'Skim a percentage of every Mobile Money transfer into a locked wallet.'),
          (icon: Icons.shield_rounded, title: 'Locked savings',
              body: 'Funds you can\'t spend impulsively — unlock on your chosen date.'),
        ];
      case AppFeature.njangi:
        return const [
          (icon: Icons.groups_rounded, title: 'Digital tontines',
              body: 'Run rotating savings groups with trust scores and instant payouts.'),
          (icon: Icons.notifications_active_rounded, title: 'Never miss a turn',
              body: 'Reminders before every contribution and celebration when it\'s your turn.'),
          (icon: Icons.verified_rounded, title: 'Member transparency',
              body: 'See everyone\'s contribution history and reliability score.'),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.feature;
    final highlights = _highlights();
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration:  BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.border3, borderRadius: BorderRadius.circular(99)),
          ),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
              children: [
                Center(child: ScaleTransition(
                  scale: _scale,
                  child: Container(
                    width: 96, height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [f.color.withOpacity(0.3), f.color.withOpacity(0.08)],
                      ),
                      border: Border.all(color: f.color.withOpacity(0.4), width: 1.8),
                      boxShadow: [BoxShadow(color: f.color.withOpacity(0.3), blurRadius: 24, spreadRadius: 2)],
                    ),
                    child: Center(child: Text(f.emoji, style: const TextStyle(fontSize: 44))),
                  ),
                )),
                const SizedBox(height: 22),
                Center(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: f.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: f.color.withOpacity(0.35)),
                  ),
                  child: Text('UNLOCKED',
                      style: GoogleFonts.hankenGrotesk(color: f.color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                )),
                const SizedBox(height: 14),
                Center(child: Text(f.title,
                    style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 24, fontWeight: FontWeight.w800))),
                const SizedBox(height: 6),
                Center(child: Text(f.tagline,
                    style: GoogleFonts.hankenGrotesk(color: f.color, fontSize: 13, fontWeight: FontWeight.w700))),
                const SizedBox(height: 24),
                for (final h in highlights) ...[
                  _highlightRow(h.icon, h.title, h.body, f.color),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 22),
            child: NkapButton(
              label: "Let's go",
              icon: Icons.arrow_forward_rounded,
              color: f.color,
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _highlightRow(IconData icon, String title, String body, Color color) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border1),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(body, style: GoogleFonts.hankenGrotesk(color: AppColors.text2, fontSize: 12, height: 1.45)),
      ])),
    ]),
  );
}

/// Helper that toggles a feature and shows the unlock sheet when enabling.
Future<void> toggleFeatureWithUnlock(BuildContext context, AppFeature feature, bool enable) async {
  if (enable) {
    await UserPreferences.instance.enableFeature(feature);
    if (context.mounted) await showFeatureUnlockSheet(context, feature);
  } else {
    HapticFeedback.selectionClick();
    await UserPreferences.instance.disableFeature(feature);
  }
}
