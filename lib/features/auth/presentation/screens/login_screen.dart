import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/fcm_service.dart';
import '../../../../core/widgets/nkap_button.dart';
import '../../../../core/widgets/nkap_card.dart';
import '../../../../core/widgets/nkap_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idCtrl   = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _showPass = false;
  String? _error;
  // Set to the unverified email when the backend returns 403 "email_not_verified"
  // so we can show a targeted message + resend option.
  String? _unverifiedEmail;
  bool _justVerified = false;   // true when landing from the email link

  static final RegExp _emailRegex =
      RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

  bool _isValidEmail(String s) => _emailRegex.hasMatch(s);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final params = GoRouterState.of(context).uri.queryParameters;
      if (params['verified'] == 'true') {
        setState(() => _justVerified = true);
      }
    });
  }

  Future<void> _resendFromLogin() async {
    final email = _idCtrl.text.trim();
    if (email.isEmpty) return;
    try {
      await ApiService.resendVerification(email);
      if (mounted) {
        setState(() {
          _error = null;
          _unverifiedEmail = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification email resent — check your inbox.')),
        );
      }
    } catch (_) {}
  }

  Future<void> _login() async {
    final email = _idCtrl.text.trim();
    final pass  = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please enter your email and password');
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => _error = 'Enter a valid email address (e.g. your@email.com)');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ApiService.login(identifier: email, password: pass);
      await FcmService.instance.syncTokenWithBackend();
      if (mounted) context.go('/home');
    } catch (e) {
      setState(() {
        _loading = false;
        if (e is DioException &&
            e.response?.statusCode == 403 &&
            (e.response?.data['detail'] ?? '') == 'email_not_verified') {
          _unverifiedEmail = email;
          _error = 'Please verify your email before logging in.';
        } else {
          _unverifiedEmail = null;
          _error = 'Wrong email or password. Check and try again.';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Soft brand glows — maps the Stitch blurred background orbs.
          Positioned(
            top: -90, left: -90,
            child: _glow(AppColors.primary),
          ),
          Positioned(
            bottom: -90, right: -90,
            child: _glow(AppColors.accent),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 16),
                      // Brand header
                      Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(
                              color: AppColors.primary.withOpacity(0.2),
                              blurRadius: 24,
                              offset: const Offset(0, 8))],
                        ),
                        child: const Icon(Icons.admin_panel_settings_rounded,
                            color: AppColors.heroFg, size: 32),
                      ),
                      const SizedBox(height: 16),
                      Text('NkapSave', style: AppTextStyles.h2),
                      const SizedBox(height: 4),
                      Text('Secure access to your savings',
                          style: AppTextStyles.bodyMuted),
                      const SizedBox(height: 32),
                      // Email verified success banner
                      if (_justVerified) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.primaryDim,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.primaryMid),
                          ),
                          child: Row(children: [
                            Icon(Icons.check_circle_rounded,
                                size: 18, color: AppColors.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Email verified! You can now log in.',
                                style: AppTextStyles.body
                                    .copyWith(color: AppColors.primary),
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Form card
                      NkapCard(
                        color: AppColors.surface1,
                        radius: 16,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_error != null) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.dangerDim,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppColors.danger.withOpacity(0.4)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      const Icon(Icons.error_outline_rounded,
                                          color: AppColors.danger, size: 18),
                                      const SizedBox(width: 10),
                                      Expanded(child: Text(_error!,
                                          style: AppTextStyles.body
                                              .copyWith(color: AppColors.danger))),
                                    ]),
                                    if (_unverifiedEmail != null) ...[
                                      const SizedBox(height: 10),
                                      GestureDetector(
                                        onTap: _resendFromLogin,
                                        child: Text(
                                          'Resend verification email',
                                          style: AppTextStyles.label.copyWith(
                                              color: AppColors.primary,
                                              decoration: TextDecoration.underline),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            NkapTextField(
                              label: 'Email',
                              hint: 'your@email.com',
                              controller: _idCtrl,
                              keyboardType: TextInputType.emailAddress,
                              prefixIcon: Icon(Icons.mail_outline_rounded,
                                  size: 18, color: AppColors.text3),
                            ),
                            const SizedBox(height: 16),
                            NkapTextField(
                              label: 'Password',
                              hint: 'Your password',
                              password: !_showPass,
                              controller: _passCtrl,
                              prefixIcon: Icon(Icons.lock_rounded,
                                  size: 18, color: AppColors.text3),
                              suffixIcon: IconButton(
                                icon: Icon(_showPass
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                                    size: 18, color: AppColors.text3),
                                onPressed: () => setState(() => _showPass = !_showPass),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {},
                                child: Text('Forgot password?',
                                    style: AppTextStyles.label
                                        .copyWith(color: AppColors.primary)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            NkapButton(
                              label: 'Log In',
                              radius: 12,
                              loading: _loading,
                              onTap: _loading ? null : _login,
                            ),
                            const SizedBox(height: 16),
                            Row(children: [
                              Expanded(child: Divider(color: AppColors.border1)),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('OR', style: AppTextStyles.caption),
                              ),
                              Expanded(child: Divider(color: AppColors.border1)),
                            ]),
                            const SizedBox(height: 16),
                            NkapButton(
                              label: 'Create New Account',
                              icon: Icons.person_add_rounded,
                              outlined: true,
                              radius: 12,
                              onTap: () => context.go('/register'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      // Trust badge
                      Opacity(
                        opacity: 0.5,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_rounded, size: 14, color: AppColors.text3),
                            const SizedBox(width: 6),
                            Text('END-TO-END ENCRYPTED',
                                style: AppTextStyles.caption.copyWith(
                                    letterSpacing: 1.5)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color color) => ImageFiltered(
    imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
    child: Container(
      width: 320, height: 320,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withOpacity(0.1),
      ),
    ),
  );
}
