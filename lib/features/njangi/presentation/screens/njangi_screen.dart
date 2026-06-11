import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:shimmer/shimmer.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/user_preferences.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../profile/presentation/screens/kyc_screen.dart';
import '../../../../core/constants/feature_flags.dart';
import 'group_chat_screen.dart';
import '../../../../core/widgets/nkap_card.dart';
import '../../../../core/widgets/nkap_button.dart';
import '../../../../core/widgets/nkap_chip.dart';
import '../../../../core/constants/app_text_styles.dart';

// ─── Operator brand colors ───────────────────────────────────
class _Brand {
  static const mtnYellow   = Color(0xFFFFCC00);
  static const mtnDark     = Color(0xFF1A1A1A);
  static const orangeRed   = Color(0xFFFF6600);
}

String _fmt(double n) => n.abs().toStringAsFixed(0)
    .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

const _memberColors = [
  Color(0xFF12E8A4), Color(0xFF60A5FA), Color(0xFFFFB627),
  Color(0xFFA78BFA), Color(0xFFFF7043), Color(0xFFEC407A),
  Color(0xFF26C6DA), Color(0xFF42A5F5),
];

// ─── Detect operator from Cameroon phone ────────────────────
// MTN: 67, 68, 650-654   |   Orange: 69, 655-659
String? _detectOperator(String phone) {
  final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (clean.length < 2) return null;
  final p2 = clean.substring(0, 2);
  if (['67', '68'].contains(p2)) return 'MTN';
  if (p2 == '69') return 'Orange';
  if (p2 == '65' && clean.length >= 3) {
    final d3 = clean[2];
    if (['0','1','2','3','4'].contains(d3)) return 'MTN';
    if (['5','6','7','8','9'].contains(d3)) return 'Orange';
  }
  if (p2 == '66') return 'MTN';
  return null;
}

// ═══════════════════════════════════════════════════════════════
// MAIN NJANGI SCREEN
// ═══════════════════════════════════════════════════════════════
class NjangiScreen extends StatefulWidget {
  const NjangiScreen({super.key});
  @override State<NjangiScreen> createState() => _NjangiScreenState();
}

class _NjangiScreenState extends State<NjangiScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  Map<String, dynamic>? _selected;
  Map<String, dynamic> _data = {};
  Map<String, dynamic>? _profile;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profileFuture = ApiService.getMyProfile()
        .catchError((_) => <String, dynamic>{});
    try {
      final res = await ApiService.getNjangi();
      final p = await profileFuture;
      if (mounted) {
        setState(() {
          _data = res;
          _profile = p.isEmpty ? null : p;
          _loading = false;
        });
        _fadeCtrl.forward(from: 0);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openProfile() async {
    HapticFeedback.lightImpact();
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
    if (!mounted) return;
    final p = await ApiService.getMyProfile()
        .catchError((_) => <String, dynamic>{});
    if (!mounted) return;
    setState(() => _profile = p.isEmpty ? null : p);
  }

  String get _profileName =>
      (_profile?['full_name'] ?? '').toString().trim().isEmpty
          ? 'Your profile'
          : _profile!['full_name'].toString();

  String get _profileInitial {
    final n = (_profile?['full_name'] ?? '').toString().trim();
    return n.isEmpty ? '?' : n[0].toUpperCase();
  }

  String get _profileAvatarUrl =>
      ApiService.pictureUrl(_profile?['profile_picture'] as String?);

  @override void dispose() { _fadeCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_selected != null) {
      return _GroupDetail(
        group: _selected!,
        onBack: () => setState(() => _selected = null),
        onRefresh: () { setState(() => _selected = null); _load(); },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _loading
          ? _buildSkeleton()
          : FadeTransition(
              opacity: _fadeAnim,
              child: CustomScrollView(slivers: [
                SliverAppBar(
                  backgroundColor: AppColors.surface1,
                  elevation: 0, pinned: true, toolbarHeight: 56,
                  title: Text('My Njangi', style: GoogleFonts.hankenGrotesk(
                      color: AppColors.text1,
                      fontWeight: FontWeight.w800, fontSize: 18)),
                  actions: [
                    IconButton(
                        icon:  Icon(Icons.refresh_rounded,
                            color: AppColors.text2, size: 20),
                        onPressed: _load),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openProfile,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: _appBarAvatar(),
                      ),
                    ),
                  ],
                ),
                SliverToBoxAdapter(child: Column(children: [
                  _buildTrustCard(),
                  _buildSectionHeader(),
                  _buildGroupList(),
                  const SizedBox(height: 100),
                ])),
              ]),
            ),
      floatingActionButton: _loading ? null : FloatingActionButton.extended(
        heroTag: 'njangi_create_btn',
        onPressed: () => _gateVerified(_showCreateSheet),
        backgroundColor: AppColors.primary,
        foregroundColor: const Color(0xFFFFFFFF),
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text('Create Group', style: GoogleFonts.hankenGrotesk(
            fontWeight: FontWeight.w800, fontSize: 13)),
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _appBarAvatar() {
    final url = _profileAvatarUrl;
    return Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: url.isEmpty
            ? const LinearGradient(colors: [AppColors.primary, Color(0xFF006C45)])
            : null,
        color: url.isEmpty ? null : AppColors.surface3,
        image: url.isEmpty ? null : DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
        border: Border.all(color: AppColors.primary.withOpacity(0.5), width: 1.5),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 10)],
      ),
      child: url.isEmpty
          ? Center(child: Text(_profileInitial,
              style: GoogleFonts.hankenGrotesk(color: AppColors.surface1, fontWeight: FontWeight.w800, fontSize: 14)))
          : null,
    );
  }

  Widget _profileAvatarRing(double trust) {
    final url = _profileAvatarUrl;
    return CircularPercentIndicator(
      radius: 46, lineWidth: 5,
      percent: (trust / 100).clamp(0.0, 1.0),
      center: Container(
        width: 70, height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: url.isEmpty
              ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [AppColors.primary, Color(0xFF006C45)])
              : null,
          color: url.isEmpty ? null : AppColors.surface3,
          image: url.isEmpty
              ? null
              : DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
        ),
        child: url.isEmpty
            ? Center(child: Text(_profileInitial,
                style: GoogleFonts.hankenGrotesk(color: AppColors.surface1, fontSize: 24, fontWeight: FontWeight.w800)))
            : null,
      ),
      progressColor: trust >= 80 ? AppColors.primary : AppColors.accent,
      backgroundColor: AppColors.border1,
      circularStrokeCap: CircularStrokeCap.round,
    );
  }

  Widget _buildTrustCard() {
    final trust = (_data['trust_score'] ?? 100.0) * 1.0;
    final List groups = _data['groups'] ?? [];
    final occupation = (_profile?['occupation'] ?? '').toString();
    final location = (_profile?['location'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openProfile,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: AppColors.heroNavyGradient),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.primary.withOpacity(0.2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Stack(clipBehavior: Clip.none, children: [
                _profileAvatarRing(trust),
                Positioned(
                  bottom: -2, right: -2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: trust >= 80 ? AppColors.primary : AppColors.accent,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                          color: AppColors.charcoal, width: 1.5),
                    ),
                    child: Text('${trust.toStringAsFixed(0)}%',
                        style: GoogleFonts.hankenGrotesk(
                            color: AppColors.heroFg,
                            fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ),
              ]),
              const SizedBox(width: 18),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_profileName,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.hankenGrotesk(
                          fontWeight: FontWeight.w800, fontSize: 16,
                          color: AppColors.heroFg)),
                  if (occupation.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(occupation,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 12, color: AppColors.heroFgMuted,
                            fontWeight: FontWeight.w600)),
                  ],
                  if (location.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(children: [
                       Icon(Icons.location_on_rounded,
                          size: 11, color: AppColors.heroFgDim),
                      const SizedBox(width: 3),
                      Flexible(child: Text(location,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 11, color: AppColors.heroFgDim))),
                    ]),
                  ],
                  if (occupation.isEmpty && location.isEmpty) ...[
                    const SizedBox(height: 4),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.edit_rounded, size: 11, color: AppColors.heroFgMuted),
                      const SizedBox(width: 4),
                      Text('Complete your profile',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 11, color: AppColors.heroFgMuted,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ],
                ])),
               Icon(Icons.chevron_right_rounded,
                  color: AppColors.heroFgDim, size: 22),
            ]),
            const SizedBox(height: 14),
            Container(height: 1, color: AppColors.heroFg.withOpacity(0.12)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text('Trust Score', style: GoogleFonts.hankenGrotesk(
                    fontWeight: FontWeight.w800, fontSize: 13,
                    color: AppColors.heroFg)),
                const SizedBox(height: 3),
                Text(trust >= 90 ? 'Excellent · Full payouts unlocked'
                    : trust >= 70 ? 'Good · Keep paying on time'
                    : 'Needs improvement',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 11.5, color: AppColors.heroFgMuted)),
              ])),
              NkapChip(
                  label: '${groups.length} Group${groups.length != 1 ? "s" : ""}',
                  color: AppColors.primary, dimColor: AppColors.primaryDim),
              const SizedBox(width: 6),
              NkapChip(
                  label: trust >= 80 ? 'Full Payout' : 'Partial',
                  color: trust >= 80 ? AppColors.primary : AppColors.accent,
                  dimColor: trust >= 80
                      ? AppColors.primaryDim : AppColors.accentDim),
            ]),
          ]),
        ),
      ),
    );
  }

  /// "Tontine Savings / Active Groups" header with the "Join New" CTA —
  /// shares the existing `_gateVerified(_showJoinSheet)` entry point that
  /// previously lived on the Join FAB.
  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('TONTINE SAVINGS',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: AppColors.text3, letterSpacing: 1.4)),
            const SizedBox(height: 4),
            Text('Active Groups', style: AppTextStyles.h2),
          ],
        )),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => _gateVerified(_showJoinSheet),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add_rounded, size: 18, color: Color(0xFFFFFFFF)),
              const SizedBox(width: 6),
              Text('Join New',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: const Color(0xFFFFFFFF))),
            ]),
          ),
        ),
      ]),
    );
  }

  // Icons cycled through for the "More Groups" tinted circular badges —
  // the API doesn't return a category/icon, so pick deterministically by
  // index for visual variety without invented data.
  static const _groupIcons = [
    Icons.school_rounded, Icons.agriculture_rounded, Icons.home_work_rounded,
    Icons.storefront_rounded, Icons.directions_car_rounded,
    Icons.flight_takeoff_rounded,
  ];

  Widget _buildGroupList() {
    final List groups = _data['groups'] ?? [];
    if (groups.isEmpty) return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(child: Column(children: [
        const Text('👥', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 16),
        Text('No Njangi groups yet',
            style: GoogleFonts.hankenGrotesk(color: AppColors.text2,
                fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('Create or join a rotating savings group',
            style: GoogleFonts.hankenGrotesk(
                color: AppColors.text3, fontSize: 13)),
      ])),
    );

    // Featured group: prefer one where it's the user's turn to collect,
    // otherwise the first group.
    final featuredIndex = groups.indexWhere((g) => (g['is_my_turn'] ?? false) == true);
    final featured = groups[featuredIndex >= 0 ? featuredIndex : 0];
    final rest = [
      for (int i = 0; i < groups.length; i++)
        if (i != (featuredIndex >= 0 ? featuredIndex : 0)) groups[i],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: _buildFeaturedGroupCard(featured),
        ),
        if (rest.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Text('More Groups', style: AppTextStyles.h3),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: rest.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.92,
              ),
              itemBuilder: (_, i) => _buildMoreGroupCard(rest[i], i),
            ),
          ),
        ],
      ],
    );
  }

  /// Full-width brand-gradient hero card for the featured Njangi group —
  /// mirrors the Stitch "Family Support" card.
  Widget _buildFeaturedGroupCard(Map g) {
    final isMyTurn = (g['is_my_turn'] ?? false) as bool;
    final cycle = (g['current_cycle'] ?? 1) as int;
    final total = (g['total_cycles'] ?? 1) as int;
    final pct = ((g['progress_pct'] ?? 0) as num).toDouble() / 100;
    final mc = (g['member_count'] ?? 0) as int;
    final nextRecipient = (g['next_recipient'] ?? '').toString();

    return GestureDetector(
      onTap: () => setState(() => _selected = Map<String, dynamic>.from(g)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: AppColors.heroBrandGradient),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.verified_rounded, size: 16, color: AppColors.heroFgMuted),
                  const SizedBox(width: 6),
                  Text('NJANGI PRIORITY',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 10.5, fontWeight: FontWeight.w700,
                          color: AppColors.heroFgMuted, letterSpacing: 1.4)),
                ]),
                const SizedBox(height: 6),
                Text((g['name'] ?? '').toString(),
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 20, fontWeight: FontWeight.w800,
                        color: AppColors.heroFg, height: 1.15)),
              ],
            )),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.heroFg.withOpacity(0.15),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: AppColors.heroFg.withOpacity(0.2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: AppColors.heroFg),
                ),
                const SizedBox(width: 6),
                Text('Active Cycle',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: AppColors.heroFg)),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Cycle Progress',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 12.5, fontWeight: FontWeight.w600,
                    color: AppColors.heroFg)),
            Text('$cycle/$total Contributions',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 12.5, fontWeight: FontWeight.w700,
                    color: AppColors.heroFg)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0), minHeight: 8,
              backgroundColor: Colors.black.withOpacity(0.18),
              valueColor: AlwaysStoppedAnimation(AppColors.heroFg),
            ),
          ),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.heroFg.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.heroFg.withOpacity(0.08)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Members',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 10.5, fontWeight: FontWeight.w600,
                          color: AppColors.heroFgMuted)),
                  const SizedBox(height: 4),
                  Text('$mc',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 16, fontWeight: FontWeight.w800,
                          color: AppColors.heroFg)),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isMyTurn ? AppColors.accent : AppColors.heroFg.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: isMyTurn
                          ? AppColors.accent
                          : AppColors.heroFg.withOpacity(0.08)),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (isMyTurn) Row(children: [
                    Icon(Icons.stars_rounded, size: 14, color: AppColors.charcoal),
                    const SizedBox(width: 4),
                    Text('YOUR TURN',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 10, fontWeight: FontWeight.w800,
                            color: AppColors.charcoal, letterSpacing: 0.6)),
                  ]) else Text('Next Recipient',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 10.5, fontWeight: FontWeight.w600,
                          color: AppColors.heroFgMuted)),
                  const SizedBox(height: 4),
                  Text(isMyTurn
                          ? 'Collection Day'
                          : (nextRecipient.isEmpty ? '—' : nextRecipient),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 14, fontWeight: FontWeight.w800,
                          color: isMyTurn ? AppColors.charcoal : AppColors.heroFg)),
                ]),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  /// Compact "More Groups" bento card — circular tinted icon, member count
  /// and a slim progress bar.
  Widget _buildMoreGroupCard(Map g, int index) {
    final pct = ((g['progress_pct'] ?? 0) as num).toDouble() / 100;
    final mc = (g['member_count'] ?? 0) as int;
    final isMyTurn = (g['is_my_turn'] ?? false) as bool;
    final tint = _memberColors[index % _memberColors.length];
    final icon = _groupIcons[index % _groupIcons.length];

    return GestureDetector(
      onTap: () => setState(() => _selected = Map<String, dynamic>.from(g)),
      child: NkapCard(
        radius: 20,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: tint.withOpacity(0.15)),
              child: Icon(icon, size: 20, color: tint),
            ),
            const Spacer(),
            Text((g['name'] ?? '').toString(),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 14, fontWeight: FontWeight.w800,
                    height: 1.2, color: AppColors.text1)),
            const SizedBox(height: 2),
            Text('$mc Member${mc != 1 ? "s" : ""}',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 11, color: AppColors.text3)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0), minHeight: 5,
                backgroundColor: AppColors.border1,
                valueColor: AlwaysStoppedAnimation(
                    isMyTurn ? AppColors.accent : AppColors.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Pre-emptive client gate: every njangi money action also requires
  /// verification on the backend (returns 403), but intercepting here
  /// gives the user a friendlier "verify first" sheet instead of an
  /// error toast after they've filled in a form.
  void _gateVerified(VoidCallback onVerified) {
    HapticFeedback.lightImpact();
    // KYC is temporarily disabled — let everyone through. The backend
    // gate (403 on money endpoints) is also off while `kKycEnabled` is
    // false, so this stays consistent. Re-enable both when the new
    // verification pipeline ships.
    if (!kKycEnabled) { onVerified(); return; }
    final isVerified = _profile?['is_verified'] == true;
    if (isVerified) { onVerified(); return; }
    _showVerifyFirstSheet();
  }

  void _showVerifyFirstSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(99)))),
          const SizedBox(height: 22),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
                color: AppColors.primaryDim,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.primaryMid)),
            child: const Icon(Icons.verified_user_rounded,
                color: AppColors.primary, size: 32),
          ),
          const SizedBox(height: 16),
          Text('Verify your identity first',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  color: AppColors.text1)),
          const SizedBox(height: 8),
          Text(
            'Every njangi member must be ID-verified with their Cameroon '
            'CNI before they can create or join a group. This protects '
            'every member’s money and keeps the trust score honest.',
            textAlign: TextAlign.center,
            style: GoogleFonts.hankenGrotesk(
                fontSize: 13, color: AppColors.text2, height: 1.5)),
          const SizedBox(height: 22),
          NkapButton(
            label: 'Verify my identity',
            icon: Icons.badge_outlined,
            onTap: () async {
              // Capture the root navigator before popping the sheet so
              // we don't reuse the sheet's BuildContext after it's gone.
              final rootNav = Navigator.of(context, rootNavigator: true);
              Navigator.pop(context);
              await rootNav.push(MaterialPageRoute(
                  builder: (_) => const KycScreen()));
              if (mounted) _load();
            },
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Not now',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: AppColors.text3)),
          ),
        ]),
      ),
    );
  }

  void _showCreateSheet() {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final maxCtrl = TextEditingController();
    String freq = 'Monthly';
    DateTime startDate = DateTime.now().add(const Duration(days: 7));
    bool creating = false;
    final freqs = ['Daily', 'Weekly', 'Bi-Weekly', 'Monthly', 'Quarterly', 'Custom'];
    final customDaysCtrl = TextEditingController();
    int customDays = 7;

    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, set) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration:  BoxDecoration(color: AppColors.surface1,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _handle(),
              const SizedBox(height: 20),
              Text('Create Njangi Group', style: GoogleFonts.hankenGrotesk(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  color: AppColors.text1)),
              const SizedBox(height: 6),
              Text('Set up your rotating savings group',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 12, color: AppColors.text3)),
              const SizedBox(height: 20),
              _field(nameCtrl, 'Group Name',
                  'e.g. Quarter Friends', Icons.group_rounded),
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft,
                  child: Text('Group Description (optional)',
                      style: GoogleFonts.hankenGrotesk(fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text2))),
              const SizedBox(height: 7),
              TextField(
                controller: descCtrl, maxLines: 3, maxLength: 300,
                style: GoogleFonts.hankenGrotesk(fontSize: 13, color: AppColors.text1),
                decoration:  InputDecoration(
                  hintText: 'What is this group about? (e.g. monthly savings for back-to-school expenses)',
                  prefixIcon: Padding(
                    padding: EdgeInsets.only(left: 12, top: 12, right: 8),
                    child: Icon(Icons.description_rounded,
                        size: 18, color: AppColors.text3),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _field(amountCtrl, 'Contribution per Member (FCFA)',
                  'e.g. 10000', Icons.payments_rounded,
                  TextInputType.number),
              const SizedBox(height: 14),
              // Number of members - free input
              Align(alignment: Alignment.centerLeft,
                  child: Text('Number of Members',
                      style: GoogleFonts.hankenGrotesk(fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text2))),
              const SizedBox(height: 7),
              TextField(
                controller: maxCtrl,
                keyboardType: TextInputType.number,
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 14, color: AppColors.text1),
                decoration:  InputDecoration(
                  hintText: 'e.g. 10, 25, 100 - your choice',
                  prefixIcon: Icon(Icons.people_alt_rounded,
                      size: 18, color: AppColors.text3),
                ),
              ),
              const SizedBox(height: 6),
              Text('You decide. Minimum 2 members.',
                  style: GoogleFonts.hankenGrotesk(fontSize: 10.5,
                      color: AppColors.text3,
                      fontStyle: FontStyle.italic)),
              const SizedBox(height: 14),
              // Frequency
              Align(alignment: Alignment.centerLeft,
                  child: Text('Contribution Frequency',
                      style: GoogleFonts.hankenGrotesk(fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text2))),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: freqs.map((f) => GestureDetector(
                onTap: () => set(() => freq = f),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: freq == f
                        ? AppColors.primary : AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: freq == f
                        ? AppColors.primary : AppColors.border2)),
                  child: Text(f, style: GoogleFonts.hankenGrotesk(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: freq == f
                          ? const Color(0xFF040C10)
                          : AppColors.text2)),
                ),
              )).toList()),
              if (freq == 'Custom') ...[
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(
                    controller: customDaysCtrl,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 14, color: AppColors.text1,
                        fontWeight: FontWeight.w700),
                    onChanged: (v) {
                      final n = int.tryParse(v) ?? 0;
                      if (n > 0) customDays = n;
                    },
                    decoration: InputDecoration(
                      hintText: 'Number of days',
                      prefixIcon: const Icon(Icons.schedule_rounded,
                          size: 18, color: AppColors.primary),
                    ),
                  )),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.primaryDim,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primaryMid),
                    ),
                    child: Text('days', style: GoogleFonts.hankenGrotesk(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('e.g. 5 days = pay every 5 days',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 10.5, color: AppColors.text3,
                        fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 14),
              // Start date with calendar
              Align(alignment: Alignment.centerLeft,
                  child: Text('Start Date',
                      style: GoogleFonts.hankenGrotesk(fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text2))),
              const SizedBox(height: 7),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: startDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                    builder: (ctx, child) => Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: ColorScheme.dark(
                          primary: AppColors.primary,
                          onPrimary: const Color(0xFFFFFFFF),
                          surface: AppColors.surface2,
                          onSurface: AppColors.text1,
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) set(() => startDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border2),
                  ),
                  child: Row(children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 18, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(
                      _formatDate(startDate),
                      style: GoogleFonts.hankenGrotesk(fontSize: 14,
                          color: AppColors.text1,
                          fontWeight: FontWeight.w600))),
                    Text('Tap to change',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 11, color: AppColors.text3)),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              Text('First contribution cycle starts on this date',
                  style: GoogleFonts.hankenGrotesk(fontSize: 10.5,
                      color: AppColors.text3,
                      fontStyle: FontStyle.italic)),
              const SizedBox(height: 18),
              // Auto rotation info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primaryMid),
                ),
                child: Row(children: [
                  const Icon(Icons.auto_awesome_rounded,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    'Payout order is auto-assigned based on join order. Members are paid one per cycle.',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 11.5, color: AppColors.text2,
                        height: 1.4))),
                ]),
              ),
              const SizedBox(height: 22),
              NkapButton(
                label: creating ? 'Creating...' : 'Create Group',
                icon: Icons.check_rounded,
                onTap: creating ? null : () async {
                  if (nameCtrl.text.isEmpty ||
                      amountCtrl.text.isEmpty ||
                      maxCtrl.text.isEmpty) return;
                  final mm = int.tryParse(maxCtrl.text) ?? 0;
                  if (mm < 2) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Minimum 2 members required',
                          style: GoogleFonts.hankenGrotesk(
                              fontWeight: FontWeight.w600)),
                      backgroundColor: AppColors.danger,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ));
                    return;
                  }
                  set(() => creating = true);
                  try {
                    final actualFreq = freq == 'Custom' 
                        ? 'Every ${customDays} days' : freq;
                    final res = await ApiService.createNjangiGroup(
                      name: nameCtrl.text.trim(),
                      contribution: double.parse(amountCtrl.text.trim()),
                      frequency: actualFreq,
                      maxMembers: mm,
                      description: descCtrl.text.trim().isEmpty 
                          ? null : descCtrl.text.trim(),
                      startDate: startDate.toIso8601String(),
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      _load();
                      _showInviteCode(res['invite_code']);
                    }
                  } catch (e) { set(() => creating = false); }
                },
              ),
            ]),
          ),
        ),
      )),
    );
  }

  String _formatDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }



  void _showJoinSheet() {
    final codeCtrl = TextEditingController();
    bool joining = false;
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, set) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration:  BoxDecoration(color: AppColors.surface1,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _handle(),
            const SizedBox(height: 20),
            const Text('🔑', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 10),
            Text('Join a Group', style: GoogleFonts.hankenGrotesk(
                fontSize: 18, fontWeight: FontWeight.w800,
                color: AppColors.text1)),
            const SizedBox(height: 6),
            Text('Enter the 6-character invite code',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 13, color: AppColors.text2)),
            const SizedBox(height: 24),
            TextField(
              controller: codeCtrl,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: GoogleFonts.hankenGrotesk(fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary, letterSpacing: 8),
              maxLength: 6,
              decoration: InputDecoration(
                hintText: 'ABC123',
                hintStyle: GoogleFonts.hankenGrotesk(fontSize: 24,
                    color: AppColors.border2, letterSpacing: 8),
                counterText: '',
              ),
            ),
            const SizedBox(height: 24),
            NkapButton(
              label: joining ? 'Joining...' : 'Join Group',
              icon: Icons.group_add_rounded,
              onTap: joining ? null : () async {
                if (codeCtrl.text.trim().length != 6) return;
                set(() => joining = true);
                try {
                  // First preview the group
                  final preview = await ApiService.previewGroup(
                      codeCtrl.text.trim().toUpperCase());
                  if (!mounted) return;
                  Navigator.pop(context);
                  // Show preview dialog
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => _GroupPreviewDialog(group: preview),
                  );
                  if (confirmed != true) return;
                  // User confirmed, now join
                  final res = await ApiService.joinNjangiGroup(
                      codeCtrl.text.trim().toUpperCase());
                  if (mounted) {
                    _load();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Joined "${res["group_name"]}" successfully!',
                          style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
                      backgroundColor: AppColors.primary.withOpacity(0.9),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ));
                  }
                } catch (e) { set(() => joining = false); }
              },
            ),
          ]),
        ),
      )),
    );
  }

  void _showInviteCode(String code) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Group Created!', style: GoogleFonts.hankenGrotesk(
          color: AppColors.text1, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Share this code with your members:',
            style: GoogleFonts.hankenGrotesk(
                color: AppColors.text2, fontSize: 13)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
              color: AppColors.primaryDim,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primaryMid)),
          child: Text(code, style: GoogleFonts.hankenGrotesk(
              fontSize: 32, fontWeight: FontWeight.w800,
              color: AppColors.primary, letterSpacing: 8)),
        ),
      ]),
      actions: [TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('Done', style: GoogleFonts.hankenGrotesk(
            color: AppColors.primary, fontWeight: FontWeight.w700)),
      )],
    ));
  }

  Widget _buildSkeleton() => Shimmer.fromColors(
    baseColor: AppColors.surface2, highlightColor: AppColors.surface3,
    child: SingleChildScrollView(padding: const EdgeInsets.all(16),
        child: Column(children: [
      const SizedBox(height: 60),
      Container(height: 120, decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(22))),
      const SizedBox(height: 14),
      ...List.generate(2, (_) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(height: 160, decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(20))))),
    ])),
  );

  Widget _handle() => Center(child: Container(width: 40, height: 4,
      decoration: BoxDecoration(color: AppColors.border2,
          borderRadius: BorderRadius.circular(99))));

  Widget _field(TextEditingController c, String label, String hint,
      IconData icon, [TextInputType? type]) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.hankenGrotesk(fontSize: 12,
          fontWeight: FontWeight.w700, color: AppColors.text2)),
      const SizedBox(height: 7),
      TextField(controller: c, keyboardType: type,
          style: GoogleFonts.hankenGrotesk(fontSize: 14, color: AppColors.text1),
          decoration: InputDecoration(hintText: hint,
              prefixIcon: Icon(icon, size: 18, color: AppColors.text3))),
    ]);
}

// ═══════════════════════════════════════════════════════════════
// GROUP DETAIL VIEW
// ═══════════════════════════════════════════════════════════════
class _GroupDetail extends StatefulWidget {
  final Map<String, dynamic> group;
  final VoidCallback onBack, onRefresh;
  const _GroupDetail({
      required this.group,
      required this.onBack,
      required this.onRefresh});
  @override State<_GroupDetail> createState() => _GroupDetailState();
}

class _GroupDetailState extends State<_GroupDetail> {
  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    // Every read below tolerates a missing field. The detail page is opened
    // with whatever data the card list held, which can be sparser than a
    // freshly-fetched group payload — an unguarded `as num` on a missing
    // score blanks the whole route.
    final List members = (g['members'] as List?) ?? const [];
    final isMyTurn  = (g['is_my_turn'] ?? false) as bool;
    final trust     = ((g['my_trust_score'] ?? 0) as num).toDouble();
    final pool      = ((g['pool_amount']     ?? 0) as num).toDouble();
    final contrib   = ((g['contribution']    ?? 0) as num).toDouble();
    final cycle     = (g['current_cycle']    ?? 1) as int;
    final total     = (g['total_cycles']     ?? 1) as int;
    final pct       = ((g['progress_pct']    ?? 0) as num).toDouble() / 100;
    final paidCount =
        members.where((m) => (m['has_paid'] ?? false) as bool).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(slivers: [
        SliverAppBar(
          backgroundColor: AppColors.surface1, elevation: 0,
          pinned: true, toolbarHeight: 56,
          leading: IconButton(
              icon:  Icon(Icons.arrow_back_rounded,
                  color: AppColors.text1),
              onPressed: widget.onBack),
          title: Text((g['name'] ?? '').toString(), style: GoogleFonts.hankenGrotesk(
              color: AppColors.text1,
              fontWeight: FontWeight.w800, fontSize: 17)),
          // Three primary actions live at the top-right so the body
          // isn't crowded with action rows: notifications, share, and
          // an overflow menu that holds everything else (manage, rules,
          // history, leave/delete). Tapping any of them opens its sheet
          // or popup directly — no nested navigation.
          actions: [
            IconButton(
              tooltip: 'Group chat',
              icon: Icon(Icons.chat_bubble_outline_rounded,
                  color: AppColors.text1, size: 20),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => GroupChatScreen(
                  groupId: g['id'].toString(),
                  groupName: (g['name'] ?? 'Group').toString(),
                ),
              )),
            ),
            IconButton(
              tooltip: 'Notifications',
              icon: Icon(Icons.notifications_none_rounded,
                  color: AppColors.text1, size: 22),
              onPressed: () => _showNotificationsSheet(g),
            ),
            IconButton(
              tooltip: 'Share group',
              icon: Icon(Icons.ios_share_rounded,
                  color: AppColors.text1, size: 20),
              onPressed: () => _showInviteSheet(
                  g, (g['members'] as List?)?.length ?? 0),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: Icon(Icons.more_vert_rounded,
                  color: AppColors.text1, size: 22),
              color: AppColors.surface2,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: AppColors.border1)),
              onSelected: (key) => _onMoreSelected(key, g),
              itemBuilder: (_) => [
                if (g['is_admin'] == true)
                  _moreItem('manage', Icons.tune_rounded,
                      'Manage group', AppColors.primary),
                _moreItem('history', Icons.history_rounded,
                    'Payment history', AppColors.info),
                _moreItem('rules', Icons.gavel_rounded,
                    'Group rules', AppColors.purple),
                _moreItem('qr', Icons.qr_code_rounded,
                    'Show QR code', AppColors.primary),
                if (g['is_admin'] != true)
                  _moreItem('leave', Icons.logout_rounded,
                      'Leave group', AppColors.danger),
                if (g['is_admin'] == true)
                  _moreItem('delete', Icons.delete_outline_rounded,
                      'Delete group', AppColors.danger),
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── 1. STATUS BANNER ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  // Active groups use the brand-tinted hero; other states
                  // get the navy hero so completed/upcoming reads cooler.
                  colors: g['status'] == 'active'
                      ? AppColors.heroBrandGradient
                      : AppColors.heroNavyGradient,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: g['status'] == 'active'
                    ? AppColors.primary.withOpacity(0.3)
                    : AppColors.accent.withOpacity(0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: g['status'] == 'active'
                          ? AppColors.primary.withOpacity(0.2)
                          : AppColors.accent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 6, height: 6,
                          decoration: BoxDecoration(shape: BoxShape.circle,
                              color: g['status'] == 'active'
                                  ? AppColors.primary
                                  : AppColors.accent)),
                      const SizedBox(width: 6),
                      Text(g['status'].toString().toUpperCase(),
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 10, fontWeight: FontWeight.w800,
                              color: g['status'] == 'active'
                                  ? AppColors.primary
                                  : AppColors.accent,
                              letterSpacing: 0.5)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  // Trust score chip — moved here from the old Quick Stats
                  // row so the banner carries every "header" fact in one
                  // glance.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.heroFg.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.shield_outlined,
                          color: AppColors.heroFg, size: 11),
                      const SizedBox(width: 5),
                      Text('Trust ${trust.toStringAsFixed(0)}%',
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 10, fontWeight: FontWeight.w800,
                              color: AppColors.heroFg, letterSpacing: 0.3)),
                    ]),
                  ),
                  const Spacer(),
                  if (isMyTurn && g['status'] == 'active')
                    const Text('🎉', style: TextStyle(fontSize: 20)),
                ]),
                const SizedBox(height: 14),
                Text('Total Pot',
                    style: GoogleFonts.hankenGrotesk(
                        color: AppColors.heroFgDim,
                        fontSize: 11, letterSpacing: 1.2)),
                const SizedBox(height: 4),
                Text('${_fmt(pool)} FCFA',
                    style: GoogleFonts.hankenGrotesk(
                        color: AppColors.heroFg, fontSize: 28,
                        fontWeight: FontWeight.w800, letterSpacing: -1)),
                const SizedBox(height: 4),
                // Contribution · frequency · cycle paid — keeps the
                // frequency visible after Quick Stats was removed.
                Text(
                    '${_fmt(contrib)} FCFA · '
                    '${(g['frequency'] ?? '–').toString()} · '
                    '$paidCount/${members.length} paid this cycle',
                    style: GoogleFonts.hankenGrotesk(
                        color: AppColors.heroFgMuted, fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 14),

            // ── 2. INVITE + PAYMENT SCHEDULE TILES ──
            // The two main pieces of group info kept inline (everything
            // else now lives in the three top-right AppBar buttons).
            Row(children: [
              Expanded(child: _squareTile(
                icon: Icons.person_add_alt_1_rounded,
                tint: AppColors.primary,
                tintDim: AppColors.primaryDim,
                tintMid: AppColors.primaryMid,
                title: 'Invite Members',
                subtitle: '${members.length}/${g['max_members']} joined',
                onTap: () => _showInviteSheet(g, members.length),
              )),
              const SizedBox(width: 10),
              Expanded(child: _squareTile(
                icon: Icons.event_repeat_rounded,
                tint: AppColors.accent,
                tintDim: AppColors.accentDim,
                tintMid: AppColors.accentMid,
                title: 'Payment Schedule',
                subtitle: g['status'] == 'active'
                    ? 'Cycle $cycle of $total'
                    : 'Starts when active',
                onTap: members.isEmpty ? null : () =>
                    _showPaymentScheduleSheet(g, members, cycle, contrib),
              )),
            ]),
            const SizedBox(height: 18),

            // ── 3. CYCLE PROGRESS BAR ──
            // Slim at-a-glance bar. Cycle number now lives in the
            // Payment Schedule tile subtitle above, and "currently
            // receiving" is shown inside that tile's sheet — both
            // removed from here to kill duplication.
            if (g['status'] == 'active') ...[
              NkapCard(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Cycle progress', style: GoogleFonts.hankenGrotesk(
                    fontWeight: FontWeight.w700, fontSize: 12.5,
                    color: AppColors.text2)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                      value: pct, minHeight: 8,
                      backgroundColor: AppColors.border1,
                      valueColor: const AlwaysStoppedAnimation(
                          AppColors.primary)),
                ),
              ])),
              const SizedBox(height: 14),
            ],

            // ── 4. MEMBERS LIST ──
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10, top: 4),
              child: Row(children: [
                Text('Members', style: GoogleFonts.hankenGrotesk(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: AppColors.text1)),
                const SizedBox(width: 6),
                Text('· ${members.length}', style: GoogleFonts.hankenGrotesk(
                    fontSize: 12, color: AppColors.text3)),
              ]),
            ),
            NkapCard(child: Column(
              children: members.asMap().entries.map<Widget>((e) {
                final m = e.value;
                final isMe = (m['is_me'] ?? false) as bool;
                final paid = (m['has_paid'] ?? false) as bool;
                final pos = (m['position'] ?? 0) as int;
                final isCurrent = pos == cycle && g['status'] == 'active';
                final color = _memberColors[e.key % _memberColors.length];
                final last = e.key == members.length - 1;
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(children: [
                      Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isMe
                              ? AppColors.primaryDim
                              : isCurrent
                                  ? AppColors.accentDim
                                  : AppColors.surface3,
                          border: Border.all(
                              color: isMe
                                  ? AppColors.primary
                                  : isCurrent
                                      ? AppColors.accent
                                      : Colors.transparent),
                        ),
                        child: Center(child: Text('$pos',
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isMe
                                    ? AppColors.primary
                                    : isCurrent
                                        ? AppColors.accent
                                        : AppColors.text3))),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () {
                          if (m['user_id'] != null) {
                            Navigator.push(context, MaterialPageRoute(
                                builder: (_) => MemberProfileView(
                                    userId: m['user_id'])));
                          }
                        },
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color.withOpacity(0.18),
                              border: Border.all(color: color.withOpacity(0.35))),
                          clipBehavior: Clip.antiAlias,
                          child: m['profile_picture'] != null &&
                                 m['profile_picture'].toString().isNotEmpty
                              ? Image.network(
                                  ApiService.pictureUrl(m['profile_picture']),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Center(
                                      child: Text(
                                    m['name'].toString().substring(0, 1).toUpperCase(),
                                    style: TextStyle(fontSize: 14,
                                        fontWeight: FontWeight.w800, color: color))),
                                )
                              : Center(child: Text(
                                  m['name'].toString().substring(0, 1).toUpperCase(),
                                  style: TextStyle(fontSize: 14,
                                      fontWeight: FontWeight.w800, color: color))),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Flexible(child: Text(m['name'],
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.hankenGrotesk(
                                  fontWeight: isMe
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontSize: 13,
                                  color: isMe
                                      ? AppColors.primary
                                      : AppColors.text1))),
                          if (m['is_admin'] == true) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.purple.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: AppColors.purple.withOpacity(0.4)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min,
                                  children: [
                                const Icon(Icons.shield_rounded,
                                    size: 10, color: AppColors.purple),
                                const SizedBox(width: 3),
                                Text('ADMIN',
                                    style: GoogleFonts.hankenGrotesk(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.purple,
                                        letterSpacing: 0.5)),
                              ]),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 2),
                        Text('Trust: ${(m["trust_score"] as num).toStringAsFixed(0)}%',
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 10, color: AppColors.text3)),
                      ])),
                      if (paid)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: AppColors.primaryDim,
                              borderRadius: BorderRadius.circular(8)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.check_rounded,
                                color: AppColors.primary, size: 11),
                            const SizedBox(width: 3),
                            Text('Paid', style: GoogleFonts.hankenGrotesk(
                                fontSize: 10, fontWeight: FontWeight.w700,
                                color: AppColors.primary)),
                          ]),
                        )
                      else if (isCurrent)
                        NkapChip(label: 'Receiving',
                            color: AppColors.accent,
                            dimColor: AppColors.accentDim)
                      else
                        Text('Pending', style: GoogleFonts.hankenGrotesk(
                            fontSize: 10, color: AppColors.text3)),
                    ]),
                  ),
                  if (!last) Divider(
                      height: 1, color: AppColors.border1),
                ]);
              }).toList(),
            )),
            const SizedBox(height: 20),

            // ── 5. PAY BUTTON ──
            if (g['status'] == 'active') ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
                child: Text('Make Payment',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: AppColors.text1)),
              ),
              GestureDetector(
              onTap: () => _showPaymentSheet(g, contrib),
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [AppColors.primary, AppColors.magenta]),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(
                      color: AppColors.primary.withOpacity(0.4),
                      blurRadius: 24, offset: const Offset(0, 8))],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.payments_rounded,
                        color: Color(0xFFFFFFFF), size: 22),
                    const SizedBox(width: 10),
                    Text('Pay ${_fmt(contrib)} FCFA',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 15, fontWeight: FontWeight.w800,
                            color: const Color(0xFFFFFFFF))),
                  ],
                ),
              ),
              ),
              const SizedBox(height: 8),
              Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                 Icon(Icons.security_rounded,
                    size: 11, color: AppColors.text3),
                const SizedBox(width: 4),
                Text('Secured by MTN & Orange Mobile Money',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 10, color: AppColors.text3)),
              ])),
            ],
            const SizedBox(height: 24),

          ]),
        )),
      ]),
    );
  }

  void _showGroupQR(Map<String, dynamic> g) {
    final qr = 'NKAPSAVE:' + g['invite_code'] + ':' + g['contribution'].toString();
    showDialog(context: context, builder: (_) => Dialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Group QR Code', style: GoogleFonts.hankenGrotesk(
              fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text1)),
          const SizedBox(height: 6),
          Text('Members can scan to pay instantly',
              style: GoogleFonts.hankenGrotesk(fontSize: 12, color: AppColors.text3)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18)),
            child: QrImageView(
                data: qr, version: QrVersions.auto,
                size: 200, backgroundColor: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(g['invite_code'], style: GoogleFonts.hankenGrotesk(
              fontSize: 24, fontWeight: FontWeight.w800,
              color: AppColors.primary, letterSpacing: 6)),
        ]),
      ),
    ));
  }

  void _showPaymentSheet(Map<String, dynamic> g, double amount) {
    String? operator;
    final phoneCtrl = TextEditingController();
    String? phoneError;
    final trust = ((g['my_trust_score'] ?? 100) as num).toDouble();
    final cycle = (g['current_cycle'] ?? 1) as int;
    final total = (g['total_cycles'] ?? 1) as int;
    final dueDate = g['next_cycle_date'] ?? 'Today';
    
    // Calculate escrow split based on trust
    final immediatePct = (trust / 100 * 100).clamp(50, 100).toInt();
    final escrowPct = 100 - immediatePct;

    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
          decoration:  BoxDecoration(color: AppColors.surface1,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            child: Column(mainAxisSize: MainAxisSize.min, 
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Drag handle ──
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: AppColors.border2,
                      borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 18),
              
              // ── Title ──
              Center(child: Text('Pay Contribution', style: GoogleFonts.hankenGrotesk(
                  fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text1))),
              const SizedBox(height: 4),
              Center(child: Text(g['name'] ?? '', style: GoogleFonts.hankenGrotesk(
                  fontSize: 12, color: AppColors.text3))),
              const SizedBox(height: 16),
              
              // ── Cycle & Due Date Banner ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border1),
                ),
                child: Row(children: [
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('CYCLE', style: GoogleFonts.hankenGrotesk(
                        fontSize: 9, color: AppColors.text3, letterSpacing: 1)),
                    const SizedBox(height: 3),
                    Text('$cycle of $total', style: GoogleFonts.hankenGrotesk(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        color: AppColors.text1)),
                  ])),
                  Container(width: 1, height: 28, color: AppColors.border1),
                  Expanded(child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('DUE DATE', style: GoogleFonts.hankenGrotesk(
                          fontSize: 9, color: AppColors.text3, letterSpacing: 1)),
                      const SizedBox(height: 3),
                      Text(dueDate, style: GoogleFonts.hankenGrotesk(
                          fontSize: 14, fontWeight: FontWeight.w800,
                          color: AppColors.text1)),
                    ]),
                  )),
                  Container(width: 1, height: 28, color: AppColors.border1),
                  Expanded(child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('TRUST', style: GoogleFonts.hankenGrotesk(
                          fontSize: 9, color: AppColors.text3, letterSpacing: 1)),
                      const SizedBox(height: 3),
                      Text('${trust.toStringAsFixed(0)}%', style: GoogleFonts.hankenGrotesk(
                          fontSize: 14, fontWeight: FontWeight.w800,
                          color: trust >= 80 ? AppColors.primary : AppColors.accent)),
                    ]),
                  )),
                ]),
              ),
              const SizedBox(height: 14),
              
              // ── Amount Card ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    AppColors.primary.withOpacity(0.18),
                    AppColors.primary.withOpacity(0.06)]),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.primaryMid)),
                child: Column(children: [
                  Text('AMOUNT TO PAY', style: GoogleFonts.hankenGrotesk(
                      fontSize: 10, color: AppColors.text3, letterSpacing: 1.5)),
                  const SizedBox(height: 4),
                  Text('${_fmt(amount)} FCFA', style: GoogleFonts.hankenGrotesk(
                      fontSize: 30, fontWeight: FontWeight.w800,
                      color: AppColors.primary, letterSpacing: -0.5, height: 1.1)),
                ]),
              ),
              const SizedBox(height: 16),
              
              // ── Escrow Notice ──
              if (escrowPct > 0) Container(
                padding: const EdgeInsets.all(11),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppColors.accent.withOpacity(0.3))),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 16, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'When you win, ${immediatePct}% sent immediately, ${escrowPct}% held in escrow until trust improves.',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 11, color: AppColors.text2, height: 1.3))),
                ]),
              ),
              if (escrowPct == 0) Container(
                padding: const EdgeInsets.all(11),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: AppColors.primaryMid)),
                child: Row(children: [
                  const Icon(Icons.shield_rounded,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'Trust 100% — when you win, full payout sent immediately. No escrow.',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 11, color: AppColors.text2, height: 1.3))),
                ]),
              ),
              
              // ── Choose Operator ──
              Text('Select Payment Method', style: GoogleFonts.hankenGrotesk(
                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text2)),
              const SizedBox(height: 10),
              _OperatorCard(
                selected: operator == 'MTN', brand: 'MTN',
                brandColor: _Brand.mtnYellow, brandText: _Brand.mtnDark,
                title: 'MTN Mobile Money', subtitle: '*126#',
                onTap: () => setSheet(() { operator = 'MTN'; phoneError = null; }),
              ),
              const SizedBox(height: 10),
              _OperatorCard(
                selected: operator == 'Orange', brand: 'Orange',
                brandColor: _Brand.orangeRed, brandText: Colors.white,
                title: 'Orange Money', subtitle: '#150*4#',
                onTap: () => setSheet(() { operator = 'Orange'; phoneError = null; }),
              ),
              
              // ── Phone Input ──
              if (operator != null) ...[
                const SizedBox(height: 18),
                Text('Phone Number', style: GoogleFonts.hankenGrotesk(
                    fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text2)),
                const SizedBox(height: 7),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  maxLength: 11,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 17, color: AppColors.text1, letterSpacing: 1.2,
                      fontWeight: FontWeight.w600),
                  onChanged: (v) {
                    final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
                    final detected = _detectOperator(digits);
                    setSheet(() {
                      if (detected != null && detected != operator) {
                        operator = detected;
                      }
                      phoneError = null;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: '6XX XXX XXX',
                    counterText: '',
                    errorText: phoneError,
                    prefixIcon: Container(
                      margin: const EdgeInsets.only(left: 12, right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface3,
                        borderRadius: BorderRadius.circular(8)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text('🇨🇲', style: TextStyle(fontSize: 14)),
                        const SizedBox(width: 4),
                        Text('+237', style: GoogleFonts.hankenGrotesk(
                            fontSize: 13, color: AppColors.text2,
                            fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 90, minHeight: 30),
                  ),
                ),
                const SizedBox(height: 4),
                Text('Must be a 9-digit number starting with 6',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 10, color: AppColors.text3,
                        fontStyle: FontStyle.italic)),
                const SizedBox(height: 18),
                
                // ── Confirm Button ──
                NkapButton(
                  label: 'Confirm Payment · ${_fmt(amount)} FCFA',
                  icon: Icons.check_rounded,
                  onTap: () {
                    final digits = phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
                    if (digits.length != 9) {
                      setSheet(() => phoneError = 'Enter 9 digits');
                      return;
                    }
                    if (!digits.startsWith('6')) {
                      setSheet(() => phoneError = 'Number must start with 6');
                      return;
                    }
                    final detected = _detectOperator(digits);
                    if (detected != null && detected != operator) {
                      setSheet(() => phoneError = 
                          'This is a $detected number, not $operator');
                      return;
                    }
                    Navigator.pop(context);
                    _showUSSDFlow(g, amount, operator!, digits, cycle);
                  },
                ),
                const SizedBox(height: 8),
                Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                   Icon(Icons.lock_rounded, size: 11, color: AppColors.text3),
                  const SizedBox(width: 4),
                  Text('Encrypted · Secured by ${operator!} Mobile Money',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 10, color: AppColors.text3)),
                ])),
              ],
            ]),
          ),
        ),
      )),
    );
  }

  void _showUSSDFlow(Map<String, dynamic> g, double amount,
      String operator, String phone, int cycle) {
    showDialog(context: context, barrierDismissible: false,
        builder: (ctx) => _USSDDialog(
          group: g, amount: amount, operator: operator,
          phone: phone, cycle: cycle,
          onSuccess: () async {
            Navigator.pop(ctx);
            // Generate transaction reference
            final txRef = 'NKP' + DateTime.now().millisecondsSinceEpoch
                .toString().substring(7);
            try {
              await ApiService.contributeNjangi(g['id']);
              if (mounted) {
                showDialog(context: context, barrierDismissible: false,
                    builder: (ctx2) => _SuccessDialog(
                      amount: amount,
                      groupName: g['name'] ?? '',
                      operator: operator,
                      phone: phone,
                      txRef: txRef,
                      onClose: () { 
                        Navigator.pop(ctx2); 
                        widget.onRefresh();
                        // Show post-payment notification
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Row(children: [
                            const Icon(Icons.check_circle_rounded,
                                color: Color(0xFFFFFFFF), size: 18),
                            const SizedBox(width: 8),
                            Expanded(child: Text(
                              'Payment confirmed! Trust score +2',
                              style: GoogleFonts.hankenGrotesk(
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFFFFFFF)))),
                          ]),
                          backgroundColor: AppColors.primary,
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 4),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ));
                      },
                    ));
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Payment failed - try again',
                      style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
                  backgroundColor: AppColors.danger,
                ));
              }
            }
          },
        ));
  }

  // ── MANAGE SHEET ──────────────────────────────────────────────
  /// Admin actions for the group: activate (if pending), adjust max
  /// members, and delete. Replaces the old inline "Activate Group"
  /// button and "Adjust" pill so all admin controls live in one place.
  void _showManageSheet(Map<String, dynamic> g) {
    final isPending = g['status'] == 'pending';
    final isActive  = g['status'] == 'active';
    final isPaused  = g['status'] == 'paused';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _sheetShell(
        title: 'Manage group',
        subtitle: 'Admin actions for "${g['name'] ?? ''}"',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (isPending) _sheetAction(
            icon: Icons.play_arrow_rounded,
            label: 'Activate group',
            hint: 'Start the first cycle. Needs at least 2 members.',
            color: AppColors.primary,
            onTap: () {
              Navigator.of(ctx).pop();
              _activate(g);
            },
          ),
          if (!isPending) _sheetAction(
            icon: Icons.edit_outlined,
            label: 'Rename group',
            hint: 'Change the displayed group name and description.',
            color: AppColors.text2,
            onTap: () {
              Navigator.of(ctx).pop();
              _showRenameSheet(g);
            },
          ),
          _sheetAction(
            icon: Icons.tune_rounded,
            label: 'Adjust max members',
            hint: 'Change the seat count. New seats become joinable.',
            color: AppColors.primary,
            onTap: () {
              Navigator.of(ctx).pop();
              _showMaxMembersSheet(g);
            },
          ),
          if (isActive) _sheetAction(
            icon: Icons.pause_circle_outline_rounded,
            label: 'Pause cycles',
            hint: 'Members keep their seats; payments halt until resumed.',
            color: AppColors.accent,
            onTap: () {
              Navigator.of(ctx).pop();
              _togglePause(g);
            },
          ),
          if (isPaused) _sheetAction(
            icon: Icons.play_circle_outline_rounded,
            label: 'Resume cycles',
            hint: 'Restart payments from where you paused.',
            color: AppColors.primary,
            onTap: () {
              Navigator.of(ctx).pop();
              _togglePause(g);
            },
          ),
          _sheetAction(
            icon: Icons.delete_outline_rounded,
            label: 'Delete group',
            hint: 'Removes the group for every member. Cannot be undone.',
            color: AppColors.danger,
            onTap: () async {
              Navigator.of(ctx).pop();
              await _deleteGroup(g);
            },
          ),
        ]),
      ),
    );
  }

  /// Bottom sheet for editing the group name + description. Both fields
  /// are sent in one PATCH so a partial save still lands cleanly.
  void _showRenameSheet(Map<String, dynamic> g) {
    final nameCtrl = TextEditingController(text: (g['name'] ?? '').toString());
    final descCtrl = TextEditingController(
        text: (g['description'] ?? '').toString());
    bool saving = false;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _sheetShell(
          title: 'Rename group',
          subtitle: 'Visible to every member of the group.',
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 4),
            TextField(
              controller: nameCtrl,
              maxLength: 100,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 13, color: AppColors.text1),
              decoration: InputDecoration(
                labelText: 'Group name',
                labelStyle: GoogleFonts.hankenGrotesk(color: AppColors.text2),
                filled: true,
                fillColor: AppColors.surface2,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border1)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border1)),
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: descCtrl,
              maxLength: 500,
              maxLines: 3,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 13, color: AppColors.text1),
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                labelStyle: GoogleFonts.hankenGrotesk(color: AppColors.text2),
                filled: true,
                fillColor: AppColors.surface2,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border1)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border1)),
              ),
            ),
            const SizedBox(height: 8),
            NkapButton(
              label: saving ? 'Saving…' : 'Save changes',
              icon: Icons.check_rounded,
              onTap: saving ? null : () async {
                set(() => saving = true);
                try {
                  final res = await ApiService.updateNjangiGroup(
                      g['id'],
                      name: nameCtrl.text.trim(),
                      description: descCtrl.text.trim());
                  if (!mounted) return;
                  // Mirror server values locally so the AppBar title and
                  // banner update before the next refresh fires.
                  setState(() {
                    widget.group['name']        = res['name'] ?? nameCtrl.text;
                    widget.group['description'] = res['description'];
                  });
                  Navigator.of(ctx).pop();
                  widget.onRefresh();
                  _snack('Group renamed');
                } catch (e) {
                  set(() => saving = false);
                  _snack(_pretty(e, 'Couldn\'t rename group'));
                }
              },
            ),
          ]),
        ),
      )),
    );
  }

  /// Toggles active ↔ paused via the backend, then refreshes the list
  /// so the dashboard re-renders with the new status.
  Future<void> _togglePause(Map<String, dynamic> g) async {
    try {
      final res = await ApiService.togglePauseNjangiGroup(g['id']);
      if (!mounted) return;
      setState(() => widget.group['status'] = res['status']);
      widget.onRefresh();
      _snack(res['status'] == 'paused'
          ? 'Group paused. Cycles will resume when you tap Resume.'
          : 'Group resumed.');
    } catch (e) {
      if (!mounted) return;
      _snack(_pretty(e, 'Couldn\'t change group status'));
    }
  }

  /// Admin-only delete. Confirms first, then calls the server and
  /// returns to the group list on success.
  Future<void> _deleteGroup(Map<String, dynamic> g) async {
    final yes = await _confirm(
      title: 'Delete this group?',
      message: 'Every member will lose access. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!yes || !mounted) return;
    try {
      await ApiService.deleteNjangiGroup(g['id']);
      if (!mounted) return;
      widget.onRefresh();  // pops back to the group list AND reloads.
      _snack('Group deleted');
    } catch (e) {
      if (!mounted) return;
      _snack(_pretty(e, 'Couldn\'t delete group'));
    }
  }

  /// Pull a friendly message out of a Dio error (the backend sends a
  /// JSON `{detail: …}` body for every 4xx/5xx).
  String _pretty(Object e, String fallback) {
    try {
      final dynamic d = e;
      final data = d.response?.data;
      if (data is Map && data['detail'] is String) return data['detail'];
    } catch (_) {}
    return fallback;
  }

  // ── NOTIFICATIONS SHEET ───────────────────────────────────────
  /// Per-group notification preferences. State is persisted via
  /// [UserPreferences.setNjangiNotif] (local SharedPreferences) so the
  /// next time the sheet opens it shows what the user previously chose.
  /// All toggles default to ON for groups the user hasn't touched yet.
  void _showNotificationsSheet(Map<String, dynamic> g) {
    final groupId = g['id'].toString();
    final saved   = UserPreferences.instance.njangiNotifs(groupId);
    bool paymentReminders = saved['payment_reminders'] ?? true;
    bool memberJoined     = saved['member_joined']     ?? true;
    bool cycleAdvanced    = saved['cycle_advanced']    ?? true;

    Future<void> persist(String key, bool value) =>
        UserPreferences.instance.setNjangiNotif(groupId, key, value);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) => _sheetShell(
        title: 'Notifications',
        subtitle: 'Choose what this group can ping you about.',
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _sheetToggle(
            icon: Icons.alarm_rounded,
            label: 'Payment reminders',
            hint: 'A day before your contribution is due.',
            value: paymentReminders,
            onChanged: (v) {
              set(() => paymentReminders = v);
              persist('payment_reminders', v);
            },
          ),
          _sheetToggle(
            icon: Icons.person_add_alt_rounded,
            label: 'New members joined',
            hint: 'Get notified when someone uses the invite code.',
            value: memberJoined,
            onChanged: (v) {
              set(() => memberJoined = v);
              persist('member_joined', v);
            },
          ),
          _sheetToggle(
            icon: Icons.event_repeat_rounded,
            label: 'Cycle advanced',
            hint: 'When a cycle closes and the next recipient is set.',
            value: cycleAdvanced,
            onChanged: (v) {
              set(() => cycleAdvanced = v);
              persist('cycle_advanced', v);
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Saved per group on this device. Mute the whole app from '
            'Profile → Notifications.',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 11, color: AppColors.text3, height: 1.45),
          ),
        ]),
      )),
    );
  }

  // ── TOP-RIGHT "MORE" POPUP ────────────────────────────────────
  /// Builds one entry for the AppBar's overflow popup menu. The visual
  /// is shared so every row has the same icon-chip + label rhythm.
  PopupMenuItem<String> _moreItem(
      String key, IconData icon, String label, Color color) {
    return PopupMenuItem<String>(
      value: key,
      child: Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Text(label, style: GoogleFonts.hankenGrotesk(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: AppColors.text1)),
      ]),
    );
  }

  /// Dispatches a tap on the top-right overflow menu to the right
  /// destination. Keeping the dispatch here means new entries only need
  /// a row in `itemBuilder` plus a `case` here — no plumbing changes.
  Future<void> _onMoreSelected(String key, Map<String, dynamic> g) async {
    switch (key) {
      case 'manage':
        _showManageSheet(g);
        break;
      case 'history':
        _showHistorySheet(g);
        break;
      case 'rules':
        _showGroupRules();
        break;
      case 'qr':
        _showGroupQR(g);
        break;
      case 'leave':
        final yes = await _confirm(
          title: 'Leave this group?',
          message: 'You may lose trust points if cycles are active. '
                   'Rejoining requires admin approval.',
          confirmLabel: 'Leave',
          destructive: true,
        );
        if (!yes || !mounted) return;
        try {
          await ApiService.leaveNjangiGroup(g['id']);
          if (!mounted) return;
          widget.onRefresh();
          _snack('You left the group');
        } catch (e) {
          if (!mounted) return;
          _snack(_pretty(e, 'Couldn\'t leave the group'));
        }
        break;
      case 'delete':
        await _deleteGroup(g);
        break;
    }
  }

  /// Static info bottom sheet explaining the Njangi rules of the road —
  /// contributions, trust, payouts, escrow. Same visual shell as the
  /// other action sheets so it feels native to the dashboard.
  void _showGroupRules() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scroll) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(children: [
            Center(child: Container(width: 40, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 6),
                decoration: BoxDecoration(
                    color: AppColors.border3,
                    borderRadius: BorderRadius.circular(99)))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(children: [
                Icon(Icons.gavel_rounded, color: AppColors.purple, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Group rules',
                    style: GoogleFonts.hankenGrotesk(
                        color: AppColors.text1, fontSize: 18,
                        fontWeight: FontWeight.w800))),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: AppColors.text2, size: 22),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ]),
            ),
            Expanded(child: SingleChildScrollView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _ruleH('1. Contributions'),
                _ruleP('Every member pays the same fixed contribution each '
                       'cycle (e.g. 5,000 FCFA weekly). The cycle starts '
                       'when the admin activates the group and at least '
                       'two members have joined.'),
                _ruleH('2. Rotation order'),
                _ruleP('Each member is assigned a position when they join. '
                       'Position 1 receives the pot in cycle 1, position 2 '
                       'in cycle 2, and so on. The order is visible in the '
                       'Payment Schedule.'),
                _ruleH('3. Trust score'),
                _ruleP('Your trust score starts at 100. It drops when you '
                       'miss a contribution and recovers as you pay on time. '
                       'A score below 80 caps your immediate payout — the '
                       'rest is held in escrow until your trust climbs back.'),
                _ruleH('4. Escrow'),
                _ruleP('The portion held in escrow is released on your next '
                       'on-time contribution. This protects the group from '
                       'a member taking their payout and ghosting.'),
                _ruleH('5. Leaving and removal'),
                _ruleP('You can leave between cycles. You cannot leave a '
                       'cycle where you\'ve already paid — wait for the '
                       'next cycle to start. Admins cannot leave; they must '
                       'transfer ownership or delete the group.'),
                _ruleH('6. Pause and delete'),
                _ruleP('The admin can pause cycles (no payments until '
                       'resumed) or delete the group entirely. Deletion is '
                       'blocked while other members are still active — pause '
                       'first and settle outstanding payouts before deleting.'),
              ]),
            )),
          ]),
        ),
      ),
    );
  }

  Widget _ruleH(String t) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(t, style: GoogleFonts.hankenGrotesk(
        color: AppColors.text1, fontSize: 14,
        fontWeight: FontWeight.w800)),
  );
  Widget _ruleP(String t) => Text(t,
      style: GoogleFonts.hankenGrotesk(
          color: AppColors.text2, fontSize: 13, height: 1.55));

  // ── PAYMENT HISTORY ──────────────────────────────────────────
  /// Full payment history for a group: every contribution + every
  /// payout, newest first. Pulled from `GET /njangi/groups/:id/history`.
  /// The sheet shows a loading shimmer while the request flies and
  /// renders a clear empty state for brand-new groups with no events.
  void _showHistorySheet(Map<String, dynamic> g) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scroll) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(children: [
            Center(child: Container(width: 40, height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 6),
                decoration: BoxDecoration(
                    color: AppColors.border3,
                    borderRadius: BorderRadius.circular(99)))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
              child: Row(children: [
                Icon(Icons.history_rounded, color: AppColors.info, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Payment history',
                    style: GoogleFonts.hankenGrotesk(
                        color: AppColors.text1, fontSize: 18,
                        fontWeight: FontWeight.w800))),
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      color: AppColors.text2, size: 22),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ]),
            ),
            Expanded(child: FutureBuilder<List<Map<String, dynamic>>>(
              future: ApiService.getNjangiHistory(g['id']),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 2.5));
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(
                        _pretty(snap.error!, "Couldn't load history"),
                        style: GoogleFonts.hankenGrotesk(color: AppColors.danger))),
                  );
                }
                final events = snap.data ?? [];
                if (events.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(child: Column(
                        mainAxisSize: MainAxisSize.min, children: [
                      const Text('📜', style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 12),
                      Text('No payments yet',
                          style: GoogleFonts.hankenGrotesk(
                              color: AppColors.text1, fontSize: 15,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                        'Contributions and payouts will appear here as '
                        'they happen.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.hankenGrotesk(
                            color: AppColors.text3, fontSize: 12)),
                    ])),
                  );
                }
                return ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  itemCount: events.length,
                  separatorBuilder: (_, __) => Divider(
                      color: AppColors.border1, height: 18),
                  itemBuilder: (_, i) => _historyTile(events[i]),
                );
              },
            )),
          ]),
        ),
      ),
    );
  }

  /// One row in the history feed. Payout rows are tinted (accent) and
  /// show the extra gross/escrow/trust detail; contribution rows are
  /// the standard green check style.
  Widget _historyTile(Map<String, dynamic> e) {
    final isPayout = e['type'] == 'payout';
    final color    = isPayout ? AppColors.accent : AppColors.primary;
    final colorDim = isPayout ? AppColors.accentDim : AppColors.primaryDim;
    final colorMid = isPayout ? AppColors.accentMid : AppColors.primaryMid;
    final actor    = (e['actor'] ?? 'Unknown').toString();
    final cycle    = (e['cycle'] ?? 0) as int;
    final amount   = ((e['amount'] ?? 0) as num).toDouble();
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: colorDim,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorMid),
        ),
        child: Icon(
            isPayout ? Icons.south_west_rounded : Icons.north_east_rounded,
            color: color, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isPayout ? 'Payout · Cycle $cycle' : 'Contribution · Cycle $cycle',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 13, fontWeight: FontWeight.w800,
                color: AppColors.text1)),
        const SizedBox(height: 2),
        Text(actor, style: GoogleFonts.hankenGrotesk(
            fontSize: 11.5, color: AppColors.text3)),
        if (isPayout && e['gross_amount'] != null) ...[
          const SizedBox(height: 2),
          Text(
              'Pool ${_fmt(((e['gross_amount'] ?? 0) as num).toDouble())} · '
              'Escrow ${_fmt(((e['escrow_amount'] ?? 0) as num).toDouble())} · '
              'Trust ${((e['trust_score'] ?? 0) as num).toStringAsFixed(0)}%',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 10.5, color: AppColors.text3)),
        ],
        const SizedBox(height: 2),
        Text(_fmtTime(e['created_at']?.toString()),
            style: GoogleFonts.hankenGrotesk(
                fontSize: 10.5, color: AppColors.text3)),
      ])),
      const SizedBox(width: 8),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${isPayout ? '+' : '−'}${_fmt(amount)}',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 14, fontWeight: FontWeight.w800,
                color: color)),
        Text('FCFA',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 9.5, color: AppColors.text3,
                letterSpacing: 0.8)),
      ]),
    ]);
  }

  /// Short relative-or-absolute timestamp used in the history feed.
  /// "5 min ago" / "3h ago" / "12 May" — keeps the row compact and
  /// easier to scan than full ISO strings.
  String _fmtTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final local = dt.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    if (diff.inDays < 7)     return '${diff.inDays}d ago';
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${local.day} ${months[local.month - 1]}';
  }

  // ── ACTIVATE (now invoked from Manage sheet) ──────────────────
  Future<void> _activate(Map<String, dynamic> g) async {
    try {
      await ApiService.activateNjangiGroup(g['id']);
      if (!mounted) return;
      widget.onRefresh();
      _snack('Group activated!');
    } catch (_) {
      if (!mounted) return;
      _snack('Need at least 2 members to activate.');
    }
  }

  // ── SHEET BUILDING BLOCKS ─────────────────────────────────────
  Widget _sheetShell({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                  color: AppColors.border3,
                  borderRadius: BorderRadius.circular(99)))),
          Text(title, style: GoogleFonts.hankenGrotesk(
              fontSize: 17, fontWeight: FontWeight.w800,
              color: AppColors.text1)),
          const SizedBox(height: 3),
          Text(subtitle, style: GoogleFonts.hankenGrotesk(
              fontSize: 12, color: AppColors.text3)),
          const SizedBox(height: 12),
          child,
        ]),
      )),
    );
  }

  Widget _sheetAction({
    required IconData icon,
    required String label,
    required String hint,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border1),
          ),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.35)),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: GoogleFonts.hankenGrotesk(
                  fontSize: 13.5, fontWeight: FontWeight.w800,
                  color: AppColors.text1)),
              const SizedBox(height: 2),
              Text(hint, style: GoogleFonts.hankenGrotesk(
                  fontSize: 11, color: AppColors.text3, height: 1.35)),
            ])),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.text3),
          ]),
        ),
      ),
    );
  }

  Widget _sheetToggle({
    required IconData icon,
    required String label,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border1),
        ),
        child: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.info.withOpacity(0.35)),
            ),
            child: const Icon(Icons.notifications_active_outlined,
                color: AppColors.info, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: GoogleFonts.hankenGrotesk(
                fontSize: 13.5, fontWeight: FontWeight.w800,
                color: AppColors.text1)),
            const SizedBox(height: 2),
            Text(hint, style: GoogleFonts.hankenGrotesk(
                fontSize: 11, color: AppColors.text3, height: 1.35)),
          ])),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ]),
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface2,
        title: Text(title, style: GoogleFonts.hankenGrotesk(
            color: AppColors.text1, fontWeight: FontWeight.w800)),
        content: Text(message, style: GoogleFonts.hankenGrotesk(
            color: AppColors.text2, fontSize: 13, height: 1.45)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel',
                style: GoogleFonts.hankenGrotesk(color: AppColors.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel,
                style: GoogleFonts.hankenGrotesk(
                    color: destructive ? AppColors.danger : AppColors.primary,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ── COMPACT TILE ──────────────────────────────────────────────
  /// Square-ish tappable tile used in the row above the members list.
  /// Designed to host short labels — the heavy content lives in the
  /// bottom sheet that opens on tap.
  Widget _squareTile({
    required IconData icon,
    required Color tint,
    required Color tintDim,
    required Color tintMid,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border1),
        ),
        child: Row(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: enabled ? tintDim : AppColors.surface3,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                  color: enabled ? tintMid : AppColors.border1),
            ),
            child: Icon(icon,
                color: enabled ? tint : AppColors.text3, size: 15),
          ),
          const SizedBox(width: 8),
          Expanded(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 11.5, fontWeight: FontWeight.w800,
                      color: AppColors.text1)),
              const SizedBox(height: 1),
              Text(subtitle,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 9.5, color: AppColors.text3)),
            ],
          )),
        ]),
      ),
    );
  }

  // ── PAYMENT SCHEDULE SHEET ────────────────────────────────────
  /// Wraps [_buildPaymentSchedule] in a scrollable bottom sheet. Since
  /// the schedule reads from the latest [members]/[currentCycle] state
  /// each render, the sheet shows fresh data every time it's opened.
  void _showPaymentScheduleSheet(
      Map<String, dynamic> g,
      List members,
      int currentCycle,
      double contrib) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scroll) => Container(
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(children: [
            Container(width: 40, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                    color: AppColors.border3,
                    borderRadius: BorderRadius.circular(99))),
            Expanded(child: SingleChildScrollView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: _buildPaymentSchedule(g, members, currentCycle, contrib),
            )),
          ]),
        ),
      ),
    );
  }

  // ── INVITE SHEET ──────────────────────────────────────────────
  /// Opens the Invite Members action sheet. Three actions: share the
  /// code through the OS share sheet (WhatsApp, Instagram, SMS, …), copy
  /// the code to the clipboard, or open the QR-code dialog.
  void _showInviteSheet(Map<String, dynamic> g, int filled) {
    final code = g['invite_code'].toString();
    final groupName = (g['name'] ?? '').toString();
    final maxMembers = (g['max_members'] ?? 0) as int;
    final shareText =
        'Join my Njangi group "$groupName" on NkapSave.\n\n'
        'Use this code in the app to join: $code\n\n'
        'Contribution: ${_fmt((g['contribution'] as num).toDouble())} FCFA · '
        '${g['frequency']}.';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: AppColors.border3,
                    borderRadius: BorderRadius.circular(99)))),
            Text('Invite to $groupName',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 17, fontWeight: FontWeight.w800,
                    color: AppColors.text1)),
            const SizedBox(height: 4),
            Text('$filled of $maxMembers slots filled',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 18),
            // Big code chip.
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.primaryDim,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primaryMid),
              ),
              child: Column(children: [
                Text('INVITE CODE', style: GoogleFonts.hankenGrotesk(
                    fontSize: 10.5, color: AppColors.text3,
                    letterSpacing: 1.4, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(code, style: GoogleFonts.hankenGrotesk(
                    fontSize: 30, fontWeight: FontWeight.w800,
                    color: AppColors.primary, letterSpacing: 6)),
              ]),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _inviteAction(
                  icon: Icons.ios_share_rounded,
                  label: 'Share',
                  primary: true,
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    try {
                      await Share.share(shareText,
                          subject: 'Join $groupName on NkapSave');
                    } catch (_) {
                      if (!mounted) return;
                      _snack('Sharing isn\'t available on this device.');
                    }
                  })),
              const SizedBox(width: 10),
              Expanded(child: _inviteAction(
                  icon: Icons.copy_rounded,
                  label: 'Copy code',
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    HapticFeedback.selectionClick();
                    if (!mounted) return;
                    Navigator.of(ctx).pop();
                    _snack('Code copied to clipboard');
                  })),
              const SizedBox(width: 10),
              Expanded(child: _inviteAction(
                  icon: Icons.qr_code_rounded,
                  label: 'Show QR',
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _showGroupQR(g);
                  })),
            ]),
            const SizedBox(height: 14),
            Text(
              'Anyone with this code can request to join. '
              'You can adjust the maximum number of members in the '
              '"Members" section below.',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11.5, color: AppColors.text3, height: 1.45),
            ),
          ]),
        )),
      ),
    );
  }

  Widget _inviteAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    final bg  = primary ? AppColors.primary : AppColors.surface2;
    final fg  = primary ? const Color(0xFFFFFFFF) : AppColors.text1;
    final bd  = primary ? AppColors.primary : AppColors.border1;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: bd),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: fg, size: 18),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11.5, fontWeight: FontWeight.w700, color: fg)),
        ]),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.hankenGrotesk(
              fontWeight: FontWeight.w600, color: AppColors.text1)),
      backgroundColor: AppColors.surface3,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── PAYMENT SCHEDULE ──────────────────────────────────────────
  /// Renders the rotation timeline. Each cycle row shows who receives
  /// that cycle, the contribution-per-member, and a status:
  ///   - past cycles: ✓ Received
  ///   - current cycle: progress chip (`paidCount of total paid`) + "Receiving"
  ///   - future cycles: "Upcoming"
  /// Data is read from [members] (sorted by position) and [g], so the
  /// next group refresh (after a payment or cycle advance) re-renders
  /// the schedule with no extra plumbing.
  Widget _buildPaymentSchedule(
      Map<String, dynamic> g,
      List members,
      int currentCycle,
      double contrib) {
    final ordered = [...members]..sort((a, b) =>
        ((a['position'] ?? 0) as int)
            .compareTo((b['position'] ?? 0) as int));
    final paidCount = ordered.where((m) =>
        (m['has_paid'] ?? false) as bool).length;
    final total = ordered.length;
    final cycleProgress = total == 0 ? 0.0 : paidCount / total;

    return NkapCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: AppColors.accentDim,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.accentMid),
          ),
          child: const Icon(Icons.event_repeat_rounded,
              color: AppColors.accent, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Payment Schedule', style: GoogleFonts.hankenGrotesk(
              fontWeight: FontWeight.w800, fontSize: 14,
              color: AppColors.text1)),
          const SizedBox(height: 2),
          Text('Updates as members pay', style: GoogleFonts.hankenGrotesk(
              fontSize: 11, color: AppColors.text3)),
        ])),
        NkapChip(
            label: 'Cycle $currentCycle/${g['total_cycles']}',
            color: AppColors.primary,
            dimColor: AppColors.primaryDim),
      ]),
      const SizedBox(height: 14),
      // Current-cycle progress strip.
      Row(children: [
        Text('This cycle', style: GoogleFonts.hankenGrotesk(
            fontSize: 11.5, color: AppColors.text2)),
        const Spacer(),
        Text('$paidCount of $total paid', style: GoogleFonts.hankenGrotesk(
            fontSize: 11.5, fontWeight: FontWeight.w700,
            color: AppColors.text1)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: cycleProgress, minHeight: 6,
          backgroundColor: AppColors.border1,
          valueColor: const AlwaysStoppedAnimation(AppColors.primary),
        ),
      ),
      const SizedBox(height: 14),
      Container(height: 1, color: AppColors.border1),
      const SizedBox(height: 6),
      // Per-cycle rows.
      for (final m in ordered)
        _scheduleRow(m, currentCycle, contrib),
    ]));
  }

  /// One row of the Payment Schedule list.
  Widget _scheduleRow(Map m, int currentCycle, double contrib) {
    final pos        = (m['position'] ?? 0) as int;
    final isMe       = (m['is_me'] ?? false) as bool;
    final paid       = (m['has_paid'] ?? false) as bool;
    final isVerified = (m['is_verified'] ?? false) as bool;
    final isPast     = pos < currentCycle;
    final isNow      = pos == currentCycle;

    late final IconData icon;
    late final Color    iconColor;
    late final Widget   trailing;
    if (isPast) {
      icon      = Icons.check_circle_rounded;
      iconColor = AppColors.primary;
      trailing  = Text('Received',
          style: GoogleFonts.hankenGrotesk(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: AppColors.primary));
    } else if (isNow) {
      icon      = Icons.radio_button_checked_rounded;
      iconColor = AppColors.accent;
      trailing  = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: AppColors.accentDim,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.accentMid)),
        child: Text(paid ? 'Paid · Receiving' : 'Receiving',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 10.5, fontWeight: FontWeight.w800,
                color: AppColors.accent)),
      );
    } else {
      icon      = Icons.radio_button_unchecked_rounded;
      iconColor = AppColors.text3;
      trailing  = Text('Upcoming',
          style: GoogleFonts.hankenGrotesk(
              fontSize: 11, color: AppColors.text3));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 12),
        SizedBox(width: 56,
          child: Text('Cycle $pos', style: GoogleFonts.hankenGrotesk(
              fontSize: 12, fontWeight: FontWeight.w700,
              color: AppColors.text2))),
        Expanded(child: Row(children: [
          Flexible(child: Text(
              isMe ? '${m['name']} (you)' : m['name'].toString(),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 12.5,
                  fontWeight: isMe ? FontWeight.w800 : FontWeight.w600,
                  color: isMe ? AppColors.primary : AppColors.text1))),
          // Verified-by-CNI checkmark — small filled circle so it reads
          // at a glance which members have cleared ID verification.
          if (isVerified) ...[
            const SizedBox(width: 4),
            Tooltip(
              message: 'ID-verified',
              child: Icon(Icons.verified_rounded,
                  size: 13, color: AppColors.primary),
            ),
          ],
        ])),
        const SizedBox(width: 8),
        trailing,
      ]),
    );
  }

  void _showMaxMembersSheet(Map<String, dynamic> g) {
    final ctrl = TextEditingController(text: g['max_members'].toString());
    final currentCount = (g['member_count'] ?? 0) as int;
    bool saving = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, set) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration:  BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(28))),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border2,
                    borderRadius: BorderRadius.circular(99)))),
            const SizedBox(height: 20),
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                  color: AppColors.primaryDim,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primaryMid)),
              child: const Icon(Icons.people_alt_rounded,
                  color: AppColors.primary, size: 28),
            ),
            const SizedBox(height: 16),
            Text('Adjust Max Members', style: GoogleFonts.hankenGrotesk(
                fontSize: 18, fontWeight: FontWeight.w800,
                color: AppColors.text1)),
            const SizedBox(height: 6),
            Text('Currently ' + currentCount.toString() + ' members joined',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 24),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 32, fontWeight: FontWeight.w800,
                  color: AppColors.primary),
              decoration: InputDecoration(
                hintText: 'e.g. 20',
                hintStyle: GoogleFonts.hankenGrotesk(
                    color: AppColors.border2, fontSize: 28),
                counterText: '',
              ),
              maxLength: 4,
            ),
            const SizedBox(height: 8),
            Text('Cannot be less than ' + currentCount.toString() + ' (current members)',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 11, color: AppColors.text3,
                    fontStyle: FontStyle.italic)),
            const SizedBox(height: 24),
            NkapButton(
              label: saving ? 'Updating...' : 'Update',
              icon: Icons.check_rounded,
              onTap: saving ? null : () async {
                final newMax = int.tryParse(ctrl.text) ?? 0;
                if (newMax < currentCount) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        'Cannot be less than ' + currentCount.toString(),
                        style: GoogleFonts.hankenGrotesk(
                            fontWeight: FontWeight.w600)),
                    backgroundColor: AppColors.danger,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ));
                  return;
                }
                if (newMax < 2) return;
                set(() => saving = true);
                try {
                  await ApiService.updateMaxMembers(g['id'], newMax);
                  if (mounted) {
                    Navigator.pop(context);
                    widget.onRefresh();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          'Max members updated to ' + newMax.toString(),
                          style: GoogleFonts.hankenGrotesk(
                              fontWeight: FontWeight.w600)),
                      backgroundColor: AppColors.primary.withOpacity(0.9),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ));
                  }
                } catch (e) {
                  set(() => saving = false);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Could not update',
                        style: GoogleFonts.hankenGrotesk(
                            fontWeight: FontWeight.w600)),
                    backgroundColor: AppColors.danger,
                  ));
                }
              },
            ),
          ]),
        ),
      )),
    );
  }

}

// ═══════════════════════════════════════════════════════════════
// OPERATOR SELECTION CARD
// ═══════════════════════════════════════════════════════════════
class _OperatorCard extends StatelessWidget {
  final bool selected;
  final String brand, title, subtitle;
  final Color brandColor, brandText;
  final VoidCallback onTap;

  const _OperatorCard({
    required this.selected, required this.brand,
    required this.brandColor, required this.brandText,
    required this.title, required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMtn = brand == 'MTN';

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? brandColor.withOpacity(0.08) : AppColors.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? brandColor : AppColors.border2,
              width: selected ? 2 : 1),
          boxShadow: selected ? [BoxShadow(
              color: brandColor.withOpacity(0.25),
              blurRadius: 16,
              offset: const Offset(0, 4))] : null,
        ),
        child: Row(children: [
          // Logo
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              gradient: isMtn
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [brandColor, brandColor.withOpacity(0.85)])
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [brandColor, const Color(0xFFFF8533)]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                  color: brandColor.withOpacity(0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 4))],
            ),
            child: Stack(children: [
              if (isMtn) Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: RadialGradient(
                      center: const Alignment(-0.4, -0.4),
                      radius: 0.9,
                      colors: [
                        Colors.white.withOpacity(0.25),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: isMtn
                    ? Text('MTN',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: brandText,
                            letterSpacing: -0.5,
                            height: 1))
                    : Column(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text('orange',
                              style: GoogleFonts.hankenGrotesk(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: brandColor,
                                  letterSpacing: 0,
                                  height: 1)),
                        ),
                        const SizedBox(height: 3),
                        Text('Money',
                            style: GoogleFonts.hankenGrotesk(
                                fontSize: 8,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                height: 1)),
                      ]),
              ),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              Text(title, style: GoogleFonts.hankenGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: AppColors.text1)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 4, height: 4,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary)),
                  const SizedBox(width: 3),
                  Text('Live', style: GoogleFonts.hankenGrotesk(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      letterSpacing: 0.3)),
                ]),
              ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
               Icon(Icons.dialpad_rounded,
                  size: 11, color: AppColors.text3),
              const SizedBox(width: 4),
              Text('Dial ' + subtitle, style: GoogleFonts.hankenGrotesk(
                  fontSize: 11, color: AppColors.text3,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5)),
            ]),
            const SizedBox(height: 3),
            Text('Instant transfer · Secured',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 10, color: AppColors.text3,
                    fontStyle: FontStyle.italic)),
          ])),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 24, height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: selected ? brandColor : AppColors.border3,
                  width: 2),
              color: selected ? brandColor : Colors.transparent,
            ),
            child: selected
                ? Icon(Icons.check_rounded, color: brandText, size: 16)
                : null,
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// USSD DIALOG (4-step: Connecting → USSD → PIN → Processing)
// ═══════════════════════════════════════════════════════════════
class _USSDDialog extends StatefulWidget {
  final Map<String, dynamic> group;
  final double amount;
  final String operator, phone;
  final int cycle;
  final VoidCallback onSuccess;
  const _USSDDialog({
    required this.group, required this.amount,
    required this.operator, required this.phone,
    this.cycle = 1,
    required this.onSuccess,
  });
  @override State<_USSDDialog> createState() => _USSDDialogState();
}

class _USSDDialogState extends State<_USSDDialog> {
  int _step = 0; // 0:dialing, 1:enter PIN, 2:processing
  final _pinCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _step = 1);
    });
  }

  Color get _brandColor =>
      widget.operator == 'MTN' ? _Brand.mtnYellow : _Brand.orangeRed;
  Color get _brandText =>
      widget.operator == 'MTN' ? _Brand.mtnDark : Colors.white;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24)),
      child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Brand header
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: _brandColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                  color: _brandColor.withOpacity(0.4), blurRadius: 16)],
            ),
            child: Center(child: Text(widget.operator,
                style: GoogleFonts.hankenGrotesk(
                    fontSize: widget.operator == 'Orange' ? 13 : 18,
                    fontWeight: FontWeight.w900,
                    color: _brandText))),
          ),
          const SizedBox(height: 16),
          if (_step == 0) ...[
            Text('Connecting to ${widget.operator}...',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: AppColors.text1)),
            const SizedBox(height: 8),
            Text('+237 ${widget.phone}',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 12, color: AppColors.text3)),
            const SizedBox(height: 20),
             SizedBox(height: 4,
                child: LinearProgressIndicator(
                    backgroundColor: AppColors.border1,
                    valueColor: AlwaysStoppedAnimation(
                        AppColors.primary))),
          ] else if (_step == 1) ...[
            // USSD prompt simulation
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border2),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('${widget.operator} Mobile Money',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 11, color: _brandColor,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text('Pay ${_fmt(widget.amount)} FCFA',
                    style: GoogleFonts.hankenGrotesk(
                        color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text('To: NkapSave Njangi (${widget.group['name']})',
                    style: GoogleFonts.hankenGrotesk(
                        color: Colors.white70, fontSize: 11)),
                const SizedBox(height: 10),
                Text('Enter PIN to confirm:',
                    style: GoogleFonts.hankenGrotesk(
                        color: Colors.white70, fontSize: 11)),
              ]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 24, fontWeight: FontWeight.w800,
                  letterSpacing: 12, color: AppColors.text1),
              decoration: InputDecoration(
                hintText: '••••',
                hintStyle: GoogleFonts.hankenGrotesk(
                    color: AppColors.border2,
                    fontSize: 24, letterSpacing: 12),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            NkapButton(
              label: 'Confirm Payment',
              icon: Icons.lock_rounded,
              onTap: () {
                if (_pinCtrl.text.length != 4) return;
                setState(() => _step = 2);
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) widget.onSuccess();
                });
              },
            ),
          ] else ...[
            Text('Processing...', style: GoogleFonts.hankenGrotesk(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: AppColors.text1)),
            const SizedBox(height: 12),
            const SizedBox(
                width: 40, height: 40,
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 3)),
          ],
          if (_step == 1) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.hankenGrotesk(
                  color: AppColors.text3, fontSize: 12)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// SUCCESS DIALOG
// ═══════════════════════════════════════════════════════════════
class _SuccessDialog extends StatefulWidget {
  final double amount;
  final String groupName, operator, phone, txRef;
  final VoidCallback onClose;
  const _SuccessDialog({
    required this.amount, required this.groupName,
    required this.operator, required this.phone,
    required this.txRef, required this.onClose,
  });
  @override
  State<_SuccessDialog> createState() => _SuccessDialogState();
}

class _SuccessDialogState extends State<_SuccessDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _scale = CurvedAnimation(
        parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.forward();
  }

  @override void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24)),
      child: Padding(padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ScaleTransition(
            scale: _scale,
            child: Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [
                  AppColors.primary,
                  AppColors.magenta]),
                boxShadow: [BoxShadow(
                    color: AppColors.primary.withOpacity(0.5),
                    blurRadius: 30, spreadRadius: 4)],
              ),
              child: const Icon(Icons.check_rounded,
                  color: Color(0xFFFFFFFF), size: 56),
            ),
          ),
          const SizedBox(height: 20),
          Text('Payment Successful!', style: GoogleFonts.hankenGrotesk(
              fontSize: 18, fontWeight: FontWeight.w800,
              color: AppColors.text1)),
          const SizedBox(height: 6),
          Text('${_fmt(widget.amount)} FCFA paid',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 15, fontWeight: FontWeight.w600,
                  color: AppColors.primary)),
          const SizedBox(height: 4),
          Text('All members have been notified.',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 12, color: AppColors.text3)),
          const SizedBox(height: 24),
          NkapButton(label: 'Done', onTap: widget.onClose),
        ]),
      ),
    );
  }
}

class _GroupPreviewDialog extends StatelessWidget {
  final Map<String, dynamic> group;
  const _GroupPreviewDialog({required this.group});

  String _f(double n) => n.abs().toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},');

  @override
  Widget build(BuildContext context) {
    final desc = (group['description'] ?? '').toString();
    final hasDesc = desc.trim().isNotEmpty;
    final creatorPic = group['creator_picture'] as String?;
    final creatorName = group['creator_name'] ?? 'Unknown';

    return Dialog(
      backgroundColor: AppColors.surface1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primaryDim,
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: AppColors.primaryMid)),
                child: const Icon(Icons.groups_rounded,
                    color: AppColors.primary, size: 26)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(group['name'] ?? '', style: GoogleFonts.hankenGrotesk(
                    fontSize: 17, fontWeight: FontWeight.w800,
                    color: AppColors.text1),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: group['status'] == 'pending'
                          ? AppColors.accentDim : AppColors.primaryDim,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(group['status'].toString().toUpperCase(),
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 9, fontWeight: FontWeight.w800,
                          color: group['status'] == 'pending'
                              ? AppColors.accent : AppColors.primary))),
              ])),
            ]),
            const SizedBox(height: 16),
            if (hasDesc) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border1)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('ABOUT', style: GoogleFonts.hankenGrotesk(
                      fontSize: 9, color: AppColors.text3, letterSpacing: 1)),
                  const SizedBox(height: 5),
                  Text(desc, style: GoogleFonts.hankenGrotesk(
                      fontSize: 12.5, color: AppColors.text2, height: 1.5)),
                ])),
              const SizedBox(height: 12),
            ],
            Row(children: [
              Expanded(child: _stat('Contribution',
                  _f((group["contribution"] as num).toDouble()), 'FCFA')),
              const SizedBox(width: 8),
              Expanded(child: _stat('Frequency',
                  group['frequency'] ?? '', '')),
              const SizedBox(width: 8),
              Expanded(child: _stat('Members',
                  '${group['member_count']}/${group['max_members']}', '')),
            ]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.primaryDim,
                  backgroundImage: creatorPic != null && creatorPic.isNotEmpty
                      ? NetworkImage(ApiService.pictureUrl(creatorPic))
                      : null,
                  child: creatorPic == null || creatorPic.isEmpty
                      ? Text(creatorName.toString()
                          .substring(0, 1).toUpperCase(),
                          style: GoogleFonts.hankenGrotesk(
                              fontSize: 12, fontWeight: FontWeight.w800,
                              color: AppColors.primary))
                      : null),
                const SizedBox(width: 8),
                Text('Created by ', style: GoogleFonts.hankenGrotesk(
                    fontSize: 11, color: AppColors.text3)),
                Flexible(child: Text(creatorName,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 11.5, fontWeight: FontWeight.w700,
                        color: AppColors.text1))),
                const SizedBox(width: 4),
                const Icon(Icons.shield_rounded,
                    size: 11, color: AppColors.purple),
              ])),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => Navigator.pop(context, false),
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border2),
                    borderRadius: BorderRadius.circular(12)),
                  child: Center(child: Text('Cancel',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: AppColors.text2)))))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: GestureDetector(
                onTap: () => Navigator.pop(context, true),
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    const Icon(Icons.group_add_rounded,
                        size: 16, color: Color(0xFFFFFFFF)),
                    const SizedBox(width: 6),
                    Text('Join Group', style: GoogleFonts.hankenGrotesk(
                        fontSize: 13, fontWeight: FontWeight.w800,
                        color: const Color(0xFFFFFFFF))),
                  ])))),
            ]),
          ]))));
  }

  Widget _stat(String label, String value, String unit) => Container(
    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
    decoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border1)),
    child: Column(children: [
      Text(label, style: GoogleFonts.hankenGrotesk(
          fontSize: 9, color: AppColors.text3, letterSpacing: 0.5),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 3),
      Text(value, style: GoogleFonts.hankenGrotesk(
          fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.text1),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      if (unit.isNotEmpty) Text(unit, style: GoogleFonts.hankenGrotesk(
          fontSize: 8, color: AppColors.text3)),
    ]));
}

