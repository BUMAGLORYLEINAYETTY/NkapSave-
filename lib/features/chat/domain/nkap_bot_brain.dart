import 'package:flutter/material.dart';
import '../../../core/services/user_preferences.dart';
import 'entities/chat_message.dart';
import 'finance_facts.dart';

class BotReply {
  final String text;
  final ChatPayload? payload;
  const BotReply(this.text, {this.payload});
}

class NkapBotBrain {
  final FinanceFacts facts;
  NkapBotBrain(this.facts);

  // ── Proactive check-ins ─────────────────────────────────────
  bool get hasProactiveAlerts {
    if (facts.bills.any((b) => _daysUntil(b.due) <= 1)) return true;
    if (facts.budgets.entries.any((e) =>
        facts.spentThisMonthFor(e.key) / e.value.limit >= 0.8)) return true;
    if (facts.goals.any((g) {
      final p = g.target == 0 ? 0.0 : g.current / g.target;
      return p >= 0.9 && p < 1.0;
    })) return true;
    if (facts.njangiYourTurn) return true;
    if (facts.savingStreak > 0 && facts.savingStreak % 7 == 0) return true;
    return false;
  }

  List<BotReply> proactiveChecks() {
    final replies = <BotReply>[_buildGreeting()];

    if (facts.njangiYourTurn) {
      replies.add(BotReply(
        "🎉 It's your turn in ${facts.njangiGroup} this month — ${_fmt(facts.njangiNextPayout)} is on the way.",
        payload: NjangiStatusPayload(
          groupName: facts.njangiGroup, memberCount: facts.njangiMembers,
          nextPayout: facts.njangiNextPayout, nextTurnLabel: facts.njangiNextTurn,
          yourTurn: true,
        ),
      ));
    }

    final urgentBills = facts.bills.where((b) => _daysUntil(b.due) <= 1).toList();
    if (urgentBills.isNotEmpty) {
      final total = urgentBills.fold<double>(0, (s, b) => s + b.amount);
      replies.add(BotReply(
        urgentBills.length == 1
            ? "Heads up — your ${urgentBills.first.name} bill (${_fmt(urgentBills.first.amount)}) is due ${urgentBills.first.due.toLowerCase()}."
            : "${urgentBills.length} bills are due soon, totaling ${_fmt(total)}. Want me to remind you again later?",
        payload: BillsListPayload(urgentBills),
      ));
    }

    final warned = <String>{};
    for (final entry in facts.budgets.entries) {
      final spent = facts.spentThisMonthFor(entry.key);
      final progress = entry.value.limit == 0 ? 0.0 : spent / entry.value.limit;
      if (progress >= 0.8) {
        warned.add(entry.key);
        replies.add(_budgetSnapshot(entry.key,
            intro: progress > 1.0 ? "You're over on ${entry.key}." : "You're close to your ${entry.key} limit."));
      }
    }

    for (final g in facts.goals) {
      final p = g.target == 0 ? 0.0 : g.current / g.target;
      if (p >= 0.9 && p < 1.0) {
        replies.add(BotReply(
          "You're at ${(p * 100).toStringAsFixed(0)}% on ${g.name} — only ${_fmt(g.target - g.current)} to go!",
          payload: GoalCreatedPayload(name: g.name, emoji: g.emoji, target: g.target),
        ));
      }
    }

    if (facts.savingStreak > 0 && facts.savingStreak % 7 == 0) {
      replies.add(BotReply(
        "🔥 ${facts.savingStreak}-day savings streak — keep it going. Add to a goal today to extend it.",
      ));
    }

    if (replies.length == 1) {
      replies.add(BotReply(
        "Everything looks healthy 👌 — what would you like to do today? Try \"check balance\" or \"how can I save more?\".",
      ));
    } else {
      replies.add(BotReply("Tap any card for more, or ask me to take action."));
    }

    return replies;
  }

  BotReply _buildGreeting() {
    final h = DateTime.now().hour;
    final tod = h < 12 ? 'morning' : h < 17 ? 'afternoon' : 'evening';
    final name = facts.displayName;
    final intent = _intentLineFromProfile();
    if (intent.isEmpty) {
      return BotReply("Good $tod $name 👋 Here's your check-in:");
    }
    return BotReply("Good $tod $name 👋\n$intent\nHere's your check-in:");
  }

  /// Builds a one-line acknowledgement of the user's saved goals from
  /// onboarding (e.g. "I see you're focused on tuition — let's keep you
  /// on track"). Returns empty string when no profile answers exist.
  String _intentLineFromProfile() {
    final p = UserPreferences.instance.profile;
    if (p.isEmpty) return '';
    final savingsFor = p['savings_for'];
    final challenge = p['spending_challenge'];
    final njangiCount = p['njangi_count'];
    if (savingsFor != null && savingsFor.isNotEmpty) {
      return "I see you're saving for ${savingsFor.toLowerCase()} — let's keep you on track.";
    }
    if (challenge != null && challenge.isNotEmpty) {
      return "Watching your ${challenge.toLowerCase()} spend with you.";
    }
    if (njangiCount != null && njangiCount.isNotEmpty) {
      return "Tracking your Njangi groups — I'll flag every contribution and payout.";
    }
    return '';
  }

  int _daysUntil(String due) {
    final d = due.toLowerCase();
    if (d == 'today') return 0;
    if (d == 'tomorrow') return 1;
    final m = RegExp(r'(\d+)\s*days?').firstMatch(d);
    if (m != null) return int.parse(m.group(1)!);
    return 30;
  }

  // Parse a number that may include thousand separators or "k" suffix (5k, 5.000, 5,000)
  double? _parseAmount(String s) {
    var raw = s.trim().toLowerCase().replaceAll(' ', '');
    final hasK = raw.endsWith('k');
    if (hasK) raw = raw.substring(0, raw.length - 1);
    raw = raw.replaceAll(',', '').replaceAll('.', '');
    final n = double.tryParse(raw);
    if (n == null) return null;
    return hasK ? n * 1000 : n;
  }

  Future<List<BotReply>> respond(String input) async {
    final q = input.trim();
    if (q.isEmpty) return const [BotReply("I didn't catch that — try again?")];

    final lower = q.toLowerCase();

    // ── Send money: "send 5000 to Marie", "transfer 10k to Paul", "envoyer 5000 à Marie" ──
    final sendMatch = RegExp(
      r'(?:send|transfer|envoy(?:er|e)|envoie)\s+([\d.,]+\s*k?)\s+(?:to|à|au|a)\s+([a-zà-ÿ\-]+)',
      caseSensitive: false, unicode: true,
    ).firstMatch(q);
    if (sendMatch != null) {
      final amt = _parseAmount(sendMatch.group(1)!);
      final who = sendMatch.group(2)!.trim();
      if (amt != null && amt > 0) {
        final contact = facts.findContact(who);
        if (contact == null) {
          return [BotReply(
            "I couldn't find \"$who\" in your contacts. Try one of: ${facts.contacts.map((c) => c.name).join(", ")}.",
          )];
        }
        if (amt > facts.totalBalance) {
          return [BotReply(
            "You only have ${_fmt(facts.totalBalance)} available — not enough to send ${_fmt(amt)}. Want to send a smaller amount?",
          )];
        }
        final result = facts.sendMoney(recipient: contact.name, amount: amt);
        return [BotReply(
          "Sent ${_fmt(amt)} to ${contact.name} ✅",
          payload: TransferSentPayload(
            recipient: result.recipient, initials: contact.initials,
            amount: result.amount, color: result.color,
          ),
        )];
      }
    }

    // ── Set budget: "set food budget to 50000", "change transport budget to 30k" ──
    final setBudgetMatch = RegExp(
      r'(?:set|update|change)\s+(?:my\s+)?(\w+)\s+budget\s+(?:to|at|=|=>)\s+([\d.,]+\s*k?)',
      caseSensitive: false,
    ).firstMatch(q);
    if (setBudgetMatch != null) {
      final cat = setBudgetMatch.group(1)!.trim();
      final amt = _parseAmount(setBudgetMatch.group(2)!);
      if (amt != null && amt > 0) {
        final canon = facts.matchCategory(cat);
        if (canon == null) {
          return [BotReply(
            "I don't have a \"$cat\" budget yet. I track: ${facts.budgets.keys.join(", ")}.",
          )];
        }
        final result = facts.setBudget(category: canon, limit: amt);
        return [BotReply(
          result.oldLimit > 0
              ? "Updated your $canon budget to ${_fmt(amt)}."
              : "Created a $canon budget at ${_fmt(amt)}.",
          payload: BudgetUpdatedPayload(
            category: result.category, oldLimit: result.oldLimit,
            newLimit: result.newLimit, color: result.color,
          ),
        )];
      }
    }

    // ── Show transactions: "show recent transactions", "last 5 expenses" ──
    final txListMatch = RegExp(
      r'\b(?:show|list|view|see|recent)\s+(?:my\s+)?(?:last\s+(\d+)\s+)?(?:transactions?|expenses?|spending|payments?)\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (txListMatch != null) {
      final count = int.tryParse(txListMatch.group(1) ?? '') ?? 5;
      final list = facts.transactions.take(count).toList();
      return [BotReply(
        list.isEmpty
            ? "You don't have any transactions yet."
            : "Here are your last ${list.length} transactions:",
        payload: list.isEmpty ? null : TransactionListPayload(list),
      )];
    }

    // ── 1. Expense recording: "spent 5000 on taxi", "j'ai dépensé 5000 pour taxi" ──
    final spentMatch = RegExp(
      r'(?:spent|paid|bought|d[éeè]pens[éeè]|j.ai\s+pay[ée]|pay[ée])\s+([\d.,]+\s*k?)\s+(?:on|for|pour|en)\s+(.+)',
      caseSensitive: false,
    ).firstMatch(q);
    if (spentMatch != null) {
      final amt = _parseAmount(spentMatch.group(1)!);
      final what = spentMatch.group(2)!.trim();
      if (amt != null && amt > 0) {
        final canonical = facts.matchCategory(what) ?? what;
        final tx = facts.recordExpense(amount: amt, category: what, name: _capitalize(what));
        return [
          BotReply(
            "Got it — recorded ${_fmt(amt)} for $canonical ✅",
            payload: TransactionRecordedPayload(
              category: tx.category, name: tx.name, amount: tx.amount.abs(), color: tx.color,
            ),
          ),
          if (facts.budgets.containsKey(tx.category))
            _budgetSnapshot(tx.category, intro: "Here's where you stand on $canonical:"),
        ];
      }
    }

    // ── 2. Balance: "balance", "how much do i have", "wallet" ──
    if (RegExp(r'\b(balance|how much (?:do i|have i|i have|i got)|wallet|account|combien.*(?:argent|reste))\b', caseSensitive: false).hasMatch(lower)) {
      return [BotReply(
        "Here's your snapshot. You've got ${_fmt(facts.totalBalance)} across all wallets.",
        payload: BalanceCardPayload(
          total: facts.totalBalance, income: facts.monthlyIncome,
          expenses: facts.monthlyExpenses, saved: facts.savedThisMonth,
        ),
      )];
    }

    // ── 3. Weekly spending ──
    if (RegExp(r'\b(this week|weekly|week.s? spending|cette semaine|semaine)\b', caseSensitive: false).hasMatch(lower)) {
      final top = facts.weeklyTop;
      return [BotReply(
        "You've spent ${_fmt(facts.weeklyTotal)} this week. Your highest day was ${top.day} (${_fmt(top.amount)}).",
        payload: WeeklySummaryPayload(
          spend: facts.weeklySpend.map((e) => (e.day, e.amount)).toList(),
          total: facts.weeklyTotal,
          topDay: top.day, topAmount: top.amount,
        ),
      )];
    }

    // ── 4. Budget check: "how much left in food budget", "food budget" ──
    final budgetMatch = RegExp(r'(?:left in|remaining|how much.*?(?:left|remain)|combien.*reste)\b.*?\b(food|drink|transport|taxi|utilities|internet|shopping)\b', caseSensitive: false).firstMatch(lower)
        ?? RegExp(r'\b(food|drink|transport|taxi|utilities|internet|shopping)\b.*?\bbudget\b', caseSensitive: false).firstMatch(lower);
    if (budgetMatch != null) {
      final cat = facts.matchCategory(budgetMatch.group(1)!);
      if (cat != null) return [_budgetSnapshot(cat)];
    }

    // ── 5. Create savings goal: "save 50000 for laptop" ──
    final goalMatch = RegExp(
      r'(?:save|saving|épargner|epargner|goal\s+of)\s+([\d.,]+\s*k?)\s+(?:for|to|pour)\s+(.+)',
      caseSensitive: false,
    ).firstMatch(q);
    if (goalMatch != null) {
      final amt = _parseAmount(goalMatch.group(1)!);
      final what = goalMatch.group(2)!.trim();
      if (amt != null && amt > 0) {
        final emoji = _goalEmoji(what);
        final goal = facts.createGoal(name: _capitalize(what), target: amt, emoji: emoji);
        return [BotReply(
          "Created your goal for ${_capitalize(what)} 🎯 Aim: ${_fmt(amt)}.",
          payload: GoalCreatedPayload(name: goal.name, emoji: goal.emoji, target: goal.target),
        )];
      }
    }

    // ── 6. Njangi / tontine status ──
    if (RegExp(r'\b(njangi|tontine|group savings?)\b', caseSensitive: false).hasMatch(lower)) {
      final yourTurn = facts.njangiYourTurn;
      return [BotReply(
        yourTurn
          ? "Good news — it's your turn in ${facts.njangiGroup}! You'll receive ${_fmt(facts.njangiNextPayout)}."
          : "Your group ${facts.njangiGroup} has ${facts.njangiMembers} members. Next payout: ${_fmt(facts.njangiNextPayout)}.",
        payload: NjangiStatusPayload(
          groupName: facts.njangiGroup, memberCount: facts.njangiMembers,
          nextPayout: facts.njangiNextPayout, nextTurnLabel: facts.njangiNextTurn,
          yourTurn: yourTurn,
        ),
      )];
    }

    // ── 7. Upcoming bills ──
    if (RegExp(r'\b(bills?|due|upcoming|pay.*soon|factures?|payer)\b', caseSensitive: false).hasMatch(lower)) {
      return [BotReply(
        "You've got ${facts.bills.length} bills coming up totaling ${_fmt(facts.bills.fold<double>(0, (s, b) => s + b.amount))}.",
        payload: BillsListPayload(facts.bills),
      )];
    }

    // ── 8. Coaching: "how can i save more", "tips" ──
    if (RegExp(r"\b(how (?:can|do) i save|save more|saving tips?|comment.*[ée]conomiser|conseils?)\b", caseSensitive: false).hasMatch(lower)) {
      return [BotReply(
        "Here's a tip just for you, based on your numbers:",
        payload: _coachingTip(),
      )];
    }

    if (RegExp(r"\b(invest|investment|investir)\b", caseSensitive: false).hasMatch(lower)) {
      return [BotReply(
        "Build an emergency cushion first. With ${_fmt(facts.savedThisMonth)} saved this month and a savings rate of ${(facts.savingsRate * 100).toStringAsFixed(0)}%, "
        "aim for 3 months of expenses (~${_fmt(facts.monthlyExpenses * 3)}) in a safe locked wallet before investing.",
        payload: CoachingTipPayload(
          title: 'Save before you invest',
          body: "An emergency fund of ~3× monthly expenses protects you from needing to sell investments at a loss when life happens.",
          emoji: '🛡️',
          color: const Color(0xFFA78BFA),
        ),
      )];
    }

    // ── 9. Help / capabilities ──
    if (RegExp(r"\b(help|what can|what do you|capabilities|commands|aide|que peux)\b", caseSensitive: false).hasMatch(lower)) {
      return [BotReply(
        "I can help with a lot — here's a quick tour:",
        payload: const CapabilityListPayload(),
      )];
    }

    // ── 10. Greetings ──
    if (RegExp(r"^(hi|hello|hey|salut|bonjour|good (?:morning|afternoon|evening))\b", caseSensitive: false).hasMatch(lower)) {
      return [BotReply("Hi ${facts.displayName} 👋 — what would you like to do? Try 'check balance', 'I spent 5000 on taxi', or 'save 50000 for laptop'.")];
    }

    // ── Fallback ──
    return [BotReply(
      "I'm still learning that one. Try things like:\n"
      "• \"I spent 5,000 on taxi\"\n"
      "• \"How much is left in my food budget?\"\n"
      "• \"Save 50,000 for a laptop\"\n"
      "• \"What bills are due?\"",
    )];
  }

  BotReply _budgetSnapshot(String category, {String? intro}) {
    final b = facts.budgets[category]!;
    final spent = facts.spentThisMonthFor(category);
    final payload = BudgetStatusPayload(
      category: category, spent: spent, limit: b.limit, color: b.color,
    );
    final remaining = (b.limit - spent).clamp(0, double.infinity);
    String text;
    if (payload.over) {
      text = "${intro ?? ''} You're ${_fmt(spent - b.limit)} over your $category budget. Consider easing up for the rest of the month.";
    } else if (payload.progress > 0.8) {
      text = "${intro ?? ''} You've used ${(payload.progress * 100).toStringAsFixed(0)}% of $category. Only ${_fmt(remaining.toDouble())} left.";
    } else {
      text = "${intro ?? ''} You've got ${_fmt(remaining.toDouble())} left in $category this month.";
    }
    return BotReply(text.trim(), payload: payload);
  }

  CoachingTipPayload _coachingTip() {
    final overspend = facts.budgets.entries
        .map((e) => (cat: e.key, used: facts.spentThisMonthFor(e.key) / e.value.limit, color: e.value.color))
        .where((r) => r.used > 0.8)
        .toList();
    if (overspend.isNotEmpty) {
      final worst = overspend.reduce((a, b) => a.used > b.used ? a : b);
      return CoachingTipPayload(
        title: 'Trim your ${worst.cat} spend',
        body: "You're at ${(worst.used * 100).toStringAsFixed(0)}% of your ${worst.cat} budget. "
            "Capping it 10% lower would free ~${_fmt(facts.budgets[worst.cat]!.limit * 0.1)}/mo toward your goals.",
        emoji: '✂️', color: worst.color,
      );
    }
    return const CoachingTipPayload(
      title: 'Automate your saving',
      body: "Turn on auto-save at 15% of every MTN transfer. You won't feel it day-to-day, but at your current income that's ~52,500 FCFA/month toward your goals.",
      emoji: '⚡', color: Color(0xFFFFB627),
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  String _goalEmoji(String name) {
    final n = name.toLowerCase();
    if (n.contains('laptop') || n.contains('computer') || n.contains('pc')) return '💻';
    if (n.contains('phone') || n.contains('téléphone')) return '📱';
    if (n.contains('trip') || n.contains('travel') || n.contains('vacation') || n.contains('voyage')) return '✈️';
    if (n.contains('school') || n.contains('tuition') || n.contains('école') || n.contains('université')) return '🎓';
    if (n.contains('car') || n.contains('voiture')) return '🚗';
    if (n.contains('house') || n.contains('home') || n.contains('maison')) return '🏠';
    if (n.contains('wedding') || n.contains('mariage')) return '💍';
    if (n.contains('emergency') || n.contains('urgence')) return '🛡️';
    return '🎯';
  }
}

String _fmt(double n) =>
    '${n < 0 ? "-" : ""}${n.abs().toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} FCFA';
