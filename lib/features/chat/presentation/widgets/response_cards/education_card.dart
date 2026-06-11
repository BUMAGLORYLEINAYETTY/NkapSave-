import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../../core/constants/app_colors.dart';

/// Article-style education card with an XAF example box and related-topic chips.
/// Shape:
///   { "topic_key", "title", "content", "language",
///     "xaf_example": str?, "related_topics": [str] }
class EducationCard extends StatelessWidget {
  final Map<String, dynamic> data;
  /// Called when the user taps a related-topic chip. Pass the localised
  /// label up so the caller can fire it as a new user message.
  final void Function(String relatedKey)? onRelatedTap;
  const EducationCard({super.key, required this.data, this.onRelatedTap});

  @override
  Widget build(BuildContext context) {
    final title   = (data['title']   ?? '').toString();
    final content = (data['content'] ?? '').toString();
    final example = data['xaf_example'] as String?;
    final related = (data['related_topics'] as List?)?.cast<String>() ?? const [];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.info.withOpacity(0.3)),
            ),
            child: const Icon(Icons.menu_book_rounded,
                color: AppColors.info, size: 18),
          ),
          const SizedBox(width: 11),
          Expanded(child: Text(title,
              style: GoogleFonts.hankenGrotesk(
                  color: AppColors.text1, fontSize: 16,
                  fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 14),
        Text(content,
            style: GoogleFonts.hankenGrotesk(
                color: AppColors.text2, fontSize: 13, height: 1.55)),
        if (example != null && example.isNotEmpty) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.info.withOpacity(0.25)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lightbulb_outline_rounded,
                  color: AppColors.info, size: 16),
              const SizedBox(width: 10),
              Expanded(child: Text(example,
                  style: GoogleFonts.hankenGrotesk(
                      color: AppColors.text1, fontSize: 12.5,
                      fontWeight: FontWeight.w500, height: 1.45))),
            ]),
          ),
        ],
        if (related.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('RELATED',
              style: GoogleFonts.hankenGrotesk(
                  color: AppColors.text3, fontSize: 9.5,
                  fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final r in related)
              InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: onRelatedTap == null ? null : () => onRelatedTap!(r),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surface3,
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: AppColors.border2),
                  ),
                  child: Text(_humanise(r),
                      style: GoogleFonts.hankenGrotesk(
                          color: AppColors.text2, fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ),
          ]),
        ],
      ]),
    );
  }

  String _humanise(String key) =>
      key.replaceAll('_', ' ').replaceFirstMapped(
          RegExp(r'^.'), (m) => m.group(0)!.toUpperCase());
}
