import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/services/user_preferences.dart';
import '../../../admin/presentation/screens/kyc_admin_screen.dart';
import '../../../../core/constants/feature_flags.dart';
import '../../../profile/presentation/screens/profile_screen.dart';
import '../../../notifications/presentation/screens/notifications_screen.dart';

/// Side drawer that opens from the top-left hamburger button on the home
/// screen. Contains everything that doesn't belong in the bottom nav or
/// the main app bar actions: app info, legal pages, support, and account.
///
/// Each "information" item opens a [_InfoSheet] modal — the placeholder
/// copy can be replaced with your real T&C / Privacy / About content
/// without changing the widget tree.
class AppDrawer extends StatelessWidget {
  /// The current user's profile payload (may be null if not yet loaded).
  final Map<String, dynamic>? profile;
  const AppDrawer({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface1,
      width: MediaQuery.of(context).size.width * 0.82,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        child: Column(children: [
          _header(context),
          Expanded(child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: [
              _section('NAVIGATE'),
              _item(context,
                  icon: Icons.person_outline_rounded,
                  label: 'My profile',
                  onTap: () => _push(context, const ProfileScreen())),
              _item(context,
                  icon: Icons.notifications_none_rounded,
                  label: 'Notifications',
                  onTap: () => _push(context, const NotificationsScreen())),
              _item(context,
                  icon: Icons.tune_rounded,
                  label: 'Manage my features',
                  hint: 'Show or hide app sections',
                  onTap: () => _push(context, const ProfileScreen())),

              _section('INFORMATION'),
              _item(context,
                  icon: Icons.info_outline_rounded,
                  label: 'About NkapSave',
                  onTap: () => _showInfo(context, _aboutSheet())),
              _item(context,
                  icon: Icons.description_outlined,
                  label: 'Terms & Conditions',
                  onTap: () => _showInfo(context, _termsSheet())),
              _item(context,
                  icon: Icons.privacy_tip_outlined,
                  label: 'Privacy Policy',
                  onTap: () => _showInfo(context, _privacySheet())),
              _item(context,
                  icon: Icons.help_outline_rounded,
                  label: 'Help & FAQ',
                  onTap: () => _showInfo(context, _helpSheet())),

              _section('PREFERENCES'),
              _item(context,
                  icon: Icons.translate_rounded,
                  label: 'Language',
                  hint: _languageHint(),
                  onTap: () => _showLanguagePicker(context)),
              _item(context,
                  icon: Icons.palette_outlined,
                  label: 'Theme',
                  hint: _themeHint(),
                  onTap: () => _showThemePicker(context)),

              _section('ENGAGE'),
              _item(context,
                  icon: Icons.feedback_outlined,
                  label: 'Send feedback',
                  onTap: () => _showInfo(context, _feedbackSheet(context))),
              _item(context,
                  icon: Icons.ios_share_rounded,
                  label: 'Share NkapSave',
                  onTap: () => _shareNkapSave(context)),
              _item(context,
                  icon: Icons.star_outline_rounded,
                  label: 'Rate the app',
                  onTap: () => _toast(context,
                      'App-store rating coming once we publish 🙌')),

              // Reviewer tools — backend gates access via 403, so the
              // entry is always visible. A non-reviewer who taps it sees
              // a clean "reviewer access only" message inside the screen.
              if (kKycEnabled) ...[
                _section('ADMIN'),
                _item(context,
                    icon: Icons.fact_check_outlined,
                    label: 'ID Verification queue',
                    hint: 'Review Cameroon CNI submissions',
                    onTap: () => _push(context, const KycAdminScreen())),
              ],

              _section('ACCOUNT'),
              _item(context,
                  icon: Icons.logout_rounded,
                  label: 'Sign out',
                  destructive: true,
                  onTap: () => _confirmLogout(context)),
            ],
          )),
          _footer(),
        ]),
      ),
    );
  }

  // ── Pieces ──────────────────────────────────────────────────
  Widget _header(BuildContext context) {
    final name  = (profile?['full_name'] ?? 'NkapSave user').toString();
    final email = (profile?['email']     ?? '').toString();
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: AppColors.heroBrandGradient,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 38, height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [
                AppColors.primary,
                AppColors.isDark
                    ? const Color(0xFF006C45)
                    : AppColors.primary.withOpacity(0.6),
              ]),
              boxShadow: [BoxShadow(
                  color: AppColors.primary.withOpacity(0.45), blurRadius: 10)],
            ),
            child: Center(child: Text('N',
                style: GoogleFonts.hankenGrotesk(
                    color: AppColors.isDark
                        ? AppColors.surface1
                        : Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900))),
          ),
          const SizedBox(width: 10),
          RichText(text: TextSpan(children: [
            TextSpan(text: 'Nkap',
                style: GoogleFonts.hankenGrotesk(
                    color: AppColors.heroFg, fontSize: 18,
                    fontWeight: FontWeight.w800)),
            TextSpan(text: 'Save',
                style: GoogleFonts.hankenGrotesk(
                    color: AppColors.primary, fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ])),
        ]),
        const SizedBox(height: 18),
        Text(name,
            style: GoogleFonts.hankenGrotesk(
                color: AppColors.heroFg, fontSize: 14,
                fontWeight: FontWeight.w700)),
        if (email.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(email,
              style: GoogleFonts.hankenGrotesk(
                  color: AppColors.heroFgMuted, fontSize: 11)),
        ],
      ]),
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
    child: Text(label,
        style: GoogleFonts.hankenGrotesk(
            color: AppColors.text3, fontSize: 9.5,
            fontWeight: FontWeight.w800, letterSpacing: 1.4)),
  );

  Widget _item(BuildContext context, {
    required IconData icon,
    required String label,
    String? hint,
    bool destructive = false,
    required VoidCallback onTap,
  }) {
    final color = destructive ? AppColors.danger : AppColors.text1;
    return InkWell(
      onTap: () { Navigator.of(context).pop(); onTap(); },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: Row(children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.hankenGrotesk(
                        color: color, fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
                if (hint != null) ...[
                  const SizedBox(height: 1),
                  Text(hint,
                      style: GoogleFonts.hankenGrotesk(
                          color: AppColors.text3, fontSize: 10.5)),
                ],
              ])),
          if (!destructive)
             Icon(Icons.chevron_right_rounded,
                color: AppColors.text3, size: 18),
        ]),
      ),
    );
  }

  Widget _footer() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
    child: Row(children: [
       Icon(Icons.shield_outlined,
          color: AppColors.text3, size: 13),
      const SizedBox(width: 6),
      Text('NkapSave · v1.0.0',
          style: GoogleFonts.hankenGrotesk(
              color: AppColors.text3, fontSize: 10.5)),
    ]),
  );

  // ── Language picker ─────────────────────────────────────────
  String _languageHint() {
    final code = (profile?['preferred_language']
        ?? UserPreferences.instance.profile['preferred_language']
        ?? 'en').toString();
    return _languageLabel(code);
  }

  String _languageLabel(String code) {
    switch (code) {
      case 'fr':     return 'Français';
      case 'pidgin': return 'Cameroon Pidgin';
      default:        return 'English';
    }
  }

  Future<void> _showLanguagePicker(BuildContext context) async {
    final currentCode = (profile?['preferred_language']
        ?? UserPreferences.instance.profile['preferred_language']
        ?? 'en').toString();
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PickerSheet(
        title: 'NkapBot\'s language',
        subtitle: 'NkapBot will reply in this language.',
        options: const [
          _PickerOption(id: 'en',     label: 'English',          emoji: '🇬🇧'),
          _PickerOption(id: 'fr',     label: 'Français',         emoji: '🇫🇷'),
          _PickerOption(id: 'pidgin', label: 'Cameroon Pidgin',  emoji: '🌍'),
        ],
        selectedId: currentCode,
      ),
    );
    if (picked == null || picked == currentCode) return;
    try {
      // Mirror the choice locally so the suggestion chips / cards pick it up
      // immediately, even before the next /profile/me reload.
      await UserPreferences.instance
          .setProfileAnswers({'preferred_language': picked});
      // Persist server-side so NkapBot prompts use it on the next /chat.
      await ApiService.updateProfile(preferredLanguage: picked);
      if (!context.mounted) return;
      _toast(context, 'Language set to ${_languageLabel(picked)}');
    } catch (e) {
      if (context.mounted) {
        _toast(context, 'Could not save: $e');
      }
    }
  }

  // ── Theme picker ────────────────────────────────────────────
  String _themeHint() {
    switch (UserPreferences.instance.themePreferenceId) {
      case 'light':  return 'Light';
      case 'system': return 'Match device';
      default:        return 'Dark';
    }
  }

  Future<void> _showThemePicker(BuildContext context) async {
    final current = UserPreferences.instance.themePreferenceId;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PickerSheet(
        title: 'App theme',
        subtitle: 'Dark is the polished default. Light is still being '
                  'rolled out across screens — some areas may stay dark '
                  'until that work lands.',
        options: const [
          _PickerOption(id: 'dark',   label: 'Dark',         emoji: '🌙'),
          _PickerOption(id: 'light',  label: 'Light',        emoji: '☀️'),
          _PickerOption(id: 'system', label: 'Match device', emoji: '⚙️'),
        ],
        selectedId: current,
      ),
    );
    if (picked == null || picked == current) return;
    await UserPreferences.instance.setThemePreference(picked);
    if (!context.mounted) return;
    _toast(context, 'Theme set to ${_themeHintForId(picked)}');
  }

  String _themeHintForId(String id) {
    switch (id) {
      case 'light':  return 'Light';
      case 'system': return 'Match device';
      default:        return 'Dark';
    }
  }

  // ── Real native share ───────────────────────────────────────
  Future<void> _shareNkapSave(BuildContext context) async {
    HapticFeedback.selectionClick();
    const text =
        "Hey — I'm using NkapSave to track my spending and save with "
        "Njangi groups. It's in French, English, and Pidgin. "
        "Try it: https://nkapsave.com";
    try {
      await Share.share(text, subject: 'NkapSave');
    } catch (_) {
      if (context.mounted) {
        _toast(context, 'Sharing isn\'t available on this device.');
      }
    }
  }

  // ── Helpers ─────────────────────────────────────────────────
  void _push(BuildContext context, Widget page) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.hankenGrotesk(color: AppColors.text1)),
      backgroundColor: AppColors.surface3,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface2,
        title: Text('Sign out?',
            style: GoogleFonts.hankenGrotesk(
                color: AppColors.text1, fontWeight: FontWeight.w700)),
        content: Text(
          'You\'ll need to sign in again to see your data.',
          style: GoogleFonts.hankenGrotesk(
              color: AppColors.text2, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.hankenGrotesk(color: AppColors.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sign out',
                style: GoogleFonts.hankenGrotesk(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (yes != true) return;
    if (!context.mounted) return;
    await FcmService.instance.unregisterFromBackend();
    await ApiService.logout();
    if (!context.mounted) return;
    context.go('/login');
  }
}

// ─── Information sheets ──────────────────────────────────────
// Each builder returns the rich content for one menu item. Replace the
// placeholder paragraphs with your real legal / marketing text — the
// presentation wrapper [_showInfo] doesn't need to change.

void _showInfo(BuildContext context, _InfoSheet sheet) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.55),
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration:  BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: AppColors.border3,
                borderRadius: BorderRadius.circular(99)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
            child: Row(children: [
              Icon(sheet.icon, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(sheet.title,
                  style: GoogleFonts.hankenGrotesk(
                      color: AppColors.text1, fontSize: 18,
                      fontWeight: FontWeight.w800))),
              IconButton(
                icon:  Icon(Icons.close_rounded,
                    color: AppColors.text2, size: 22),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]),
          ),
          Expanded(child: SingleChildScrollView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: sheet.body,
          )),
        ]),
      ),
    ),
  );
}

class _InfoSheet {
  final String title;
  final IconData icon;
  final Widget body;
  const _InfoSheet({required this.title, required this.icon, required this.body});
}

Text _p(String s) => Text(s,
    style: GoogleFonts.hankenGrotesk(
        color: AppColors.text2, fontSize: 13, height: 1.55));

Text _h2(String s) => Text(s,
    style: GoogleFonts.hankenGrotesk(
        color: AppColors.text1, fontSize: 14,
        fontWeight: FontWeight.w700, height: 1.4));

Widget _gap([double h = 10]) => SizedBox(height: h);

_InfoSheet _aboutSheet() => _InfoSheet(
  title: 'About NkapSave',
  icon:  Icons.info_outline_rounded,
  body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _p('NkapSave is a personal-finance companion built for Cameroon. '
       'It helps you see where your money goes, save toward goals, manage '
       'Njangi groups digitally, and get smart advice from NkapBot — '
       'all from a single app that speaks your language.'),
    _gap(14),
    _h2('Why it exists'),
    _gap(6),
    _p('Most finance apps assume a Western context — bank accounts, credit '
       'scores, retirement funds. NkapSave starts from how money actually '
       'moves here: Mobile Money transfers, family obligations, rotating '
       'savings groups. We build features that match the reality.'),
    _gap(14),
    _h2('What you can do'),
    _gap(6),
    _p('• Track spending and set monthly category budgets\n'
       '• Save toward goals with fixed-amount auto-deductions\n'
       '• Run Njangi (tontine) groups with trust scores and reminders\n'
       '• Ask NkapBot anything about your money — in English, French, '
       'or Cameroon Pidgin.'),
    _gap(14),
    _h2('Built for you, with you'),
    _gap(6),
    _p('NkapSave is still growing. Tell us what should come next via the '
       '"Send feedback" option below — every suggestion is read.'),
  ]),
);

_InfoSheet _termsSheet() => _InfoSheet(
  title: 'Terms & Conditions',
  icon:  Icons.description_outlined,
  body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _h2('1. Acceptance of terms'),
    _gap(6),
    _p('By creating an account and using NkapSave, you agree to these '
       'terms. If you don\'t agree, please don\'t use the app.'),
    _gap(14),
    _h2('2. Your account'),
    _gap(6),
    _p('You are responsible for keeping your account credentials and PIN '
       'safe. Don\'t share them with anyone. Notify us immediately if you '
       'suspect unauthorised access.'),
    _gap(14),
    _h2('3. Money movement'),
    _gap(6),
    _p('NkapSave provides advisory and organisational tools. It does not '
       'hold your money. All actual transfers happen through your linked '
       'Mobile Money provider (MTN MoMo, Orange Money), which has its own '
       'terms and authorisation flow.'),
    _gap(14),
    _h2('4. Njangi groups'),
    _gap(6),
    _p('Njangi groups are formed between members. NkapSave provides the '
       'digital infrastructure (contribution tracking, reminders, trust '
       'scores) but does not guarantee payouts. Members are responsible '
       'to each other.'),
    _gap(14),
    _h2('5. Data accuracy'),
    _gap(6),
    _p('Numbers shown in the app — balances, projections, health scores — '
       'are based on data you provide and your linked accounts. Treat them '
       'as guidance, not as official financial statements.'),
    _gap(14),
    _h2('6. Termination'),
    _gap(6),
    _p('You may delete your account at any time. We reserve the right to '
       'suspend accounts that violate these terms or are used for fraud.'),
    _gap(14),
    _p('Last updated: May 2026. We\'ll notify you in-app when these terms '
       'change.'),
  ]),
);

_InfoSheet _privacySheet() => _InfoSheet(
  title: 'Privacy Policy',
  icon:  Icons.privacy_tip_outlined,
  body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _h2('What we collect'),
    _gap(6),
    _p('Your name, phone, email, profile photo, transactions you log, '
       'savings goals, Njangi memberships, and the answers you give during '
       'onboarding. We collect this to run the features you use — nothing '
       'more.'),
    _gap(14),
    _h2('What we don\'t collect'),
    _gap(6),
    _p('We don\'t scrape your phone\'s SMS, contacts, location, photos, '
       'or any other data outside what you explicitly enter into the app.'),
    _gap(14),
    _h2('Where it lives'),
    _gap(6),
    _p('On NkapSave servers, encrypted at rest. We send anonymised '
       'metadata to Anthropic when you ask NkapBot a question; your '
       'name, phone, and email never leave our servers in that flow.'),
    _gap(14),
    _h2('Who we share with'),
    _gap(6),
    _p('Nobody, except as required to run the service: your Mobile Money '
       'provider when you authorise a transfer, and Anthropic for NkapBot '
       'responses (context only, never personal identifiers).'),
    _gap(14),
    _h2('Your rights'),
    _gap(6),
    _p('You can request a full export of your data, or permanent deletion '
       'of your account, at any time via "Send feedback".'),
  ]),
);

_InfoSheet _helpSheet() => _InfoSheet(
  title: 'Help & FAQ',
  icon:  Icons.help_outline_rounded,
  body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _h2('I created a goal but auto-save didn\'t fire'),
    _gap(6),
    _p('Auto-save requires a verified Mobile Money wallet. From the '
       'Savings screen, tap "Connect Wallet" and complete the link. '
       'Once verified, the next scheduled run will pull funds.'),
    _gap(14),
    _h2('I joined a Njangi by mistake'),
    _gap(6),
    _p('Tap the group → "Leave group" before the first contribution. '
       'Once contributions have started, leaving requires consent from '
       'the group admin to keep payouts fair.'),
    _gap(14),
    _h2('NkapBot says it can\'t reach the AI'),
    _gap(6),
    _p('This usually means the server\'s connection to the AI provider '
       'is temporarily down or out of credits. Your data is fine; try '
       'again in a few minutes.'),
    _gap(14),
    _h2('I want NkapBot to speak French'),
    _gap(6),
    _p('Profile → Edit → "NkapBot\'s language" → French. Save. The next '
       'reply from NkapBot will be in French.'),
    _gap(14),
    _h2('Something else?'),
    _gap(6),
    _p('Send feedback (option above this one) and we\'ll get back to you.'),
  ]),
);

_InfoSheet _feedbackSheet(BuildContext context) => _InfoSheet(
  title: 'Send feedback',
  icon:  Icons.feedback_outlined,
  body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _p('We read every message. Reach us at the address below — please '
       'include your account email so we can match the feedback to your '
       'situation.'),
    _gap(14),
    _CopyTile(text: 'feedback@nkapsave.com'),
    _gap(10),
    _CopyTile(text: '+237 6 00 00 00 00'),
    _gap(14),
    _p('Bug? A short description of what you tried and what you saw is '
       'worth more than a thousand "it doesn\'t work" messages.'),
  ]),
);

// Note: the share menu item now opens the native share sheet directly
// (see [AppDrawer._shareNkapSave]). No info-sheet builder needed.

class _PickerOption {
  final String id, label, emoji;
  const _PickerOption({
    required this.id, required this.label, required this.emoji,
  });
}

class _PickerSheet extends StatelessWidget {
  final String title, subtitle, selectedId;
  final List<_PickerOption> options;
  const _PickerSheet({
    required this.title, required this.subtitle,
    required this.options, required this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration:  BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border3,
                  borderRadius: BorderRadius.circular(99)),
            ),
            Align(alignment: Alignment.centerLeft,
              child: Text(title,
                  style: GoogleFonts.hankenGrotesk(
                      color: AppColors.text1, fontSize: 17,
                      fontWeight: FontWeight.w800))),
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerLeft,
              child: Text(subtitle,
                  style: GoogleFonts.hankenGrotesk(
                      color: AppColors.text3, fontSize: 11.5, height: 1.4))),
            const SizedBox(height: 14),
            for (final opt in options) ...[
              _PickerRow(
                option: opt,
                selected: opt.id == selectedId,
                onTap: () => Navigator.of(context).pop(opt.id),
              ),
              const SizedBox(height: 8),
            ],
          ]),
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final _PickerOption option;
  final bool selected;
  final VoidCallback onTap;
  const _PickerRow({
    required this.option, required this.selected, required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withOpacity(0.08)
              : AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border1,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Text(option.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(child: Text(option.label,
              style: GoogleFonts.hankenGrotesk(
                  color: AppColors.text1, fontSize: 13.5,
                  fontWeight: FontWeight.w700))),
          Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected ? AppColors.primary : AppColors.text3,
            size: 20,
          ),
        ]),
      ),
    );
  }
}

class _CopyTile extends StatelessWidget {
  final String text;
  const _CopyTile({required this.text});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: text));
        if (!context.mounted) return;
        HapticFeedback.selectionClick();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Copied to clipboard',
              style: GoogleFonts.hankenGrotesk(color: AppColors.text1)),
          backgroundColor: AppColors.surface3,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ));
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border1),
        ),
        child: Row(children: [
          Expanded(child: Text(text,
              style: GoogleFonts.hankenGrotesk(
                  color: AppColors.text1, fontSize: 12.5,
                  height: 1.5, fontWeight: FontWeight.w500),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 10),
           Icon(Icons.copy_rounded,
              color: AppColors.text3, size: 17),
        ]),
      ),
    );
  }
}
