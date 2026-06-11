import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';

String _fmt(num n) => n.abs().toStringAsFixed(0).replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

/// Two columns: This Month | Last Month. Delta arrows + colour coding.
/// Shape:
///   { "this_month": {"expenses": int, "top_category": str?},
///     "last_month": {"expenses": int, "top_category": str?} }
class MonthlyComparisonCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const MonthlyComparisonCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final tm = (data['this_month'] as Map?)?.cast<String, dynamic>() ?? {};
    final lm = (data['last_month'] as Map?)?.cast<String, dynamic>() ?? {};
    final thisExp = (tm['expenses'] as num?)?.toInt() ?? 0;
    final lastExp = (lm['expenses'] as num?)?.toInt() ?? 0;
    final delta   = thisExp - lastExp;
    final pct     = lastExp == 0 ? null : (delta / lastExp) * 100;

    final upIsBad = true; // expenses going up is bad
    Color deltaColor;
    if (delta == 0) {
      deltaColor = AppColors.text3;
    } else if ((delta > 0) == upIsBad) {
      deltaColor = AppColors.danger;
    } else {
      deltaColor = AppColors.primary;
    }
    final arrow = delta == 0 ? '→' : (delta > 0 ? '↑' : '↓');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('MONTH-OVER-MONTH',
            style: GoogleFonts.hankenGrotesk(
                color: AppColors.text3, fontSize: 9.5,
                fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _Column(
            label: 'This month',
            expenses: thisExp,
            topCategory: (tm['top_category'] ?? '—').toString(),
            highlight: true,
          )),
          const SizedBox(width: 12),
          Expanded(child: _Column(
            label: 'Last month',
            expenses: lastExp,
            topCategory: (lm['top_category'] ?? '—').toString(),
          )),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: deltaColor.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: deltaColor.withOpacity(0.25)),
          ),
          child: Row(children: [
            Text(arrow,
                style: GoogleFonts.hankenGrotesk(
                    color: deltaColor, fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Expanded(child: Text(
              delta == 0
                  ? 'Flat versus last month'
                  : '${delta > 0 ? "+" : "-"}${_fmt(delta.abs())} XAF '
                    '${pct == null ? "" : "(${pct.abs().toStringAsFixed(0)}%)"} '
                    '${delta > 0 ? "more" : "less"} than last month',
              style: GoogleFonts.hankenGrotesk(
                  color: deltaColor, fontSize: 12,
                  fontWeight: FontWeight.w700),
            )),
          ]),
        ),
      ]),
    );
  }
}

class _Column extends StatelessWidget {
  final String label, topCategory;
  final int expenses;
  final bool highlight;
  const _Column({
    required this.label, required this.expenses,
    required this.topCategory, this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight ? AppColors.primaryDim : AppColors.surface3,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color:
            highlight ? AppColors.primary.withOpacity(0.3) : AppColors.border1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: GoogleFonts.hankenGrotesk(
                color: AppColors.text3, fontSize: 10,
                fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        const SizedBox(height: 4),
        Text('${_fmt(expenses)} XAF',
            style: GoogleFonts.hankenGrotesk(
                color: AppColors.text1, fontSize: 16,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('Top: $topCategory',
            style: GoogleFonts.hankenGrotesk(
                color: AppColors.text2, fontSize: 11,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}
