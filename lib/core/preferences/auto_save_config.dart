import 'dart:convert';

/// Triggers that can fire the auto-save engine.
enum AutoSaveTrigger {
  income('income', 'After every income', 'Each time money lands in your wallet'),
  transfer('transfer', 'After every transfer', 'Each time you send money out'),
  expense('expense', 'After every expense', 'Each time you log a purchase'),
  daily('daily', 'Once a day', 'Saves automatically each morning if balance allows');

  final String id, label, description;
  const AutoSaveTrigger(this.id, this.label, this.description);

  static AutoSaveTrigger fromId(String id) =>
      AutoSaveTrigger.values.firstWhere((t) => t.id == id, orElse: () => income);
}

/// Behaviour when the source balance is too low to satisfy the rule.
enum AutoSaveShortfallPolicy {
  skip('skip', 'Skip', 'Skip this save entirely; try again on the next trigger.'),
  partial('partial', 'Save what fits', 'Save whatever\'s available, even if less than the rule.'),
  retry('retry', 'Retry tomorrow', 'Queue the save and retry on the next day with funds.');

  final String id, label, description;
  const AutoSaveShortfallPolicy(this.id, this.label, this.description);

  static AutoSaveShortfallPolicy fromId(String id) =>
      AutoSaveShortfallPolicy.values.firstWhere((p) => p.id == id, orElse: () => skip);
}

class AutoSaveConfig {
  /// Master switch. False = engine never fires regardless of other fields.
  final bool enabled;
  final bool paused;
  /// True = skip the very next trigger then resume normally.
  final bool skipNext;
  /// Fixed FCFA amount to move per matching trigger.
  final double amount;
  final AutoSaveTrigger trigger;
  /// Destination goal name. When null, the save goes to a generic "Locked
  /// Savings" bucket (tracked on FinanceFacts.savedThisMonth).
  final String? destinationGoalName;
  /// Minimum gap between fires in minutes. Stops salary day draining the wallet.
  final int minGapMinutes;
  /// Hard ceiling per calendar day, regardless of trigger frequency.
  final int dailyCap;
  final AutoSaveShortfallPolicy shortfallPolicy;

  const AutoSaveConfig({
    this.enabled = false,
    this.paused = false,
    this.skipNext = false,
    this.amount = 1500,
    this.trigger = AutoSaveTrigger.income,
    this.destinationGoalName,
    this.minGapMinutes = 60,
    this.dailyCap = 3,
    this.shortfallPolicy = AutoSaveShortfallPolicy.skip,
  });

  AutoSaveConfig copyWith({
    bool? enabled,
    bool? paused,
    bool? skipNext,
    double? amount,
    AutoSaveTrigger? trigger,
    Object? destinationGoalName = _unset,
    int? minGapMinutes,
    int? dailyCap,
    AutoSaveShortfallPolicy? shortfallPolicy,
  }) {
    return AutoSaveConfig(
      enabled: enabled ?? this.enabled,
      paused: paused ?? this.paused,
      skipNext: skipNext ?? this.skipNext,
      amount: amount ?? this.amount,
      trigger: trigger ?? this.trigger,
      destinationGoalName: identical(destinationGoalName, _unset)
          ? this.destinationGoalName
          : destinationGoalName as String?,
      minGapMinutes: minGapMinutes ?? this.minGapMinutes,
      dailyCap: dailyCap ?? this.dailyCap,
      shortfallPolicy: shortfallPolicy ?? this.shortfallPolicy,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'paused': paused,
    'skipNext': skipNext,
    'amount': amount,
    'trigger': trigger.id,
    'destinationGoalName': destinationGoalName,
    'minGapMinutes': minGapMinutes,
    'dailyCap': dailyCap,
    'shortfallPolicy': shortfallPolicy.id,
  };

  static AutoSaveConfig fromJson(Map<String, dynamic> j) => AutoSaveConfig(
    enabled: j['enabled'] as bool? ?? false,
    paused: j['paused'] as bool? ?? false,
    skipNext: j['skipNext'] as bool? ?? false,
    amount: (j['amount'] as num?)?.toDouble() ?? 1500,
    trigger: AutoSaveTrigger.fromId(j['trigger']?.toString() ?? 'income'),
    destinationGoalName: j['destinationGoalName'] as String?,
    minGapMinutes: (j['minGapMinutes'] as num?)?.toInt() ?? 60,
    dailyCap: (j['dailyCap'] as num?)?.toInt() ?? 3,
    shortfallPolicy: AutoSaveShortfallPolicy.fromId(j['shortfallPolicy']?.toString() ?? 'skip'),
  );

  String encode() => json.encode(toJson());
  static AutoSaveConfig decode(String s) => fromJson(json.decode(s) as Map<String, dynamic>);
}

const Object _unset = Object();
