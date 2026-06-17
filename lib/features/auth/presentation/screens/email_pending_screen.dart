import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/widgets/nkap_button.dart';

class EmailPendingScreen extends StatefulWidget {
  final String email;
  const EmailPendingScreen({super.key, required this.email});

  @override
  State<EmailPendingScreen> createState() => _EmailPendingScreenState();
}

class _EmailPendingScreenState extends State<EmailPendingScreen> {
  bool _resending = false;
  String? _resendMessage;

  Future<void> _resend() async {
    setState(() { _resending = true; _resendMessage = null; });
    try {
      await ApiService.resendVerification(widget.email);
      if (mounted) {
        setState(() {
          _resending = false;
          _resendMessage = 'Verification email sent! Check your inbox.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _resending = false;
          _resendMessage = 'Could not send email. Please try again later.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text1),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: AppColors.heroBrandGradient,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.mark_email_unread_rounded,
                      color: AppColors.heroFg,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text('Check your inbox', style: AppTextStyles.h2),
                  const SizedBox(height: 12),
                  Text(
                    'We sent a verification link to',
                    style: AppTextStyles.bodyMuted,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.email,
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Click the link in the email to activate your account. '
                    'Check your spam folder if you don\'t see it.',
                    style: AppTextStyles.bodyMuted,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (_resendMessage != null) ...[
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
                          child: Text(_resendMessage!,
                              style: AppTextStyles.body
                                  .copyWith(color: AppColors.primary)),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ],
                  NkapButton(
                    label: _resending ? 'Sending...' : 'Resend verification email',
                    icon: Icons.send_rounded,
                    outlined: true,
                    radius: 12,
                    loading: _resending,
                    onTap: _resending ? null : _resend,
                  ),
                  const SizedBox(height: 16),
                  NkapButton(
                    label: 'Back to Login',
                    radius: 12,
                    onTap: () => context.go('/login'),
                  ),
                  const SizedBox(height: 32),
                  Opacity(
                    opacity: 0.5,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.lock_rounded, size: 14, color: AppColors.text3),
                        const SizedBox(width: 6),
                        Text('END-TO-END ENCRYPTED',
                            style: AppTextStyles.caption
                                .copyWith(letterSpacing: 1.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
