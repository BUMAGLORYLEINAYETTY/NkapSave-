import 'package:flutter/material.dart';

enum ChatRole { user, bot }

class ChatMessage {
  final String id;
  final ChatRole role;
  final String text;
  final DateTime time;
  final ChatPayload? payload;

  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    DateTime? time,
    this.payload,
  }) : time = time ?? DateTime.now();
}

sealed class ChatPayload {
  const ChatPayload();
}

class BalanceCardPayload extends ChatPayload {
  final double total, income, expenses, saved;
  const BalanceCardPayload({
    required this.total, required this.income,
    required this.expenses, required this.saved,
  });
}

class TransactionRecordedPayload extends ChatPayload {
  final String category, name;
  final double amount;
  final Color color;
  const TransactionRecordedPayload({
    required this.category, required this.name,
    required this.amount, required this.color,
  });
}

class WeeklySummaryPayload extends ChatPayload {
  final List<(String day, double amount)> spend;
  final double total;
  final String topDay;
  final double topAmount;
  const WeeklySummaryPayload({
    required this.spend, required this.total,
    required this.topDay, required this.topAmount,
  });
}

class GoalCreatedPayload extends ChatPayload {
  final String name, emoji;
  final double target;
  const GoalCreatedPayload({
    required this.name, required this.emoji, required this.target,
  });
}

class BudgetStatusPayload extends ChatPayload {
  final String category;
  final double spent, limit;
  final Color color;
  const BudgetStatusPayload({
    required this.category, required this.spent,
    required this.limit, required this.color,
  });
  double get remaining => (limit - spent).clamp(0, double.infinity);
  double get progress => limit == 0 ? 0 : (spent / limit).clamp(0.0, 1.0);
  bool get over => spent > limit;
}

class NjangiStatusPayload extends ChatPayload {
  final String groupName;
  final int memberCount;
  final double nextPayout;
  final String nextTurnLabel;
  final bool yourTurn;
  const NjangiStatusPayload({
    required this.groupName, required this.memberCount,
    required this.nextPayout, required this.nextTurnLabel,
    required this.yourTurn,
  });
}

class BillsListPayload extends ChatPayload {
  final List<({String name, double amount, String due, IconData icon, Color color})> bills;
  const BillsListPayload(this.bills);
}

class CapabilityListPayload extends ChatPayload {
  const CapabilityListPayload();
}

class CoachingTipPayload extends ChatPayload {
  final String title, body, emoji;
  final Color color;
  const CoachingTipPayload({
    required this.title, required this.body,
    required this.emoji, required this.color,
  });
}

class TransferSentPayload extends ChatPayload {
  final String recipient;
  final String initials;
  final double amount;
  final Color color;
  const TransferSentPayload({
    required this.recipient, required this.initials,
    required this.amount, required this.color,
  });
}

class BudgetUpdatedPayload extends ChatPayload {
  final String category;
  final double oldLimit, newLimit;
  final Color color;
  const BudgetUpdatedPayload({
    required this.category, required this.oldLimit,
    required this.newLimit, required this.color,
  });
  bool get increased => newLimit > oldLimit;
}

class TransactionListPayload extends ChatPayload {
  final List<({String name, String category, double amount, String date, Color color})> transactions;
  const TransactionListPayload(this.transactions);
}
