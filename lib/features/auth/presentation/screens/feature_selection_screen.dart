import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/preferences/app_feature.dart';
import '../../../../core/services/user_preferences.dart';
import '../../../../core/widgets/nkap_button.dart';

class FeatureSelectionScreen extends StatefulWidget {
  const FeatureSelectionScreen({super.key});
  @override
  State<FeatureSelectionScreen> createState() => _FeatureSelectionScreenState();
}

class _FeatureSelectionScreenState extends State<FeatureSelectionScreen> with TickerProviderStateMixin {
  final Set<AppFeature> _selected = {};
  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    final existing = UserPreferences.instance.explicitFeatures;
    if (existing.isNotEmpty) _selected.addAll(existing);
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() { _fadeCtrl.dispose(); super.dispose(); }

  void _toggle(AppFeature f) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(f)) {
        _selected.remove(f);
      } else {
        _selected.add(f);
      }
    });
  }

  Future<void> _continue() async {
    HapticFeedback.mediumImpact();
    await UserPreferences.instance.setFeatures(_selected);
    if (!mounted) return;
    context.go('/profile-setup');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(children: [
            _header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                children: [
                  for (final f in AppFeature.values) ...[
                    _FeatureCard(
                      feature: f,
                      selected: _selected.contains(f),
                      onTap: () => _toggle(f),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            _footer(),
          ]),
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primaryDim,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppColors.primaryMid),
          ),
          child: Text('STEP 1 OF 2',
              style: GoogleFonts.hankenGrotesk(color: AppColors.primary, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
        ),
      ]),
      const SizedBox(height: 16),
      Text("What would you like to use NkapSave for?",
          style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 22, fontWeight: FontWeight.w800, height: 1.2)),
      const SizedBox(height: 6),
      Text("Pick one or more. You can change this anytime from your profile.",
          style: GoogleFonts.hankenGrotesk(color: AppColors.text2, fontSize: 13, height: 1.4)),
    ]),
  );

  Widget _footer() {
    final count = _selected.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: count == 0
            ? Padding(
                key: const ValueKey('hint'),
                padding: const EdgeInsets.only(bottom: 10),
                child: Text("Tap any card to get started",
                    style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 12)),
              )
            : Padding(
                key: ValueKey('count-$count'),
                padding: const EdgeInsets.only(bottom: 10),
                child: Text("$count feature${count == 1 ? '' : 's'} selected",
                    style: GoogleFonts.hankenGrotesk(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
        ),
        NkapButton(
          label: 'Continue',
          icon: Icons.arrow_forward_rounded,
          onTap: count == 0 ? null : _continue,
        ),
      ]),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final AppFeature feature;
  final bool selected;
  final VoidCallback onTap;
  const _FeatureCard({required this.feature, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? feature.color.withOpacity(0.08) : AppColors.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? feature.color : AppColors.border2,
            width: selected ? 1.8 : 1,
          ),
          boxShadow: selected
            ? [BoxShadow(color: feature.color.withOpacity(0.18), blurRadius: 18, spreadRadius: -2)]
            : null,
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(
              color: feature.color.withOpacity(selected ? 0.2 : 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: feature.color.withOpacity(0.3)),
            ),
            child: Center(child: Text(feature.emoji, style: const TextStyle(fontSize: 24))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(feature.title,
                  style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 15, fontWeight: FontWeight.w800))),
              const SizedBox(width: 8),
              Text(feature.tagline,
                  style: GoogleFonts.hankenGrotesk(color: feature.color, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Text(feature.description,
                style: GoogleFonts.hankenGrotesk(color: AppColors.text2, fontSize: 12, height: 1.45)),
          ])),
          const SizedBox(width: 10),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 24, height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? feature.color : Colors.transparent,
              border: Border.all(color: selected ? feature.color : AppColors.border3, width: 1.6),
            ),
            child: selected
                ?  Icon(Icons.check_rounded, color: AppColors.surface1, size: 16)
                : null,
          ),
        ]),
      ),
    );
  }
}
