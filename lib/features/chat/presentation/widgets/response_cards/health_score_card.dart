import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';

/// Renders the financial-health-score payload from the backend.
/// Shape:
///   { "overall_score": int, "rating": str,
///     "components": [{key, score, weight, explanation}, ...],
///     "top_improvement_tip": str }
class HealthScoreCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const HealthScoreCard({super.key, required this.data});

  Color _scoreColor(int s) {
    if (s >= 80) return AppColors.primary;          // green
    if (s >= 60) return AppColors.accent;            // yellow
    if (s >= 40) return AppColors.accent;            // amber
    return AppColors.danger;                          // red
  }

  String _componentLabel(String key) {
    switch (key) {
      case 'savings_rate':         return 'Savings rate';
      case 'budget_adherence':     return 'Budget adherence';
      case 'njangi_trust':         return 'Njangi trust';
      case 'goal_progress':        return 'Goal progress';
      case 'autosave_consistency': return 'Auto-save consistency';
      default:                     return key;
    }
  }

  @override
  Widget build(BuildContext context) {
    final overall = (data['overall_score'] as num?)?.toInt() ?? 0;
    final rating  = (data['rating'] ?? '').toString();
    final tip     = (data['top_improvement_tip'] ?? '').toString();
    final comps   = (data['components'] as List?)?.cast<Map>() ?? const [];
    final color   = _scoreColor(overall);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.1),
            blurRadius: 18, spreadRadius: -4)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Gauge(score: overall, color: color),
          const SizedBox(width: 16),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('FINANCIAL HEALTH',
                  style: GoogleFonts.hankenGrotesk(
                      color: AppColors.text3, fontSize: 9.5,
                      fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 4),
              Text('$overall / 100',
                  style: GoogleFonts.hankenGrotesk(
                      color: AppColors.text1, fontSize: 26,
                      fontWeight: FontWeight.w800, height: 1)),
              const SizedBox(height: 4),
              Text(rating,
                  style: GoogleFonts.hankenGrotesk(
                      color: color, fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          )),
        ]),
        const SizedBox(height: 16),
        for (final c in comps) ...[
          _ComponentRow(
            label:       _componentLabel(c['key']?.toString() ?? ''),
            score:       (c['score'] as num?)?.toInt() ?? 0,
            weight:      (c['weight'] as num?)?.toDouble() ?? 0,
            explanation: (c['explanation'] ?? '').toString(),
            color:       _scoreColor((c['score'] as num?)?.toInt() ?? 0),
          ),
          const SizedBox(height: 8),
        ],
        if (tip.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryDim,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.25)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lightbulb_outline_rounded,
                  color: AppColors.primary, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(tip,
                  style: GoogleFonts.hankenGrotesk(
                      color: AppColors.text1, fontSize: 12.5, height: 1.4,
                      fontWeight: FontWeight.w500))),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _Gauge extends StatelessWidget {
  final int score;
  final Color color;
  const _Gauge({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76, height: 76,
      child: CustomPaint(painter: _GaugePainter(score: score, color: color)),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final int score;
  final Color color;
  _GaugePainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;
    final track = Paint()
      ..color = AppColors.surface4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 8;
    final progress = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 8;
    canvas.drawCircle(center, radius, track);
    final sweep = (score.clamp(0, 100) / 100) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, sweep, false, progress,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.score != score || oldDelegate.color != color;
}

class _ComponentRow extends StatelessWidget {
  final String label, explanation;
  final int score;
  final double weight;
  final Color color;
  const _ComponentRow({
    required this.label, required this.score, required this.weight,
    required this.explanation, required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 38, height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text('$score',
            style: GoogleFonts.hankenGrotesk(
                color: color, fontSize: 13, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(width: 11),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(label,
                style: GoogleFonts.hankenGrotesk(
                    color: AppColors.text1, fontSize: 12.5,
                    fontWeight: FontWeight.w700))),
            Text('${(weight * 100).round()}%',
                style: GoogleFonts.hankenGrotesk(
                    color: AppColors.text3, fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 2),
          Text(explanation,
              style: GoogleFonts.hankenGrotesk(
                  color: AppColors.text2, fontSize: 11, height: 1.35)),
        ],
      )),
    ]);
  }
}
