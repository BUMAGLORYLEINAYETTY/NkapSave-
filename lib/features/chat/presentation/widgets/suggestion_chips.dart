import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/preferences/app_feature.dart';
import '../../../../core/services/user_preferences.dart';

/// Quick-tap suggestions shown when the conversation is empty. Composed
/// from a small core set + feature-gated chips so a user who only picked
/// "Savings" doesn't see expense or njangi prompts.
class SuggestionChips extends StatelessWidget {
  /// Called when the user taps a chip. Pass the chip's label so the
  /// caller can fire it through the controller verbatim.
  final void Function(String prompt) onTap;
  const SuggestionChips({super.key, required this.onTap});

  List<_Chip> _chipsFor(Set<AppFeature> enabled, String lang) {
    final isFr     = lang == 'fr';
    final isPidgin = lang == 'pidgin';
    String t(String en, String fr, String pidgin) =>
        isFr ? fr : (isPidgin ? pidgin : en);

    final core = <_Chip>[
      _Chip(
        emoji: '❤️',
        label: t('My financial health',
                 'Ma santé financière',
                 'How my money dey'),
      ),
      _Chip(
        emoji: '💰',
        label: t('Am I saving enough?',
                 'Est-ce que j\'épargne assez ?',
                 'I dey save enough?'),
      ),
    ];

    if (enabled.contains(AppFeature.expenses)) {
      core.addAll([
        _Chip(
          emoji: '🔍',
          label: t('Where do I waste money?',
                   'Où est-ce que je gaspille ?',
                   'Where my money dey waste?'),
        ),
        _Chip(
          emoji: '📊',
          label: t('Compare this month',
                   'Comparer ce mois',
                   'Compare this month'),
        ),
      ]);
    }
    if (enabled.contains(AppFeature.savings)) {
      core.addAll([
        _Chip(
          emoji: '🎯',
          label: t('When do I hit my goal?',
                   'Quand vais-je atteindre mon objectif ?',
                   'When I go reach my goal?'),
        ),
        _Chip(
          emoji: '📈',
          label: t('My savings rate',
                   'Mon taux d\'épargne',
                   'My savings rate'),
        ),
      ]);
    }
    if (enabled.contains(AppFeature.njangi)) {
      core.addAll([
        _Chip(
          emoji: '👥',
          label: t('My Njangi status',
                   'Mon statut Njangi',
                   'My Njangi status'),
        ),
        _Chip(
          emoji: '📅',
          label: t('Explain my payout',
                   'Expliquer mon tour',
                   'Explain my payout'),
        ),
      ]);
    }

    core.addAll([
      _Chip(
        emoji: '🛡️',
        label: t('What is an emergency fund?',
                 'Qu\'est-ce qu\'un fonds d\'urgence ?',
                 'Wetin be emergency fund?'),
      ),
      _Chip(
        emoji: '📒',
        label: t('How do I budget?',
                 'Comment faire un budget ?',
                 'How I go plan my money?'),
      ),
    ]);

    return core;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: UserPreferences.instance,
      builder: (ctx, _) {
        final lang = UserPreferences.instance.profile['preferred_language']
                    ?? 'en';
        final enabled = UserPreferences.instance.enabledFeatures;
        final chips = _chipsFor(enabled, lang);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in chips)
              InkWell(
                borderRadius: BorderRadius.circular(99),
                onTap: () => onTap(c.label),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface4,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(c.emoji, style: const TextStyle(fontSize: 13)),
                    const SizedBox(width: 7),
                    Text(c.label,
                        style: AppTextStyles.h4.copyWith(color: AppColors.text2)),
                  ]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Chip {
  final String emoji, label;
  const _Chip({required this.emoji, required this.label});
}
