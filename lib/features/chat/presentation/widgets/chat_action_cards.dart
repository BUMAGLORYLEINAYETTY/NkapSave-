import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/entities/chat_message.dart';

String _fmt(double n) =>
    '${n < 0 ? "-" : ""}${n.abs().toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} FCFA';

class ChatActionCard extends StatelessWidget {
  final ChatPayload payload;
  const ChatActionCard({super.key, required this.payload});

  @override
  Widget build(BuildContext context) {
    return switch (payload) {
      BalanceCardPayload p          => _BalanceCard(p),
      TransactionRecordedPayload p  => _TxRecordedCard(p),
      WeeklySummaryPayload p        => _WeeklyCard(p),
      GoalCreatedPayload p          => _GoalCard(p),
      BudgetStatusPayload p         => _BudgetCard(p),
      NjangiStatusPayload p         => _NjangiCard(p),
      BillsListPayload p            => _BillsCard(p),
      CoachingTipPayload p          => _TipCard(p),
      TransferSentPayload p         => _TransferCard(p),
      BudgetUpdatedPayload p        => _BudgetUpdatedCard(p),
      TransactionListPayload p      => _TxListCard(p),
      CapabilityListPayload _       => const _CapabilityCard(),
    };
  }
}

class _CardShell extends StatelessWidget {
  final Widget child;
  final Color borderColor;
  const _CardShell({required this.child, required this.borderColor});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderColor.withOpacity(0.3)),
      boxShadow: [BoxShadow(color: borderColor.withOpacity(0.08), blurRadius: 16, spreadRadius: -4)],
    ),
    child: child,
  );
}

class _BalanceCard extends StatelessWidget {
  final BalanceCardPayload p;
  const _BalanceCard(this.p);
  @override
  Widget build(BuildContext context) => _CardShell(
    borderColor: AppColors.primary,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('TOTAL BALANCE',
          style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 4),
      Text(_fmt(p.total),
          style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _miniStat(Icons.arrow_upward_rounded, AppColors.success, 'Income', _fmt(p.income))),
        const SizedBox(width: 8),
        Expanded(child: _miniStat(Icons.arrow_downward_rounded, AppColors.danger, 'Expenses', _fmt(p.expenses))),
      ]),
      const SizedBox(height: 8),
      _miniStat(Icons.savings_rounded, AppColors.accent, 'Saved this month', _fmt(p.saved)),
    ]),
  );
}

Widget _miniStat(IconData icon, Color color, String label, String value) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  decoration: BoxDecoration(
    color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10),
    border: Border.all(color: color.withOpacity(0.18)),
  ),
  child: Row(children: [
    Icon(icon, size: 12, color: color),
    const SizedBox(width: 6),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 9.5)),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 11.5, fontWeight: FontWeight.w700)),
    ])),
  ]),
);

class _TxRecordedCard extends StatelessWidget {
  final TransactionRecordedPayload p;
  const _TxRecordedCard(this.p);
  @override
  Widget build(BuildContext context) => _CardShell(
    borderColor: p.color,
    child: Row(children: [
      Container(width: 38, height: 38,
        decoration: BoxDecoration(color: p.color.withOpacity(0.15), borderRadius: BorderRadius.circular(11),
            border: Border.all(color: p.color.withOpacity(0.3))),
        child:  Icon(Icons.check_rounded, color: AppColors.text1, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.name, style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('${p.category} · Today',
            style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 10.5)),
      ])),
      Text('-${_fmt(p.amount)}',
          style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 13, fontWeight: FontWeight.w800)),
    ]),
  );
}

class _WeeklyCard extends StatelessWidget {
  final WeeklySummaryPayload p;
  const _WeeklyCard(this.p);
  @override
  Widget build(BuildContext context) {
    final maxAmt = p.spend.map((e) => e.$2).reduce((a, b) => a > b ? a : b);
    return _CardShell(
      borderColor: AppColors.primary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('THIS WEEK',
              style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          Text(_fmt(p.total),
              style: GoogleFonts.hankenGrotesk(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 70,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: p.spend.map((e) {
            final h = (e.$2 / maxAmt) * 60;
            final isTop = e.$1 == p.topDay;
            return Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(
                  height: h.clamp(4, 60),
                  decoration: BoxDecoration(
                    gradient: isTop
                        ? LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                            colors: AppColors.heroBrandGradient.reversed.toList())
                        : null,
                    color: isTop ? null : AppColors.surface4,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(e.$1, style: GoogleFonts.hankenGrotesk(fontSize: 9, color: isTop ? AppColors.primary : AppColors.text3, fontWeight: isTop ? FontWeight.w700 : FontWeight.w400)),
              ]),
            ));
          }).toList()),
        ),
      ]),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final GoalCreatedPayload p;
  const _GoalCard(this.p);
  @override
  Widget build(BuildContext context) => _CardShell(
    borderColor: AppColors.primary,
    child: Row(children: [
      Container(width: 38, height: 38,
          decoration: BoxDecoration(color: AppColors.primaryDim, borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.primary.withOpacity(0.3))),
          child: Center(child: Text(p.emoji, style: const TextStyle(fontSize: 18)))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(p.name, style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('Target ${_fmt(p.target)} · 0% done',
            style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 10.5)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child:  LinearProgressIndicator(
            value: 0, minHeight: 4,
            backgroundColor: AppColors.surface4,
            valueColor: AlwaysStoppedAnimation(AppColors.primary),
          ),
        ),
      ])),
    ]),
  );
}

class _BudgetCard extends StatelessWidget {
  final BudgetStatusPayload p;
  const _BudgetCard(this.p);
  @override
  Widget build(BuildContext context) => _CardShell(
    borderColor: p.color,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 30, height: 30,
            decoration: BoxDecoration(color: p.color.withOpacity(0.15), borderRadius: BorderRadius.circular(9),
                border: Border.all(color: p.color.withOpacity(0.3))),
            child: Icon(Icons.pie_chart_rounded, color: p.color, size: 14)),
        const SizedBox(width: 10),
        Expanded(child: Text('${p.category} budget',
            style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 12.5, fontWeight: FontWeight.w700))),
        Text('${(p.progress * 100).toStringAsFixed(0)}%',
            style: GoogleFonts.hankenGrotesk(color: p.over ? AppColors.danger : p.color, fontSize: 13, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: p.progress, minHeight: 6,
          backgroundColor: AppColors.surface4,
          valueColor: AlwaysStoppedAnimation(p.over ? AppColors.danger : p.color),
        ),
      ),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('Spent ${_fmt(p.spent)}',
            style: GoogleFonts.hankenGrotesk(color: AppColors.text2, fontSize: 10.5, fontWeight: FontWeight.w500)),
        Text('Limit ${_fmt(p.limit)}',
            style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 10.5)),
      ]),
    ]),
  );
}

class _NjangiCard extends StatelessWidget {
  final NjangiStatusPayload p;
  const _NjangiCard(this.p);
  @override
  Widget build(BuildContext context) {
    final c = p.yourTurn ? AppColors.primary : AppColors.purple;
    return _CardShell(
      borderColor: c,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 32, height: 32,
              decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.withOpacity(0.3))),
              child: Icon(p.yourTurn ? Icons.celebration_rounded : Icons.group_rounded, color: c, size: 16)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.groupName,
                style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 13, fontWeight: FontWeight.w700)),
            Text('${p.memberCount} members',
                style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 10.5)),
          ])),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(color: c.withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Text(p.yourTurn ? '🎉' : '📅', style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(child: Text(
              p.yourTurn ? "Your turn — receiving ${_fmt(p.nextPayout)}" : "Next payout ${_fmt(p.nextPayout)}",
              style: GoogleFonts.hankenGrotesk(color: c, fontSize: 11.5, fontWeight: FontWeight.w700),
            )),
          ]),
        ),
      ]),
    );
  }
}

class _BillsCard extends StatelessWidget {
  final BillsListPayload p;
  const _BillsCard(this.p);
  @override
  Widget build(BuildContext context) => _CardShell(
    borderColor: AppColors.accent,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('UPCOMING BILLS',
          style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 10),
      ...p.bills.map((b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Container(width: 30, height: 30,
              decoration: BoxDecoration(color: b.color.withOpacity(0.15), borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: b.color.withOpacity(0.3))),
              child: Icon(b.icon, color: b.color, size: 14)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b.name, style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 12, fontWeight: FontWeight.w600)),
            Text(b.due, style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 10)),
          ])),
          Text(_fmt(b.amount),
              style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      )),
    ]),
  );
}

class _TipCard extends StatelessWidget {
  final CoachingTipPayload p;
  const _TipCard(this.p);
  @override
  Widget build(BuildContext context) => _CardShell(
    borderColor: p.color,
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 36, height: 36,
          decoration: BoxDecoration(color: p.color.withOpacity(0.15), borderRadius: BorderRadius.circular(11),
              border: Border.all(color: p.color.withOpacity(0.3))),
          child: Center(child: Text(p.emoji, style: const TextStyle(fontSize: 18)))),
      const SizedBox(width: 11),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(color: p.color.withOpacity(0.15), borderRadius: BorderRadius.circular(5)),
            child: Text('TIP',
                style: GoogleFonts.hankenGrotesk(color: p.color, fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          ),
          const SizedBox(width: 6),
          Flexible(child: Text(p.title,
              style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 12.5, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 4),
        Text(p.body,
            style: GoogleFonts.hankenGrotesk(color: AppColors.text2, fontSize: 11.5, height: 1.4)),
      ])),
    ]),
  );
}

class _TransferCard extends StatelessWidget {
  final TransferSentPayload p;
  const _TransferCard(this.p);
  @override
  Widget build(BuildContext context) => _CardShell(
    borderColor: p.color,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('TRANSFER SENT',
          style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 10),
      Row(children: [
        Container(width: 42, height: 42,
          decoration: BoxDecoration(shape: BoxShape.circle,
              color: p.color.withOpacity(0.18),
              border: Border.all(color: p.color.withOpacity(0.35), width: 1.5)),
          child: Center(child: Text(p.initials,
              style: GoogleFonts.hankenGrotesk(color: p.color, fontSize: 14, fontWeight: FontWeight.w800))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.recipient,
              style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 14, fontWeight: FontWeight.w700)),
          Row(children: [
            const Icon(Icons.check_circle_rounded, size: 12, color: AppColors.primary),
            const SizedBox(width: 4),
            Text('Sent · Today',
                style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 10.5)),
          ]),
        ])),
        Text('-${_fmt(p.amount)}',
            style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 13.5, fontWeight: FontWeight.w800)),
      ]),
    ]),
  );
}

class _BudgetUpdatedCard extends StatelessWidget {
  final BudgetUpdatedPayload p;
  const _BudgetUpdatedCard(this.p);
  @override
  Widget build(BuildContext context) => _CardShell(
    borderColor: p.color,
    child: Row(children: [
      Container(width: 38, height: 38,
        decoration: BoxDecoration(color: p.color.withOpacity(0.15), borderRadius: BorderRadius.circular(11),
            border: Border.all(color: p.color.withOpacity(0.3))),
        child: Icon(p.increased ? Icons.trending_up_rounded : Icons.tune_rounded, color: p.color, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${p.category} budget',
            style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Row(children: [
          if (p.oldLimit > 0) ...[
            Text(_fmt(p.oldLimit),
                style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 10.5,
                    decoration: TextDecoration.lineThrough)),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward_rounded, size: 12, color: AppColors.text3),
            const SizedBox(width: 6),
          ],
          Text(_fmt(p.newLimit),
              style: GoogleFonts.hankenGrotesk(color: p.color, fontSize: 12, fontWeight: FontWeight.w800)),
        ]),
      ])),
    ]),
  );
}

class _TxListCard extends StatelessWidget {
  final TransactionListPayload p;
  const _TxListCard(this.p);
  @override
  Widget build(BuildContext context) => _CardShell(
    borderColor: AppColors.primary,
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('RECENT TRANSACTIONS',
          style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
      const SizedBox(height: 8),
      ...p.transactions.take(5).map((t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Container(width: 28, height: 28,
              decoration: BoxDecoration(color: t.color.withOpacity(0.15), borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: t.color.withOpacity(0.3))),
              child: Center(child: Container(width: 7, height: 7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: t.color)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 12, fontWeight: FontWeight.w600)),
            Text('${t.category} · ${t.date}',
                style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 10)),
          ])),
          Text('${t.amount < 0 ? "-" : "+"}${_fmt(t.amount.abs())}',
              style: GoogleFonts.hankenGrotesk(
                color: t.amount > 0 ? AppColors.primary : AppColors.text1,
                fontSize: 12, fontWeight: FontWeight.w700,
              )),
        ]),
      )),
    ]),
  );
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard();
  @override
  Widget build(BuildContext context) {
    const items = [
      ('💸', 'Record expenses', '"I spent 5,000 on taxi"'),
      ('📤', 'Send money',      '"Send 5,000 to Marie"'),
      ('💰', 'Check balance',   '"How much do I have?"'),
      ('📊', 'Budgets',         '"How much is left in food?"'),
      ('⚙️', 'Adjust budget',   '"Set transport budget to 30,000"'),
      ('🎯', 'Savings goals',   '"Save 50,000 for a laptop"'),
      ('📋', 'View activity',   '"Show last 5 transactions"'),
      ('📅', 'Bills',           '"What bills are due?"'),
      ('👥', 'Njangi / tontine','"Njangi status"'),
      ('🧠', 'Coaching',        '"How can I save more?"'),
    ];
    return _CardShell(
      borderColor: AppColors.primary,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final it in items) Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Text(it.$1, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.$2, style: GoogleFonts.hankenGrotesk(color: AppColors.text1, fontSize: 12.5, fontWeight: FontWeight.w700)),
              Text(it.$3, style: GoogleFonts.hankenGrotesk(color: AppColors.text3, fontSize: 10.5, fontStyle: FontStyle.italic)),
            ])),
          ]),
        ),
      ]),
    );
  }
}
