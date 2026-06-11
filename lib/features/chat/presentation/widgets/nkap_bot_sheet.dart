import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/preferences/app_feature.dart';
import '../../../../core/services/user_preferences.dart';
import '../providers/chat_controller.dart';
import 'chat_bubble.dart';
import 'chat_typing_indicator.dart';

Future<void> showNkapBotSheet(BuildContext context) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.55),
    useSafeArea: true,
    builder: (_) => const NkapBotSheet(),
  );
}

class _Suggestion {
  final String emoji, label;
  final AppFeature? requires;
  const _Suggestion(this.emoji, this.label, {this.requires});
}

class NkapBotSheet extends StatefulWidget {
  const NkapBotSheet({super.key});
  @override
  State<NkapBotSheet> createState() => _NkapBotSheetState();
}

class _NkapBotSheetState extends State<NkapBotSheet> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  final _controller = ChatController.instance;

  static const _allSuggestions = <_Suggestion>[
    _Suggestion('💰', 'Check my balance'),
    _Suggestion('📊', "This week's spending", requires: AppFeature.expenses),
    _Suggestion('💸', 'I spent 5,000 on taxi', requires: AppFeature.expenses),
    _Suggestion('📤', 'Send 5,000 to Marie'),
    _Suggestion('⚙️', 'Set transport budget to 30,000', requires: AppFeature.expenses),
    _Suggestion('🎯', 'Save 50,000 for a laptop', requires: AppFeature.savings),
    _Suggestion('📋', 'Show last 5 transactions', requires: AppFeature.expenses),
    _Suggestion('📅', "What bills are due?"),
    _Suggestion('👥', 'Njangi status', requires: AppFeature.njangi),
    _Suggestion('🧠', 'How can I save more?'),
  ];

  List<_Suggestion> get _suggestions {
    final enabled = UserPreferences.instance.enabledFeatures;
    return _allSuggestions
        .where((s) => s.requires == null || enabled.contains(s.requires!))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_controller.isEmpty && !_controller.hasGreeted) {
        _controller.runProactiveCheck();
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  void _submit([String? value]) {
    final text = (value ?? _input.text).trim();
    if (text.isEmpty) return;
    HapticFeedback.lightImpact();
    _input.clear();
    _controller.send(text);
  }

  void _sendSuggestion(_Suggestion s) {
    HapticFeedback.selectionClick();
    _controller.send(s.label);
  }

  void _confirmClear() {
    if (_controller.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface2,
        title: Text('Clear conversation?',
            style: AppTextStyles.h3.copyWith(color: AppColors.text1)),
        content: Text('This will delete all messages with NkapBot.',
            style: AppTextStyles.body.copyWith(color: AppColors.text2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: AppTextStyles.body.copyWith(color: AppColors.text2)),
          ),
          TextButton(
            onPressed: () { _controller.clear(); Navigator.pop(ctx); },
            child: Text('Clear', style: AppTextStyles.h4.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, dragCtrl) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration:  BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(children: [
            _handle(),
            _header(),
            if (_controller.isEmpty) _suggestionsRow(),
            Expanded(child: _body(dragCtrl)),
            _inputBar(),
          ]),
        ),
      ),
    );
  }

  Widget _handle() => Container(
    margin: const EdgeInsets.only(top: 10, bottom: 8),
    width: 40, height: 4,
    decoration: BoxDecoration(color: AppColors.border3, borderRadius: BorderRadius.circular(99)),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 6, 6, 14),
    child: Row(children: [
      Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: AppColors.heroBrandGradient),
          border: Border.all(color: AppColors.primaryMid),
          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 14)],
        ),
        child: const Icon(Icons.smart_toy_rounded, color: AppColors.heroFg, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text('NkapBot', style: AppTextStyles.h2.copyWith(color: AppColors.primary, fontSize: 16)),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: AppColors.primaryDim, borderRadius: BorderRadius.circular(6)),
            child: Text('AI', style: AppTextStyles.chip.copyWith(color: AppColors.primary)),
          ),
        ]),
        const SizedBox(height: 2),
        Row(children: [
          Container(width: 8, height: 8,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.primary,
                  boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.6), blurRadius: 4)])),
          const SizedBox(width: 6),
          Text(_controller.isThinking ? 'Thinking…' : 'Online · Ready to help',
              style: AppTextStyles.caption.copyWith(color: AppColors.text2)),
        ]),
      ])),
      if (!_controller.isEmpty)
        IconButton(
          icon:  Icon(Icons.delete_sweep_rounded, color: AppColors.primary, size: 20),
          tooltip: 'Clear conversation',
          onPressed: _confirmClear,
        ),
      IconButton(
        icon:  Icon(Icons.close_rounded, color: AppColors.text2, size: 22),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ]),
  );

  Widget _suggestionsRow() => SizedBox(
    height: 36,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _suggestions.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) {
        final s = _suggestions[i];
        return InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => _sendSuggestion(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.surface4,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(s.emoji, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(s.label,
                  style: AppTextStyles.h4.copyWith(color: AppColors.text2)),
            ]),
          ),
        );
      },
    ),
  );

  Widget _body(ScrollController dragCtrl) {
    if (_controller.isEmpty) return _emptyState(dragCtrl);
    return _messagesList();
  }

  Widget _messagesList() {
    final messages = _controller.messages;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      itemCount: messages.length + (_controller.isThinking ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= messages.length) return const ChatTypingIndicator();
        return _AnimatedMessage(
          key: ValueKey(messages[i].id),
          child: ChatBubble(message: messages[i]),
        );
      },
    );
  }

  Widget _emptyState(ScrollController scrollCtrl) => ListView(
    controller: scrollCtrl,
    padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
    children: [
      Center(child: Container(
        width: 88, height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.primary.withOpacity(0.25), AppColors.primary.withOpacity(0.05)]),
          border: Border.all(color: AppColors.primaryMid, width: 1.5),
        ),
        child: const Icon(Icons.smart_toy_rounded, color: AppColors.primary, size: 36),
      )),
      const SizedBox(height: 18),
      Center(child: Text('Hi 👋',
          style: AppTextStyles.h2.copyWith(color: AppColors.text1, fontSize: 20))),
      const SizedBox(height: 6),
      Center(child: Text("I'm NkapBot. Ask me anything about\nyour money — or try a suggestion above.",
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMuted.copyWith(color: AppColors.text2, fontSize: 12.5, height: 1.5))),
      const SizedBox(height: 22),
      _capabilityRow(Icons.query_stats_rounded, 'Insights',
          'Spending trends, category breakdowns, savings tips'),
      const SizedBox(height: 10),
      _capabilityRow(Icons.flash_on_rounded, 'Quick actions',
          'Send money, pay bills, check Njangi without leaving any screen'),
      const SizedBox(height: 10),
      _capabilityRow(Icons.shield_moon_rounded, 'Private',
          'On-device summaries — your transactions stay in your wallet'),
    ],
  );

  Widget _capabilityRow(IconData icon, String title, String body) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border1),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: AppColors.primaryDim, borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppColors.primaryMid)),
        child: Icon(icon, color: AppColors.primary, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: AppTextStyles.h4.copyWith(color: AppColors.text1)),
        const SizedBox(height: 3),
        Text(body, style: AppTextStyles.bodyMuted.copyWith(color: AppColors.text2, fontSize: 11.5, height: 1.4)),
      ])),
    ]),
  );

  Widget _inputBar() {
    final canSend = _input.text.trim().isNotEmpty && !_controller.isThinking;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration:  BoxDecoration(
        color: AppColors.surface1,
        border: Border(top: BorderSide(color: AppColors.border1)),
      ),
      child: SafeArea(
        top: false,
        child: Row(children: [
          IconButton(
            icon:  Icon(Icons.mic_none_rounded, color: AppColors.text2, size: 22),
            onPressed: () { HapticFeedback.selectionClick();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Voice input coming soon', style: AppTextStyles.body.copyWith(color: AppColors.text1)),
                backgroundColor: AppColors.surface3, behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 2),
              ));
            },
          ),
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(99),
              border: Border.all(color: AppColors.border2),
            ),
            child: TextField(
              controller: _input,
              focusNode: _inputFocus,
              style: AppTextStyles.body.copyWith(color: AppColors.text1, fontSize: 13.5, height: 1),
              cursorColor: AppColors.primary,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Ask NkapBot anything…',
                hintStyle: AppTextStyles.body.copyWith(color: AppColors.text3, fontSize: 13.5, height: 1),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: _submit,
              onChanged: (_) => setState(() {}),
            ),
          )),
          const SizedBox(width: 8),
          AnimatedOpacity(
            opacity: canSend ? 1.0 : 0.4,
            duration: const Duration(milliseconds: 180),
            child: GestureDetector(
              onTap: canSend ? () => _submit() : null,
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: AppColors.heroBrandGradient),
                  boxShadow: canSend
                      ? [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 10)]
                      : null,
                ),
                child: const Icon(Icons.send_rounded, color: AppColors.heroFg, size: 20),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _AnimatedMessage extends StatefulWidget {
  final Widget child;
  const _AnimatedMessage({super.key, required this.child});
  @override
  State<_AnimatedMessage> createState() => _AnimatedMessageState();
}

class _AnimatedMessageState extends State<_AnimatedMessage> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(_fade);
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: SlideTransition(position: _slide, child: widget.child),
  );
}
