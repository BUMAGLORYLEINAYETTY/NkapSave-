import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/nkap_card.dart';
import '../../../../core/widgets/nkap_button.dart';
import '../../../../core/widgets/nkap_chip.dart';

// ─── Models ───────────────────────────────────────────────────────────────────

class SavingsGoal {
  final String id, name, emoji;
  final double target, current;
  final Color color;
  final bool isLocked;
  const SavingsGoal({
    required this.id, required this.name, required this.emoji,
    required this.target, required this.current, required this.color,
    this.isLocked = true,
  });
  double get percent => (current / target).clamp(0.0, 1.0);
  double get remaining => target - current;
}

class AutoSaveConfig {
  final bool active;
  final int percent;
  final String provider;
  final double savedThisMonth;
  const AutoSaveConfig({
    required this.active, required this.percent,
    required this.provider, required this.savedThisMonth,
  });
}

// ─── Mock Data ────────────────────────────────────────────────────────────────

const _mockAutoSave = AutoSaveConfig(
  active: true, percent: 10,
  provider: 'MTN Money', savedThisMonth: 35000,
);

final _mockGoals = [
  SavingsGoal(id:'1', name:'Emergency Fund',  emoji:'🛡️',
      target:1000000, current:620000, color:AppColors.primary),
  SavingsGoal(id:'2', name:'New Phone',        emoji:'📱',
      target:200000,  current:155000, color:AppColors.info),
  SavingsGoal(id:'3', name:'Trip to Douala',   emoji:'✈️',
      target:300000,  current:85000,  color:AppColors.accent),
  SavingsGoal(id:'4', name:'Business Capital', emoji:'💼',
      target:500000,  current:45000,  color:AppColors.purple),
];

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _fmt(double n) => n.abs()
    .toStringAsFixed(0)
    .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

// ─── Savings Screen ───────────────────────────────────────────────────────────

class SavingsScreen extends StatefulWidget {
  const SavingsScreen({super.key});
  @override
  State<SavingsScreen> createState() => _SavingsScreenState();
}

class _SavingsScreenState extends State<SavingsScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  int _autoSavePct = 10;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  double get _totalSaved => _mockGoals.fold(0, (s, g) => s + g.current);
  double get _totalTarget => _mockGoals.fold(0, (s, g) => s + g.target);

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadData();
  }

  Future<void> _loadData() async {
    // TODO: replace with ApiClient → GET /api/v1/savings
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) {
      setState(() => _loading = false);
      _fadeCtrl.forward();
    }
  }

  @override
  void dispose() { _fadeCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _loading ? _buildSkeleton() : FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          slivers: [
            _buildAppBar(),
            SliverToBoxAdapter(child: Column(children: [
              _buildHeader(),
              _buildAutoSaveCard(),
              _buildLockedWalletBanner(),
              _buildGoalsHeader(),
              ..._mockGoals.map(_buildGoalCard),
              _buildTipCard(),
              const SizedBox(height: 100),
            ])),
          ],
        ),
      ),
      floatingActionButton: _loading ? null : FloatingActionButton.extended(
        onPressed: () => _showAddGoalSheet(),
        backgroundColor: AppColors.primary,
        foregroundColor: const Color(0xFFFFFFFF),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text('New Goal', style: GoogleFonts.hankenGrotesk(
            fontWeight: FontWeight.w800, fontSize: 13)),
        elevation: 0,
      ),
    );
  }

  // ── App Bar ────────────────────────────────────────────────────────────────

  SliverAppBar _buildAppBar() => SliverAppBar(
    backgroundColor: AppColors.surface1,
    elevation: 0, pinned: true, toolbarHeight: 56,
    title: Text('Savings', style: GoogleFonts.hankenGrotesk(
        color: AppColors.text1, fontWeight: FontWeight.w800, fontSize: 18)),
    actions: [
      IconButton(
        icon:  Icon(Icons.history_rounded, color: AppColors.text2, size: 20),
        onPressed: () {},
      ),
    ],
  );

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [const Color(0xFF0D2020), AppColors.bg],
      ),
    ),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Total Saved', style: GoogleFonts.hankenGrotesk(
            color: AppColors.text3, fontSize: 11, letterSpacing: 1.2)),
        const SizedBox(height: 6),
        Text('${_fmt(_totalSaved)} FCFA', style: GoogleFonts.hankenGrotesk(
            color: AppColors.text1, fontSize: 28, fontWeight: FontWeight.w800,
            letterSpacing: -1)),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.arrow_upward_rounded,
              size: 13, color: AppColors.primary),
          const SizedBox(width: 4),
          Text('+${_fmt(_mockAutoSave.savedThisMonth)} FCFA this month',
              style: GoogleFonts.hankenGrotesk(
                  color: AppColors.primary, fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ]),
      ])),
      // Overall ring
      CircularPercentIndicator(
        radius: 42,
        lineWidth: 6,
        percent: (_totalSaved / _totalTarget).clamp(0, 1),
        center: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${((_totalSaved / _totalTarget) * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.hankenGrotesk(fontSize: 14, fontWeight: FontWeight.w800,
                  color: AppColors.primary)),
          Text('overall', style: GoogleFonts.hankenGrotesk(
              fontSize: 9, color: AppColors.text3)),
        ]),
        progressColor: AppColors.primary,
        backgroundColor: AppColors.border1,
        circularStrokeCap: CircularStrokeCap.round,
      ),
    ]),
  );

  // ── Auto Save Card ─────────────────────────────────────────────────────────

  Widget _buildAutoSaveCard() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: NkapCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Auto-Save Rate', style: GoogleFonts.hankenGrotesk(
                fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.text1)),
            const SizedBox(height: 3),
            Text('${_mockAutoSave.provider} · Connected',
                style: GoogleFonts.hankenGrotesk(fontSize: 11, color: AppColors.text3)),
          ]),
          NkapChip(label: 'ACTIVE', color: AppColors.primary,
              dimColor: AppColors.primaryDim),
        ]),
        const SizedBox(height: 18),
        // Big percentage display
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$_autoSavePct', style: GoogleFonts.hankenGrotesk(
              fontSize: 48, fontWeight: FontWeight.w800,
              color: AppColors.primary, height: 1)),
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 3),
            child: Text('%', style: GoogleFonts.hankenGrotesk(
                fontSize: 22, fontWeight: FontWeight.w700,
                color: AppColors.primary)),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primaryDim,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primaryMid),
            ),
            child: Column(children: [
              Text('Saved/month', style: GoogleFonts.hankenGrotesk(
                  fontSize: 9.5, color: AppColors.text3)),
              const SizedBox(height: 2),
              Text('${_fmt(_mockAutoSave.savedThisMonth)} FCFA',
                  style: GoogleFonts.hankenGrotesk(fontSize: 13,
                      fontWeight: FontWeight.w700, color: AppColors.primary)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        // Slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: AppColors.border2,
            thumbColor: AppColors.primary,
            overlayColor: AppColors.primaryDim,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            trackHeight: 4,
          ),
          child: Slider(
            value: _autoSavePct.toDouble(),
            min: 5, max: 30, divisions: 5,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              setState(() => _autoSavePct = v.round());
            },
            onChangeEnd: (v) {
              // TODO: PATCH /api/v1/savings/auto-save {"percent": v}
            },
          ),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('5%', style: GoogleFonts.hankenGrotesk(
              fontSize: 10, color: AppColors.text3)),
          Text('30%', style: GoogleFonts.hankenGrotesk(
              fontSize: 10, color: AppColors.text3)),
        ]),
        const SizedBox(height: 14),
        // Provider buttons
        Row(children: [
          _ProviderBtn(label: 'MTN Money',    emoji: '🟡',
              selected: true,  onTap: () {}),
          const SizedBox(width: 10),
          _ProviderBtn(label: 'Orange Money', emoji: '🟠',
              selected: false, onTap: () {}),
        ]),
      ]),
    ),
  );

  // ── Locked Wallet Banner ───────────────────────────────────────────────────

  Widget _buildLockedWalletBanner() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.accent.withOpacity(0.1),
          AppColors.accent.withOpacity(0.04),
        ]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withOpacity(0.22)),
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: AppColors.accentDim,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.accentMid),
          ),
          child: const Icon(Icons.lock_rounded,
              color: AppColors.accent, size: 19),
        ),
        const SizedBox(width: 13),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Locked Wallet', style: GoogleFonts.hankenGrotesk(
              fontWeight: FontWeight.w700, fontSize: 13,
              color: AppColors.accent)),
          const SizedBox(height: 2),
          Text('Funds inaccessible until goal is reached',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11, color: AppColors.text2)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${_fmt(_mockAutoSave.savedThisMonth)} FCFA',
              style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w800,
                  fontSize: 14, color: AppColors.accent)),
          Text('this month', style: GoogleFonts.hankenGrotesk(
              fontSize: 10, color: AppColors.text3)),
        ]),
      ]),
    ),
  );

  // ── Goals Header ───────────────────────────────────────────────────────────

  Widget _buildGoalsHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text('Savings Goals', style: GoogleFonts.hankenGrotesk(
          fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.text1)),
      Text('${_mockGoals.length} active', style: GoogleFonts.hankenGrotesk(
          fontSize: 11, color: AppColors.text3)),
    ]),
  );

  // ── Goal Card ──────────────────────────────────────────────────────────────

  Widget _buildGoalCard(SavingsGoal g) {
    final monthsLeft = _autoSavePct > 0
        ? (g.remaining / (350000 * _autoSavePct / 100)).ceil()
        : 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GestureDetector(
        onTap: () => _showGoalDetail(g),
        child: NkapCard(
          child: Row(children: [
            // Ring
            CircularPercentIndicator(
              radius: 36,
              lineWidth: 5,
              percent: g.percent,
              center: Text(g.emoji,
                  style: const TextStyle(fontSize: 18)),
              progressColor: g.color,
              backgroundColor: AppColors.border1,
              circularStrokeCap: CircularStrokeCap.round,
              animation: true,
              animationDuration: 800,
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(g.name, style: GoogleFonts.hankenGrotesk(
                    fontWeight: FontWeight.w700, fontSize: 13,
                    color: AppColors.text1)),
                Text('${(g.percent * 100).toStringAsFixed(0)}%',
                    style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w800,
                        fontSize: 14, color: g.color)),
              ]),
              const SizedBox(height: 4),
              Text('${_fmt(g.current)} / ${_fmt(g.target)} FCFA',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 11, color: AppColors.text3)),
              const SizedBox(height: 8),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: g.percent,
                  minHeight: 5,
                  backgroundColor: AppColors.border1,
                  valueColor: AlwaysStoppedAnimation(g.color),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                g.percent >= 1.0
                    ? '🎉 Goal reached!'
                    : '${_fmt(g.remaining)} left · ~$monthsLeft month${monthsLeft != 1 ? "s" : ""} at current rate',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 10.5, color: AppColors.text3),
              ),
            ])),
          ]),
        ),
      ),
    );
  }

  // ── Tip Card ───────────────────────────────────────────────────────────────

  Widget _buildTipCard() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.purple.withOpacity(0.1),
          AppColors.purple.withOpacity(0.03),
        ]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.purple.withOpacity(0.2)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: AppColors.purpleDim,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppColors.purple.withOpacity(0.3)),
          ),
          child: const Icon(Icons.lightbulb_rounded,
              color: AppColors.purple, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Savings Tip', style: GoogleFonts.hankenGrotesk(
              fontWeight: FontWeight.w700, fontSize: 12,
              color: AppColors.purple)),
          const SizedBox(height: 4),
          Text(
            'Increasing your auto-save rate by just 5% would add ~17,500 FCFA/month to your Emergency Fund — reaching it 4 months sooner! 🚀',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 12, color: AppColors.text2, height: 1.55),
          ),
        ])),
      ]),
    ),
  );

  // ── Add Goal Sheet ─────────────────────────────────────────────────────────

  void _showAddGoalSheet() {
    final nameCtrl   = TextEditingController();
    final targetCtrl = TextEditingController();
    String selectedEmoji = '🎯';
    final emojis = ['🎯','🏠','🚗','📱','✈️','🎓','💼','💍','🏋️','🌍'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom),
          decoration:  BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(99)),
              )),
              const SizedBox(height: 20),
              Text('New Savings Goal', style: GoogleFonts.hankenGrotesk(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  color: AppColors.text1)),
              const SizedBox(height: 20),
              // Emoji picker
              Align(alignment: Alignment.centerLeft,
                child: Text('Choose Icon', style: GoogleFonts.hankenGrotesk(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: AppColors.text2))),
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: emojis.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final sel = emojis[i] == selectedEmoji;
                    return GestureDetector(
                      onTap: () => setSheet(() => selectedEmoji = emojis[i]),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primaryDim : AppColors.surface2,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: sel ? AppColors.primary : AppColors.border2),
                        ),
                        child: Center(child: Text(emojis[i],
                            style: const TextStyle(fontSize: 22))),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 14),
              _SheetField(controller: nameCtrl, label: 'Goal Name',
                  hint: 'e.g. Emergency Fund',
                  icon: Icons.flag_rounded),
              const SizedBox(height: 14),
              _SheetField(controller: targetCtrl, label: 'Target Amount (FCFA)',
                  hint: 'e.g. 500000',
                  icon: Icons.savings_rounded,
                  keyboardType: TextInputType.number),
              const SizedBox(height: 24),
              NkapButton(
                label: 'Create Goal',
                icon: Icons.check_rounded,
                onTap: () {
                  // TODO: POST /api/v1/savings/goals
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Goal created!',
                        style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
                    backgroundColor: AppColors.primary.withOpacity(0.9),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ));
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ── Goal Detail Sheet ──────────────────────────────────────────────────────

  void _showGoalDetail(SavingsGoal g) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration:  BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: AppColors.border2,
                borderRadius: BorderRadius.circular(99)),
          )),
          const SizedBox(height: 24),
          Text(g.emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 10),
          Text(g.name, style: GoogleFonts.hankenGrotesk(
              fontSize: 20, fontWeight: FontWeight.w800,
              color: AppColors.text1)),
          const SizedBox(height: 6),
          Text('${(g.percent * 100).toStringAsFixed(0)}% Complete',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 13, color: g.color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          CircularPercentIndicator(
            radius: 60,
            lineWidth: 8,
            percent: g.percent,
            center: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${_fmt(g.current)}', style: GoogleFonts.hankenGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w800,
                  color: AppColors.text1)),
              Text('FCFA', style: GoogleFonts.hankenGrotesk(
                  fontSize: 10, color: AppColors.text3)),
            ]),
            progressColor: g.color,
            backgroundColor: AppColors.border1,
            circularStrokeCap: CircularStrokeCap.round,
            animation: true,
          ),
          const SizedBox(height: 20),
          _DetailRow(label: 'Target',    value: '${_fmt(g.target)} FCFA'),
          _DetailRow(label: 'Saved',     value: '${_fmt(g.current)} FCFA'),
          _DetailRow(label: 'Remaining', value: '${_fmt(g.remaining)} FCFA'),
          _DetailRow(label: 'Status',    value: g.isLocked ? '🔒 Locked' : '🔓 Unlocked'),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: NkapButton(
                label: 'Withdraw', outlined: true,
                color: AppColors.danger,
                onTap: () => Navigator.pop(context))),
            const SizedBox(width: 12),
            Expanded(child: NkapButton(
                label: 'Add Funds',
                onTap: () => Navigator.pop(context))),
          ]),
        ]),
      ),
    );
  }

  // ── Skeleton ───────────────────────────────────────────────────────────────

  Widget _buildSkeleton() => Shimmer.fromColors(
    baseColor: AppColors.surface2,
    highlightColor: AppColors.surface3,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        const SizedBox(height: 60),
        Container(height: 90, decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(16))),
        const SizedBox(height: 12),
        Container(height: 200, decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(20))),
        const SizedBox(height: 12),
        Container(height: 70, decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(18))),
        const SizedBox(height: 12),
        ...List.generate(3, (_) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(height: 90, decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(20))),
        )),
      ]),
    ),
  );
}

// ─── Provider Button ──────────────────────────────────────────────────────────

class _ProviderBtn extends StatelessWidget {
  final String label, emoji;
  final bool selected;
  final VoidCallback onTap;
  const _ProviderBtn({required this.label, required this.emoji,
      required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryDim : AppColors.surface3,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? AppColors.primaryMid : AppColors.border2),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.hankenGrotesk(
              fontSize: 12.5, fontWeight: FontWeight.w600,
              color: selected ? AppColors.primary : AppColors.text2)),
        ]),
      ),
    ),
  );
}

// ─── Detail Row ───────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final String label, value;
  const _DetailRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: GoogleFonts.hankenGrotesk(
          fontSize: 13, color: AppColors.text3)),
      Text(value, style: GoogleFonts.hankenGrotesk(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: AppColors.text1)),
    ]),
  );
}

// ─── Sheet Field ──────────────────────────────────────────────────────────────

class _SheetField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final IconData icon;
  final TextInputType? keyboardType;
  const _SheetField({required this.controller, required this.label,
      required this.hint, required this.icon, this.keyboardType});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: GoogleFonts.hankenGrotesk(
          fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text2)),
      const SizedBox(height: 7),
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: GoogleFonts.hankenGrotesk(fontSize: 14, color: AppColors.text1),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, size: 18, color: AppColors.text3),
        ),
      ),
    ],
  );
}
