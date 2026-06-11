import 'package:flutter/foundation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/finance_facts.dart';
import '../../domain/nkap_bot_brain.dart';

class ChatController extends ChangeNotifier {
  ChatController._() : _brain = NkapBotBrain(FinanceFacts.instance);
  static final ChatController instance = ChatController._();

  final NkapBotBrain _brain;
  final List<ChatMessage> _messages = [];
  bool _thinking = false;
  bool _greeted = false;
  int _counter = 0;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isThinking => _thinking;
  bool get isEmpty => _messages.isEmpty;
  bool get hasGreeted => _greeted;
  bool get hasPendingAlerts => !_greeted && _brain.hasProactiveAlerts;

  String _newId() => '${DateTime.now().millisecondsSinceEpoch}-${_counter++}';

  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _thinking) return;

    _messages.add(ChatMessage(id: _newId(), role: ChatRole.user, text: trimmed));
    _thinking = true;
    notifyListeners();

    // Small delay so the typing indicator is visible and feels natural.
    await Future.delayed(const Duration(milliseconds: 550));

    final replies = await _brain.respond(trimmed);
    for (var i = 0; i < replies.length; i++) {
      if (i > 0) await Future.delayed(const Duration(milliseconds: 350));
      final r = replies[i];
      _messages.add(ChatMessage(
        id: _newId(), role: ChatRole.bot,
        text: r.text, payload: r.payload,
      ));
      _thinking = i < replies.length - 1;
      notifyListeners();
    }

    _thinking = false;
    notifyListeners();
  }

  Future<void> runProactiveCheck({bool force = false}) async {
    if (_thinking) return;
    if (_greeted && !force) return;
    _greeted = true;

    _thinking = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 400));

    final replies = _brain.proactiveChecks();
    for (var i = 0; i < replies.length; i++) {
      if (i > 0) await Future.delayed(const Duration(milliseconds: 380));
      final r = replies[i];
      _messages.add(ChatMessage(
        id: _newId(), role: ChatRole.bot,
        text: r.text, payload: r.payload,
      ));
      _thinking = i < replies.length - 1;
      notifyListeners();
    }
    _thinking = false;
    notifyListeners();
  }

  void clear() {
    _messages.clear();
    _thinking = false;
    _greeted = false;
    notifyListeners();
  }
}
