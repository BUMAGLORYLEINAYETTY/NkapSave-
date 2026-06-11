import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';

/// Render the spending-pattern detector output as a stack of alert rows.
/// Shape:
///   { "patterns": [{pattern_type, severity, description, amount, suggestion}, ...] }
class PatternAlertCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const PatternAlertCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final patterns = (data['patterns'] as List?)?.cast<Map>() ?? const [];
    if (patterns.isEmpty) {
      return _emptyState();
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < patterns.length; i++) ...[
          _PatternRow(p: patterns[i]),
          if (i < patterns.length - 1) const SizedBox(height: 10),
        ],
      ]),
    );
  }

  Widget _emptyState() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.border1),
    ),
    child: Row(children: [
      const Icon(Icons.check_circle_outline_rounded,
          color: AppColors.primary, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(
        'No spending patterns to flag this period — keep it up.',
        style: GoogleFonts.hankenGrotesk(
            color: AppColors.text2, fontSize: 12, height: 1.4),
      )),
    ]),
  );
}

class _PatternRow extends StatelessWidget {
  final Map p;
  const _PatternRow({required this.p});

  ({IconData icon, Color color}) _styleFor(String severity, String type) {
    if (type == 'mom_delta' || type == 'burn_rate') {
      return (icon: Icons.lightbulb_outline_rounded, color: AppColors.info);
    }
    switch (severity) {
      case 'critical':
        return (icon: Icons.error_outline_rounded, color: AppColors.danger);
      case 'warn':
        return (icon: Icons.warning_amber_rounded, color: AppColors.accent);
      default:
        return (icon: Icons.info_outline_rounded, color: AppColors.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = (p['pattern_type'] ?? '').toString();
    final sev  = (p['severity']     ?? 'info').toString();
    final desc = (p['description']  ?? '').toString();
    final sug  = (p['suggestion']   ?? '').toString();
    final s    = _styleFor(sev, type);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: s.color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: s.color.withOpacity(0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(s.icon, color: s.color, size: 18),
        const SizedBox(width: 11),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(desc,
                style: GoogleFonts.hankenGrotesk(
                    color: AppColors.text1, fontSize: 12.5,
                    fontWeight: FontWeight.w700, height: 1.4)),
            if (sug.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(sug,
                  style: GoogleFonts.hankenGrotesk(
                      color: AppColors.text2, fontSize: 11.5, height: 1.45)),
            ],
          ],
        )),
      ]),
    );
  }
}
