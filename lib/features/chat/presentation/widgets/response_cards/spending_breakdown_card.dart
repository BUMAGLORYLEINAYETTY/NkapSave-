import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';

String _fmt(num n) => n.abs().toStringAsFixed(0).replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

/// Horizontal bars per category. Each bar:
///   - green when within budget, red when over (or amber when no budget set)
///   - amount + share of month total
/// Shape:
///   { "month_total": int, "prev_month_total": int,
///     "bars": [{category, amount, limit, over}, ...] }
class SpendingBreakdownCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const SpendingBreakdownCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final total = (data['month_total']      as num?)?.toInt() ?? 0;
    final prev  = (data['prev_month_total'] as num?)?.toInt() ?? 0;
    final bars  = (data['bars'] as List?)?.cast<Map>() ?? const [];

    final maxAmount = bars.isEmpty
        ? 1
        : bars.map((b) => (b['amount'] as num?)?.toInt() ?? 0)
              .reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('THIS MONTH',
              style: GoogleFonts.hankenGrotesk(
                  color: AppColors.text3, fontSize: 9.5,
                  fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          Text('${_fmt(total)} XAF',
              style: GoogleFonts.hankenGrotesk(
                  color: AppColors.text1, fontSize: 13,
                  fontWeight: FontWeight.w800)),
        ]),
        if (prev > 0) ...[
          const SizedBox(height: 2),
          Text('vs ${_fmt(prev)} XAF last month',
              style: GoogleFonts.hankenGrotesk(
                  color: AppColors.text3, fontSize: 11)),
        ],
        const SizedBox(height: 14),
        if (bars.isEmpty)
          Text('No expense data this month yet.',
              style: GoogleFonts.hankenGrotesk(
                  color: AppColors.text3, fontSize: 12))
        else
          for (final b in bars) ...[
            _Bar(
              category: (b['category'] ?? '').toString(),
              amount:   (b['amount']   as num?)?.toInt() ?? 0,
              limit:    (b['limit']    as num?)?.toInt(),
              over:     b['over'] == true,
              maxAmount: maxAmount,
              total:    total,
            ),
            const SizedBox(height: 10),
          ],
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  final String category;
  final int amount, maxAmount, total;
  final int? limit;
  final bool over;
  const _Bar({
    required this.category, required this.amount,
    required this.maxAmount, required this.total,
    this.limit, required this.over,
  });

  @override
  Widget build(BuildContext context) {
    final color = over
        ? AppColors.danger
        : (limit == null ? AppColors.accent : AppColors.primary);
    final share = total == 0 ? 0.0 : amount / total;
    final width = amount / maxAmount;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(category,
            style: GoogleFonts.hankenGrotesk(
                color: AppColors.text1, fontSize: 12,
                fontWeight: FontWeight.w600))),
        Text('${_fmt(amount)} XAF',
            style: GoogleFonts.hankenGrotesk(
                color: color, fontSize: 12,
                fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Text('(${(share * 100).toStringAsFixed(0)}%)',
            style: GoogleFonts.hankenGrotesk(
                color: AppColors.text3, fontSize: 10)),
      ]),
      const SizedBox(height: 5),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: Stack(children: [
          Container(height: 6, color: AppColors.surface4),
          FractionallySizedBox(
            widthFactor: width.clamp(0.02, 1.0),
            child: Container(height: 6, color: color),
          ),
        ]),
      ),
      if (limit != null) ...[
        const SizedBox(height: 3),
        Text(over
            ? 'Over budget — limit ${_fmt(limit!)} XAF'
            : 'Budget ${_fmt(limit!)} XAF',
            style: GoogleFonts.hankenGrotesk(
                color: over ? AppColors.danger : AppColors.text3,
                fontSize: 10,
                fontWeight: over ? FontWeight.w600 : FontWeight.w400)),
      ],
    ]);
  }
}
