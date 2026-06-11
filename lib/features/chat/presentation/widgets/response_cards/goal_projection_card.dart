import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';

String _fmt(num n) => n.abs().toStringAsFixed(0).replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

/// Renders a goal's progress + two "weeks to go" scenarios.
/// Shape:
///   { "name", "emoji", "current", "target",
///     "per_period", "frequency",
///     "weeks_at_current", "bumped_amount", "weeks_at_bumped" }
class GoalProjectionCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const GoalProjectionCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final name        = (data['name']  ?? '').toString();
    final emoji       = (data['emoji'] ?? '🎯').toString();
    final current     = (data['current'] as num?)?.toInt() ?? 0;
    final target      = (data['target']  as num?)?.toInt() ?? 1;
    final progress    = (current / target).clamp(0.0, 1.0);
    final perPeriod   = (data['per_period'] as num?)?.toInt();
    final frequency   = (data['frequency'] ?? 'weekly').toString();
    final weeksCur    = (data['weeks_at_current'] as num?)?.toInt();
    final bumpedAmt   = (data['bumped_amount']    as num?)?.toInt();
    final weeksBumped = (data['weeks_at_bumped']  as num?)?.toInt();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryDim,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primaryMid),
            ),
            child: Center(child: Text(emoji,
                style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: GoogleFonts.hankenGrotesk(
                      color: AppColors.text1, fontSize: 14,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('${_fmt(current)} / ${_fmt(target)} XAF · '
                   '${(progress * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.hankenGrotesk(
                      color: AppColors.text3, fontSize: 11)),
            ],
          )),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress, minHeight: 6,
            backgroundColor: AppColors.surface4,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
        const SizedBox(height: 14),
        if (perPeriod != null && weeksCur != null)
          _ScenarioRow(
            label: 'At current pace',
            sublabel: '${_fmt(perPeriod)} XAF / $frequency',
            weeks: weeksCur,
            color: AppColors.text1,
          ),
        if (bumpedAmt != null && weeksBumped != null) ...[
          const SizedBox(height: 8),
          _ScenarioRow(
            label: 'If you bump to',
            sublabel: '${_fmt(bumpedAmt)} XAF / $frequency',
            weeks: weeksBumped,
            color: AppColors.primary,
            highlight: true,
          ),
        ],
        if (perPeriod == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('No auto-save plan attached. Set one up to see a projection.',
                style: GoogleFonts.hankenGrotesk(
                    color: AppColors.text3, fontSize: 11.5, height: 1.4)),
          ),
      ]),
    );
  }
}

class _ScenarioRow extends StatelessWidget {
  final String label, sublabel;
  final int weeks;
  final Color color;
  final bool highlight;
  const _ScenarioRow({
    required this.label, required this.sublabel, required this.weeks,
    required this.color, this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? AppColors.primaryDim : AppColors.surface3,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight
              ? AppColors.primary.withOpacity(0.3)
              : AppColors.border1,
        ),
      ),
      child: Row(children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.hankenGrotesk(
                    color: AppColors.text3, fontSize: 10,
                    fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 2),
            Text(sublabel,
                style: GoogleFonts.hankenGrotesk(
                    color: AppColors.text1, fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
        )),
        Text('$weeks ${weeks == 1 ? "week" : "weeks"}',
            style: GoogleFonts.hankenGrotesk(
                color: color, fontSize: 14, fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
