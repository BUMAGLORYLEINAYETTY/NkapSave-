import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/preferences/app_feature.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/services/user_preferences.dart';
import '../../../../core/widgets/nkap_card.dart';
import '../../../../core/widgets/nkap_button.dart';
import '../../../../core/widgets/nkap_text_field.dart';
import '../../../auth/presentation/widgets/feature_unlock_sheet.dart';
import 'kyc_screen.dart';
import '../../../../core/constants/feature_flags.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _uploading = false;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await ApiService.getMyProfile();
      if (mounted) setState(() { _profile = p; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1024);
    if (file == null) return;

    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      await ApiService.uploadProfilePicture(bytes, file.name);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Photo updated!',
              style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
          backgroundColor: AppColors.primary.withOpacity(0.9),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Upload failed',
              style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
          backgroundColor: AppColors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _editProfile() {
    final p = _profile ?? {};
    final nameCtrl = TextEditingController(text: p['full_name'] ?? '');
    final phoneCtrl = TextEditingController(text: p['phone'] ?? '');
    final bioCtrl = TextEditingController(text: p['bio'] ?? '');
    final locCtrl = TextEditingController(text: p['location'] ?? '');
    final occCtrl = TextEditingController(text: p['occupation'] ?? '');
    String? incomeBracket    = p['income_bracket']     as String?;
    String  preferredLanguage = (p['preferred_language'] as String?) ?? 'en';
    bool saving = false;

    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, set) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration:  BoxDecoration(color: AppColors.surface1,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: AppColors.border2,
                      borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 20),
              Text('Edit Profile', style: GoogleFonts.hankenGrotesk(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  color: AppColors.text1)),
              const SizedBox(height: 20),
              NkapTextField(label: 'Full Name', hint: 'Your name',
                  controller: nameCtrl,
                  prefixIcon:  Icon(Icons.person_rounded,
                      size: 18, color: AppColors.text3)),
              const SizedBox(height: 14),
              NkapTextField(label: 'Phone', hint: '+237 6XX XXX XXX',
                  controller: phoneCtrl, keyboardType: TextInputType.phone,
                  prefixIcon:  Icon(Icons.phone_rounded,
                      size: 18, color: AppColors.text3)),
              const SizedBox(height: 14),
              NkapTextField(label: 'Occupation', hint: 'e.g. Teacher',
                  controller: occCtrl,
                  prefixIcon:  Icon(Icons.work_rounded,
                      size: 18, color: AppColors.text3)),
              const SizedBox(height: 14),
              NkapTextField(label: 'Location', hint: 'e.g. Douala',
                  controller: locCtrl,
                  prefixIcon:  Icon(Icons.location_on_rounded,
                      size: 18, color: AppColors.text3)),
              const SizedBox(height: 18),
              Align(alignment: Alignment.centerLeft,
                  child: Text('Monthly income bracket',
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: AppColors.text2))),
              const SizedBox(height: 7),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in const [
                  ('under_50k', 'Under 50k'),
                  ('50k_100k',  '50k–100k'),
                  ('100k_300k', '100k–300k'),
                  ('300k_500k', '300k–500k'),
                  ('500k_1m',   '500k–1M'),
                  ('over_1m',   '1M+'),
                ])
                  _Chip(
                    label: e.$2,
                    selected: incomeBracket == e.$1,
                    onTap: () => set(() => incomeBracket = e.$1),
                  ),
              ]),
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft,
                  child: Text("NkapBot's language",
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: AppColors.text2))),
              const SizedBox(height: 7),
              Row(children: [
                for (final l in const [
                  ('en', 'English'),
                  ('fr', 'Français'),
                  ('pidgin', 'Pidgin'),
                ]) ...[
                  _Chip(
                    label: l.$2,
                    selected: preferredLanguage == l.$1,
                    onTap: () => set(() => preferredLanguage = l.$1),
                  ),
                  const SizedBox(width: 6),
                ],
              ]),
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft,
                  child: Text('Bio', style: GoogleFonts.hankenGrotesk(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: AppColors.text2))),
              const SizedBox(height: 7),
              TextField(
                controller: bioCtrl, maxLines: 3, maxLength: 300,
                style: GoogleFonts.hankenGrotesk(fontSize: 14, color: AppColors.text1),
                decoration: const InputDecoration(
                  hintText: 'Tell people a bit about yourself...',
                ),
              ),
              const SizedBox(height: 20),
              NkapButton(
                label: saving ? 'Saving...' : 'Save Changes',
                icon: Icons.check_rounded,
                onTap: saving ? null : () async {
                  set(() => saving = true);
                  try {
                    await ApiService.updateProfile(
                      fullName: nameCtrl.text.trim(),
                      phone: phoneCtrl.text.trim(),
                      bio: bioCtrl.text.trim(),
                      location: locCtrl.text.trim(),
                      occupation: occCtrl.text.trim(),
                      incomeBracket: incomeBracket,
                      preferredLanguage: preferredLanguage,
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      _load();
                    }
                  } catch (e) { set(() => saving = false); }
                },
              ),
            ]),
          ),
        ),
      )),
    );
  }

  Future<void> _logout() async {
    await FcmService.instance.unregisterFromBackend();
    await ApiService.logout();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface1, elevation: 0,
        title: Text('My Profile', style: GoogleFonts.hankenGrotesk(
            color: AppColors.text1, fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded,
                color: AppColors.primary, size: 20),
            onPressed: _profile == null ? null : _editProfile,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _buildHeader(),
                const SizedBox(height: 16),
                if (kKycEnabled) ...[
                  _buildVerification(),
                  const SizedBox(height: 16),
                ],
                _buildInfo(),
                const SizedBox(height: 16),
                _buildFeaturesSection(),
                const SizedBox(height: 16),
                _buildLogout(),
              ]),
            ),
    );
  }

  Widget _buildHeader() {
    final p = _profile ?? {};
    final pic = p['profile_picture'] as String?;
    final picUrl = ApiService.pictureUrl(pic);
    final name = p['full_name'] ?? 'User';
    final trust = (p['trust_score'] ?? 100.0) * 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: AppColors.heroNavyGradient),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(children: [
        Stack(children: [
          CircleAvatar(
            radius: 48,
            backgroundColor: AppColors.surface3,
            backgroundImage: picUrl.isNotEmpty
                ? NetworkImage(picUrl) : null,
            child: picUrl.isEmpty
                ? Text(name[0].toUpperCase(),
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 36, fontWeight: FontWeight.w800,
                        color: AppColors.primary))
                : null,
          ),
          Positioned(
            bottom: 0, right: 0,
            child: GestureDetector(
              onTap: _uploading ? null : _pickAndUploadPhoto,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle, color: AppColors.primary,
                  border: Border.all(color: AppColors.surface1, width: 2),
                ),
                child: Icon(
                  _uploading ? Icons.hourglass_empty_rounded
                      : Icons.camera_alt_rounded,
                  color: const Color(0xFFFFFFFF), size: 16),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(name, style: GoogleFonts.hankenGrotesk(
              fontSize: 19, fontWeight: FontWeight.w800,
              color: AppColors.text1))),
          if (p['is_verified'] == true) ...[
            const SizedBox(width: 6),
            const Icon(Icons.verified_rounded,
                color: AppColors.primary, size: 18),
          ],
        ]),
        if ((p['occupation'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(p['occupation'], style: GoogleFonts.hankenGrotesk(
              fontSize: 13, color: AppColors.primary,
              fontWeight: FontWeight.w600)),
        ],
        if ((p['location'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
             Icon(Icons.location_on_rounded,
                size: 13, color: AppColors.text3),
            const SizedBox(width: 3),
            Text(p['location'], style: GoogleFonts.hankenGrotesk(
                fontSize: 12, color: AppColors.text3)),
          ]),
        ],
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularPercentIndicator(
            radius: 26, lineWidth: 4,
            percent: (trust / 100).clamp(0.0, 1.0),
            center: Text('${trust.toStringAsFixed(0)}',
                style: GoogleFonts.hankenGrotesk(fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: trust >= 80 ? AppColors.primary : AppColors.accent)),
            progressColor: trust >= 80 ? AppColors.primary : AppColors.accent,
            backgroundColor: AppColors.border1,
            circularStrokeCap: CircularStrokeCap.round,
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Trust Score', style: GoogleFonts.hankenGrotesk(
                fontSize: 10, color: AppColors.text3)),
            Text(trust >= 80 ? 'Excellent' : trust >= 70 ? 'Good' : 'Low',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: trust >= 80 ? AppColors.primary : AppColors.accent)),
          ]),
        ]),
      ]),
    );
  }

  Widget _buildVerification() {
    final verified = _profile?['is_verified'] == true;
    final (IconData icon, Color color, String title, String subtitle) = verified
        ? (Icons.verified_rounded, AppColors.primary,
           'Identity verified',
           'You\'re cleared to join groups and receive payouts.')
        : (Icons.badge_outlined, AppColors.info,
           'Verify your identity',
           'Required to join njangi groups and receive payouts.');

    return NkapCard(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const KycScreen()));
        if (mounted) _load();
      },
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: color.withOpacity(0.16),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: color.withOpacity(0.35)),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.hankenGrotesk(
              fontSize: 13.5, fontWeight: FontWeight.w800,
              color: AppColors.text1)),
          const SizedBox(height: 2),
          Text(subtitle, style: GoogleFonts.hankenGrotesk(
              fontSize: 11, color: AppColors.text3, height: 1.4)),
        ])),
        Icon(Icons.chevron_right_rounded,
            color: AppColors.text3, size: 20),
      ]),
    );
  }

  Widget _buildInfo() {
    final p = _profile ?? {};
    final bio = (p['bio'] ?? '').toString();
    return NkapCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('About', style: GoogleFonts.hankenGrotesk(
          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text1)),
      const SizedBox(height: 10),
      if (bio.isEmpty)
        Text('Tap edit to add a bio',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 12, color: AppColors.text3,
                fontStyle: FontStyle.italic))
      else
        Text(bio, style: GoogleFonts.hankenGrotesk(
            fontSize: 13, color: AppColors.text2, height: 1.5)),
      const SizedBox(height: 16),
      _row(Icons.email_rounded, 'Email', p['email'] ?? ''),
      const SizedBox(height: 10),
      _row(Icons.phone_rounded, 'Phone', p['phone'] ?? 'Not set'),
    ]));
  }

  Widget _row(IconData icon, String label, String value) => Row(children: [
    Container(
      width: 32, height: 32,
      decoration: BoxDecoration(color: AppColors.surface3,
          borderRadius: BorderRadius.circular(9)),
      child: Icon(icon, size: 14, color: AppColors.text3),
    ),
    const SizedBox(width: 12),
    Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.hankenGrotesk(
          fontSize: 10.5, color: AppColors.text3)),
      Text(value, style: GoogleFonts.hankenGrotesk(
          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text1)),
    ])),
  ]);

  Widget _buildFeaturesSection() {
    return AnimatedBuilder(
      animation: UserPreferences.instance,
      builder: (ctx, _) {
        final enabled = UserPreferences.instance.enabledFeatures;
        return NkapCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppColors.primaryDim, borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.primaryMid),
              ),
              child: const Icon(Icons.tune_rounded, size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Manage My Features',
                  style: GoogleFonts.hankenGrotesk(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.text1)),
              const SizedBox(height: 2),
              Text('Show or hide app sections to match how you use NkapSave',
                  style: GoogleFonts.hankenGrotesk(fontSize: 11, color: AppColors.text3, height: 1.4)),
            ])),
          ]),
          const SizedBox(height: 14),
          for (final f in AppFeature.values) ...[
            _featureToggleRow(f, enabled.contains(f)),
            if (f != AppFeature.values.last) Divider(height: 1, color: AppColors.border1),
          ],
        ]));
      },
    );
  }

  Widget _featureToggleRow(AppFeature f, bool on) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: f.color.withOpacity(on ? 0.18 : 0.08),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: f.color.withOpacity(on ? 0.35 : 0.15)),
          ),
          child: Center(child: Text(f.emoji, style: const TextStyle(fontSize: 18))),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(f.title,
              style: GoogleFonts.hankenGrotesk(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text1)),
          const SizedBox(height: 2),
          Text(f.tagline,
              style: GoogleFonts.hankenGrotesk(fontSize: 11, color: AppColors.text3)),
        ])),
        Transform.scale(
          scale: 0.85,
          child: Switch(
            value: on,
            activeColor: f.color,
            activeTrackColor: f.color.withOpacity(0.35),
            inactiveThumbColor: AppColors.text3,
            inactiveTrackColor: AppColors.surface3,
            onChanged: (val) => toggleFeatureWithUnlock(context, f, val),
          ),
        ),
      ]),
    );
  }

  Widget _buildLogout() => GestureDetector(
    onTap: _logout,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withOpacity(0.3)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.logout_rounded, color: AppColors.danger, size: 18),
        const SizedBox(width: 8),
        Text('Sign Out', style: GoogleFonts.hankenGrotesk(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: AppColors.danger)),
      ]),
    ),
  );
}

// ─── Member Profile View (read-only, shown to other njangi members) ───
class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(99),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryDim : AppColors.surface2,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border2,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Text(label,
          style: GoogleFonts.hankenGrotesk(
              color: selected ? AppColors.primary : AppColors.text2,
              fontSize: 11.5,
              fontWeight: FontWeight.w600)),
    ),
  );
}

class MemberProfileView extends StatefulWidget {
  final String userId;
  const MemberProfileView({super.key, required this.userId});
  @override State<MemberProfileView> createState() => _MemberProfileViewState();
}

class _MemberProfileViewState extends State<MemberProfileView> {
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final p = await ApiService.getUserProfile(widget.userId);
      if (mounted) setState(() { _profile = p; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface1, elevation: 0,
        leading: IconButton(
          icon:  Icon(Icons.arrow_back_rounded, color: AppColors.text1),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Member Profile', style: GoogleFonts.hankenGrotesk(
            color: AppColors.text1, fontWeight: FontWeight.w800, fontSize: 17)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _profile == null
              ? Center(child: Text('Could not load profile',
                  style: GoogleFonts.hankenGrotesk(color: AppColors.text2)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _buildInfo(),
                  ]),
                ),
    );
  }

  Widget _buildHeader() {
    final p = _profile!;
    final pic = p['profile_picture'] as String?;
    final picUrl = ApiService.pictureUrl(pic);
    final name = p['full_name'] ?? 'User';
    final trust = (p['trust_score'] ?? 100.0) * 1.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: AppColors.heroNavyGradient),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(children: [
        CircleAvatar(
          radius: 56,
          backgroundColor: AppColors.surface3,
          backgroundImage: picUrl.isNotEmpty ? NetworkImage(picUrl) : null,
          child: picUrl.isEmpty
              ? Text(name[0].toUpperCase(),
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 42, fontWeight: FontWeight.w800,
                      color: AppColors.primary))
              : null,
        ),
        const SizedBox(height: 14),
        Text(name, style: GoogleFonts.hankenGrotesk(
            fontSize: 21, fontWeight: FontWeight.w800,
            color: AppColors.text1)),
        if ((p['occupation'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(p['occupation'], style: GoogleFonts.hankenGrotesk(
              fontSize: 14, color: AppColors.primary,
              fontWeight: FontWeight.w600)),
        ],
        if ((p['location'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
             Icon(Icons.location_on_rounded,
                size: 14, color: AppColors.text3),
            const SizedBox(width: 4),
            Text(p['location'], style: GoogleFonts.hankenGrotesk(
                fontSize: 13, color: AppColors.text3)),
          ]),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: trust >= 80 ? AppColors.primaryDim : AppColors.accentDim,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
                color: trust >= 80 ? AppColors.primaryMid : AppColors.accentMid),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.shield_rounded,
                size: 13,
                color: trust >= 80 ? AppColors.primary : AppColors.accent),
            const SizedBox(width: 5),
            Text('Trust Score: ${trust.toStringAsFixed(0)}%',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 12, fontWeight: FontWeight.w700,
                    color: trust >= 80 ? AppColors.primary : AppColors.accent)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildInfo() {
    final p = _profile!;
    final bio = (p['bio'] ?? '').toString();
    return NkapCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('About', style: GoogleFonts.hankenGrotesk(
          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.text1)),
      const SizedBox(height: 10),
      if (bio.isEmpty)
        Text('No bio yet',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 12, color: AppColors.text3,
                fontStyle: FontStyle.italic))
      else
        Text(bio, style: GoogleFonts.hankenGrotesk(
            fontSize: 13, color: AppColors.text2, height: 1.5)),
      const SizedBox(height: 16),
      Row(children: [
         Icon(Icons.phone_rounded, size: 14, color: AppColors.text3),
        const SizedBox(width: 8),
        Text(p['phone'] ?? 'Not provided',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 12, color: AppColors.text2)),
      ]),
    ]));
  }
}
