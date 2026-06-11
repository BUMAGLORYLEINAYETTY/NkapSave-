// Domain models for the NkapBot full-screen chat.
// Kept separate from the legacy rule-based chat domain so the two can
// coexist while we migrate. These models match the /nkapbot/chat
// response shape one-for-one.

enum NkapBotCardType {
  none,
  healthScore,
  spendingBreakdown,
  goalProjection,
  education,
  monthlyComparison,
  patternAlert,
}

NkapBotCardType _cardTypeFromString(String? raw) {
  switch (raw) {
    case 'health_score':        return NkapBotCardType.healthScore;
    case 'spending_breakdown':  return NkapBotCardType.spendingBreakdown;
    case 'goal_projection':     return NkapBotCardType.goalProjection;
    case 'education':           return NkapBotCardType.education;
    case 'monthly_comparison':  return NkapBotCardType.monthlyComparison;
    case 'pattern_alert':       return NkapBotCardType.patternAlert;
    default:                    return NkapBotCardType.none;
  }
}

enum NkapBotRole { user, assistant }

/// A single turn in the chat. Bot turns carry an optional rich card.
class NkapBotMessage {
  final NkapBotRole role;
  final String text;
  final NkapBotCardType cardType;
  final Map<String, dynamic> cardData;
  final String category;
  final DateTime time;

  const NkapBotMessage({
    required this.role,
    required this.text,
    this.cardType = NkapBotCardType.none,
    this.cardData = const {},
    this.category = '',
    required this.time,
  });

  Map<String, String> toApiTurn() => {
    'role': role == NkapBotRole.user ? 'user' : 'assistant',
    'content': text,
  };
}

/// Decoded response from POST /nkapbot/chat.
class NkapBotResponse {
  final String message;
  final String category;
  final NkapBotCardType cardType;
  final Map<String, dynamic> cardData;

  const NkapBotResponse({
    required this.message,
    required this.category,
    required this.cardType,
    required this.cardData,
  });

  factory NkapBotResponse.fromJson(Map<String, dynamic> j) => NkapBotResponse(
    message:  (j['message'] ?? '').toString(),
    category: (j['category'] ?? 'health').toString(),
    cardType: _cardTypeFromString(j['card_type'] as String?),
    cardData: (j['card_data'] is Map)
        ? Map<String, dynamic>.from(j['card_data'] as Map)
        : <String, dynamic>{},
  );

  factory NkapBotResponse.fallback(String text) => NkapBotResponse(
    message: text,
    category: 'health',
    cardType: NkapBotCardType.none,
    cardData: const {},
  );
}
