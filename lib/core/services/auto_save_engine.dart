import '../preferences/auto_save_config.dart';

/// What kind of source event is asking the engine to consider firing.
enum AutoSaveEventKind { income, transfer, expense, scheduled }

class AutoSaveDecision {
  final bool save;
  final double amount;
  final String? destinationGoalName;
  final String reason;

  const AutoSaveDecision.skip(this.reason)
      : save = false, amount = 0, destinationGoalName = null;

  const AutoSaveDecision.fire({
    required this.amount,
    required this.destinationGoalName,
    required this.reason,
  }) : save = true;
}

/// Pure-logic engine: given current config + recent events + the new event,
/// decide whether to fire an auto-save and for how much.
///
/// Stateless on purpose — the caller (FinanceFacts) owns the ledger and
/// passes the relevant history in.
class AutoSaveEngine {
  /// Returns a decision describing whether this event should trigger a save.
  ///
  /// - [config]: current user rule.
  /// - [kind]: what just happened.
  /// - [availableBalance]: liquid balance the save would be drawn from.
  /// - [recentEvents]: timestamps of prior auto-save events (any successful
  ///   fires) used to enforce frequency caps. Most recent first.
  /// - [now]: clock, injectable for tests.
  AutoSaveDecision evaluate({
    required AutoSaveConfig config,
    required AutoSaveEventKind kind,
    required double availableBalance,
    required List<DateTime> recentEvents,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();

    if (!config.enabled) return const AutoSaveDecision.skip('Auto-save is off');
    if (config.paused)  return const AutoSaveDecision.skip('Auto-save is paused');
    if (config.amount <= 0) return const AutoSaveDecision.skip('Amount is zero');

    if (!_kindMatchesTrigger(kind, config.trigger)) {
      return AutoSaveDecision.skip('Event does not match trigger (${config.trigger.id})');
    }

    if (config.skipNext) {
      return const AutoSaveDecision.skip('Skipping this trigger (skip-next)');
    }

    // Frequency: minimum gap since last successful save.
    if (recentEvents.isNotEmpty) {
      final lastFire = recentEvents.first;
      final gap = clock.difference(lastFire);
      if (gap < Duration(minutes: config.minGapMinutes)) {
        final mins = config.minGapMinutes - gap.inMinutes;
        return AutoSaveDecision.skip('Within cooldown — next attempt in ~${mins}m');
      }
    }

    // Daily cap.
    final today = DateTime(clock.year, clock.month, clock.day);
    final firesToday = recentEvents.where((e) {
      final d = DateTime(e.year, e.month, e.day);
      return d.isAtSameMomentAs(today);
    }).length;
    if (firesToday >= config.dailyCap) {
      return AutoSaveDecision.skip('Daily cap reached (${config.dailyCap}/day)');
    }

    // Funds check.
    if (availableBalance < config.amount) {
      switch (config.shortfallPolicy) {
        case AutoSaveShortfallPolicy.skip:
          return const AutoSaveDecision.skip('Balance too low; skipped');
        case AutoSaveShortfallPolicy.retry:
          return const AutoSaveDecision.skip('Balance too low; will retry next event');
        case AutoSaveShortfallPolicy.partial:
          if (availableBalance <= 0) {
            return const AutoSaveDecision.skip('No balance available');
          }
          return AutoSaveDecision.fire(
            amount: availableBalance,
            destinationGoalName: config.destinationGoalName,
            reason: 'Partial save (balance below rule)',
          );
      }
    }

    return AutoSaveDecision.fire(
      amount: config.amount,
      destinationGoalName: config.destinationGoalName,
      reason: 'Triggered by ${config.trigger.label.toLowerCase()}',
    );
  }

  bool _kindMatchesTrigger(AutoSaveEventKind kind, AutoSaveTrigger trigger) {
    switch (trigger) {
      case AutoSaveTrigger.income:    return kind == AutoSaveEventKind.income;
      case AutoSaveTrigger.transfer:  return kind == AutoSaveEventKind.transfer;
      case AutoSaveTrigger.expense:   return kind == AutoSaveEventKind.expense;
      case AutoSaveTrigger.daily:     return kind == AutoSaveEventKind.scheduled;
    }
  }
}
