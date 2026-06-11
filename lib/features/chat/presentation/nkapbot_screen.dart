import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/preferences/app_feature.dart';
import '../../../core/services/user_preferences.dart';
import '../domain/nkapbot_models.dart';
import 'nkapbot_provider.dart';
import 'widgets/suggestion_chips.dart';
import 'widgets/response_cards/health_score_card.dart';
import 'widgets/response_cards/spending_breakdown_card.dart';
import 'widgets/response_cards/goal_projection_card.dart';
import 'widgets/response_cards/education_card.dart';
import 'widgets/response_cards/monthly_comparison_card.dart';
import 'widgets/response_cards/pattern_alert_card.dart';

class NkapBotScreen extends ConsumerStatefulWidget {
  const NkapBotScreen({super.key});
  @override
  ConsumerState<NkapBotScreen> createState() => _NkapBotScreenState();
}

class _NkapBotScreenState extends ConsumerState<NkapBotScreen> {
  final _inputCtrl  = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll     = ScrollController();
  bool _canSend = false;

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(() {
      final empty = _inputCtrl.text.trim().isEmpty;
      if (empty == _canSend) setState(() => _canSend = !empty);
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<String> get _enabledFeatures =>
      UserPreferences.instance.enabledFeatures
          .map((f) => f.id).toList();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  void _send(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    HapticFeedback.lightImpact();
    _inputCtrl.clear();
    ref.read(nkapBotControllerProvider.notifier).send(
      message: trimmed,
      enabledFeatures: _enabledFeatures,
    );
    _scrollToBottom();
  }

  void _confirmClear() {
    final messagesEmpty =
        ref.read(nkapBotControllerProvider).messages.isEmpty;
    if (messagesEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface2,
        title: Text('Clear conversation?',
            style: AppTextStyles.h3.copyWith(color: AppColors.text1)),
        content: Text(
          'This removes all messages with NkapBot. Your data is unaffected.',
          style: AppTextStyles.body.copyWith(color: AppColors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: AppTextStyles.body.copyWith(color: AppColors.text2)),
          ),
          TextButton(
            onPressed: () {
              ref.read(nkapBotControllerProvider.notifier).clear();
              Navigator.pop(ctx);
            },
            child: Text('Clear',
                style: AppTextStyles.h4.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nkapBotControllerProvider);
    ref.listen<NkapBotState>(nkapBotControllerProvider, (_, __) {
      _scrollToBottom();
    });

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface1,
        elevation: 0,
        leading: IconButton(
          icon:  Icon(Icons.arrow_back_rounded, color: AppColors.text1),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: AppColors.heroBrandGradient),
              border: Border.all(color: AppColors.primaryMid, width: 2),
              boxShadow: [BoxShadow(
                  color: AppColors.primary.withOpacity(0.4), blurRadius: 10)],
            ),
            child: const Icon(Icons.smart_toy_rounded,
                color: AppColors.heroFg, size: 20),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, children: [
            Text('NkapBot', style: AppTextStyles.h2.copyWith(color: AppColors.primary)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: AppColors.primary),
              ),
              const SizedBox(width: 5),
              Text(state.isLoading ? 'Thinking…' : 'Online Assistant',
                  style: AppTextStyles.caption.copyWith(color: AppColors.text2)),
            ]),
          ]),
        ]),
        actions: [
          if (state.messages.isNotEmpty)
            IconButton(
              icon:  Icon(Icons.delete_sweep_rounded,
                  color: AppColors.primary, size: 20),
              tooltip: 'Clear',
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: state.messages.isEmpty
                ? _emptyState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: state.messages.length +
                        (state.isLoading ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= state.messages.length) {
                        return const _TypingIndicator();
                      }
                      return _MessageBubble(message: state.messages[i],
                          onRelatedTap: _send);
                    },
                  ),
          ),
          _Input(
            controller: _inputCtrl,
            focusNode: _inputFocus,
            canSend: _canSend && !state.isLoading,
            onSubmit: () => _send(_inputCtrl.text),
          ),
        ]),
      ),
    );
  }

  Widget _emptyState() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
    children: [
      Center(child: Container(
        width: 84, height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [
                AppColors.primary.withOpacity(0.25),
                AppColors.primary.withOpacity(0.05),
              ]),
          border: Border.all(color: AppColors.primaryMid, width: 1.5),
        ),
        child: const Icon(Icons.smart_toy_rounded,
            color: AppColors.primary, size: 36),
      )),
      const SizedBox(height: 18),
      Center(child: Text("Hi, I'm NkapBot", style: AppTextStyles.h2.copyWith(color: AppColors.text1))),
      const SizedBox(height: 6),
      Center(child: Text(
        'Ask anything about your money — your numbers, not generic tips.\n'
        "I advise; you act.",
        textAlign: TextAlign.center,
        style: AppTextStyles.body.copyWith(color: AppColors.text2),
      )),
      const SizedBox(height: 22),
      Text('TRY THESE', style: AppTextStyles.label.copyWith(color: AppColors.text3, letterSpacing: 1.2)),
      const SizedBox(height: 10),
      SuggestionChips(onTap: _send),
    ],
  );
}

class _MessageBubble extends StatelessWidget {
  final NkapBotMessage message;
  final void Function(String) onRelatedTap;
  const _MessageBubble({required this.message, required this.onRelatedTap});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == NkapBotRole.user;
    return Padding(
      padding: EdgeInsets.fromLTRB(isUser ? 60 : 4, 6, isUser ? 4 : 60, 6),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) _botAvatar(),
              if (!isUser) const SizedBox(width: 8),
              Flexible(child: _textBubble(isUser)),
            ],
          ),
          if (!isUser && message.cardType != NkapBotCardType.none) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: _cardFor(message),
            ),
          ],
        ],
      ),
    );
  }

  Widget _botAvatar() => Container(
    width: 28, height: 28,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: AppColors.heroBrandGradient),
      border: Border.all(color: AppColors.primaryMid),
      boxShadow: [BoxShadow(
          color: AppColors.primary.withOpacity(0.3), blurRadius: 8)],
    ),
    child: const Icon(Icons.smart_toy_rounded,
        color: AppColors.heroFg, size: 14),
  );

  Widget _textBubble(bool isUser) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: isUser ? AppColors.primary : AppColors.surface2,
      borderRadius: BorderRadius.only(
        topLeft:     const Radius.circular(16),
        topRight:    const Radius.circular(16),
        bottomLeft:  Radius.circular(isUser ? 16 : 4),
        bottomRight: Radius.circular(isUser ? 4 : 16),
      ),
      border: isUser ? null : Border.all(color: AppColors.border1),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message.text,
            style: AppTextStyles.body.copyWith(
                color: isUser ? AppColors.heroFg : AppColors.text1)),
        const SizedBox(height: 4),
        Text(DateFormat('h:mm a').format(message.time),
            style: AppTextStyles.caption.copyWith(
                color: isUser ? AppColors.heroFgDim : AppColors.text3)),
      ],
    ),
  );

  Widget _cardFor(NkapBotMessage m) {
    switch (m.cardType) {
      case NkapBotCardType.healthScore:
        return HealthScoreCard(data: m.cardData);
      case NkapBotCardType.spendingBreakdown:
        return SpendingBreakdownCard(data: m.cardData);
      case NkapBotCardType.goalProjection:
        return GoalProjectionCard(data: m.cardData);
      case NkapBotCardType.education:
        return EducationCard(data: m.cardData, onRelatedTap: onRelatedTap);
      case NkapBotCardType.monthlyComparison:
        return MonthlyComparisonCard(data: m.cardData);
      case NkapBotCardType.patternAlert:
        return PatternAlertCard(data: m.cardData);
      case NkapBotCardType.none:
        return const SizedBox.shrink();
    }
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1100))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  double _dot(double t, int i) {
    final shifted = (t - i * 0.18) % 1.0;
    return (1.0 - (shifted - 0.3).abs() * 2.5).clamp(0.25, 1.0);
  }
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 60, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: AppColors.heroBrandGradient),
            border: Border.all(color: AppColors.primaryMid),
          ),
          child: const Icon(Icons.smart_toy_rounded,
              color: AppColors.heroFg, size: 14),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: const BorderRadius.only(
              topLeft:     Radius.circular(4),
              topRight:    Radius.circular(16),
              bottomLeft:  Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            border: Border.all(color: AppColors.border1),
          ),
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Row(mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) => Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 5),
                  child: Opacity(
                    opacity: _dot(_ctrl.value, i),
                    child: Container(width: 7, height: 7,
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary)),
                  ),
                ))),
          ),
        ),
      ]),
    );
  }
}

class _Input extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool canSend;
  final VoidCallback onSubmit;
  const _Input({
    required this.controller, required this.focusNode,
    required this.canSend, required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration:  BoxDecoration(
        color: AppColors.surface1,
        border: Border(top: BorderSide(color: AppColors.border1)),
      ),
      child: Row(children: [
        Expanded(child: AnimatedBuilder(
          animation: focusNode,
          builder: (_, child) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                  color: focusNode.hasFocus ? AppColors.primary : AppColors.border2),
            ),
            child: child,
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            style: AppTextStyles.body.copyWith(color: AppColors.text1, fontSize: 13.5, height: 1),
            cursorColor: AppColors.primary,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Ask NkapBot about your money…',
              hintStyle: AppTextStyles.body.copyWith(color: AppColors.text3, fontSize: 13.5, height: 1),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            textInputAction: TextInputAction.send,
            onSubmitted: (_) { if (canSend) onSubmit(); },
          ),
        )),
        const SizedBox(width: 8),
        AnimatedOpacity(
          opacity: canSend ? 1.0 : 0.4,
          duration: const Duration(milliseconds: 180),
          child: GestureDetector(
            onTap: canSend ? onSubmit : null,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: AppColors.heroBrandGradient),
                boxShadow: canSend
                    ? [BoxShadow(
                        color: AppColors.primary.withOpacity(0.4),
                        blurRadius: 10)]
                    : null,
              ),
              child: const Icon(Icons.send_rounded,
                  color: AppColors.heroFg, size: 20),
            ),
          ),
        ),
      ]),
    );
  }
}

// Silence unused-import analyzer hint if AppFeature is only consumed
// transitively via the suggestion chips. Kept explicit for future use.
// ignore: unused_element
void _appFeatureKeepalive(AppFeature _) {}
