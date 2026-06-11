import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/preferences/app_feature.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/user_preferences.dart';
import '../../../../core/widgets/nkap_button.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> with TickerProviderStateMixin {
  late final List<ProfileQuestion> _questions;
  final Map<String, String> _answers = {};
  final _textCtrl = TextEditingController();
  final _focus = FocusNode();
  int _index = 0;

  late final AnimationController _slideCtrl;
  late final Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _questions = ProfileQuestionCatalog.forFeatures(UserPreferences.instance.enabledFeatures);
    _slideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))..forward();
    _slideAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic);

    if (_questions.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    } else {
      _textCtrl.text = UserPreferences.instance.answer(_questions[0].id) ?? '';
    }
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _textCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  ProfileQuestion get _current => _questions[_index];

  bool get _canAdvance {
    final answer = _textCtrl.text.trim();
    return answer.isNotEmpty;
  }

  Future<void> _next() async {
    final answer = _textCtrl.text.trim();
    if (answer.isEmpty) return;
    HapticFeedback.lightImpact();
    _answers[_current.id] = answer;

    if (_index >= _questions.length - 1) {
      await _finish();
      return;
    }

    setState(() {
      _index++;
      _textCtrl.text = _answers[_questions[_index].id]
          ?? UserPreferences.instance.answer(_questions[_index].id)
          ?? '';
    });
    _focus.unfocus();
    _slideCtrl.forward(from: 0);
  }

  void _back() {
    if (_index == 0) {
      context.go('/feature-select');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _index--;
      _textCtrl.text = _answers[_questions[_index].id]
          ?? UserPreferences.instance.answer(_questions[_index].id)
          ?? '';
    });
    _slideCtrl.forward(from: 0);
  }

  /// Maps the free-text "monthly_income" answer (e.g. "150,000") to one of
  /// the six discrete brackets the backend stores.
  String? _bracketFromIncomeAnswer(String? raw) {
    if (raw == null) return null;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final n = int.tryParse(digits);
    if (n == null || n <= 0) return null;
    if (n < 50000)    return 'under_50k';
    if (n < 100000)   return '50k_100k';
    if (n < 300000)   return '100k_300k';
    if (n < 500000)   return '300k_500k';
    if (n < 1000000)  return '500k_1m';
    return 'over_1m';
  }

  Future<void> _persistToBackend() async {
    // Best-effort sync to the user's account so NkapBot has them on the
    // very next request. We swallow errors — the user can still set both
    // fields explicitly in Profile if this fails.
    final bracket = _bracketFromIncomeAnswer(_answers['monthly_income']);
    if (bracket == null) return;
    try {
      await ApiService.updateProfile(incomeBracket: bracket);
    } catch (_) {/* non-fatal */}
  }

  Future<void> _finish() async {
    await UserPreferences.instance.setProfileAnswers(_answers);
    await _persistToBackend();
    if (!mounted) return;
    context.go('/register');
  }

  Future<void> _skip() async {
    HapticFeedback.selectionClick();
    await UserPreferences.instance.setProfileAnswers(_answers);
    await _persistToBackend();
    if (!mounted) return;
    context.go('/register');
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) {
      return  Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          _header(),
          Expanded(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              behavior: HitTestBehavior.opaque,
              child: SlideTransition(
                position: Tween<Offset>(begin: const Offset(0.05, 0), end: Offset.zero).animate(_slideAnim),
                child: FadeTransition(
                  opacity: _slideAnim,
                  child: _questionBody(),
                ),
              ),
            ),
          ),
          _footer(),
        ]),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
            onTap: _back,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(8),
              child:  Icon(Icons.arrow_back_rounded, color: AppColors.text2, size: 22),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: _progressBar()),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _skip,
            child: Text('Skip', style: GoogleFonts.hankenGrotesk(color: AppColors.text2, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _current.feature.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: _current.feature.color.withOpacity(0.35)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_current.feature.emoji, style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 5),
              Text(_current.feature.title,
                  style: GoogleFonts.hankenGrotesk(color: _current.feature.color, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _progressBar() {
    final progress = (_index + 1) / _questions.length;
    return Stack(children: [
      Container(
        height: 6,
        decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(99)),
      ),
      AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        height: 6,
        width: (MediaQuery.of(context).size.width - 80) * progress.clamp(0.0, 1.0),
        decoration: BoxDecoration(color: _current.feature.color, borderRadius: BorderRadius.circular(99)),
      ),
    ]);
  }

  Widget _questionBody() {
    return ListView(
      key: ValueKey(_current.id),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        Text("Question ${_index + 1} of ${_questions.length}",
            style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 10),
        Text(_current.question,
            style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 22, fontWeight: FontWeight.w800, height: 1.25)),
        if (_current.hint != null) ...[
          const SizedBox(height: 8),
          Text(_current.hint!,
              style: GoogleFonts.hankenGrotesk(color: AppColors.text2, fontSize: 13, height: 1.45)),
        ],
        const SizedBox(height: 22),
        if (_current.quickAnswers.isNotEmpty) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final qa in _current.quickAnswers)
              _quickAnswerChip(qa),
          ]),
          const SizedBox(height: 16),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border2),
          ),
          child: TextField(
            controller: _textCtrl,
            focusNode: _focus,
            style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 14),
            cursorColor: _current.feature.color,
            keyboardType: _current.isNumeric ? TextInputType.number : TextInputType.text,
            inputFormatters: _current.isNumeric
                ? [FilteringTextInputFormatter.digitsOnly]
                : null,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: _current.isNumeric ? 'Or type a number' : 'Or type your answer',
              hintStyle: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 14),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) { if (_canAdvance) _next(); },
            textInputAction: TextInputAction.done,
          ),
        ),
      ],
    );
  }

  Widget _quickAnswerChip(String label) {
    final selected = _textCtrl.text.trim() == label;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _textCtrl.text = label;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? _current.feature.color.withOpacity(0.15) : AppColors.surface2,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? _current.feature.color : AppColors.border2,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(label,
            style: GoogleFonts.hankenGrotesk(
              color: selected ? _current.feature.color : AppColors.text1,
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            )),
      ),
    );
  }

  Widget _footer() {
    final last = _index == _questions.length - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: NkapButton(
        label: last ? 'Finish setup' : 'Next',
        icon: last ? Icons.check_rounded : Icons.arrow_forward_rounded,
        color: _current.feature.color,
        onTap: _canAdvance ? _next : null,
      ),
    );
  }
}
