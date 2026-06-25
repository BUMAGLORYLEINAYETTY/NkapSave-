import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/widgets/nkap_button.dart';
import '../../../../core/widgets/nkap_text_field.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  int _step = 0;
  bool _loading = false;
  bool _showPass = false;
  String? _error;
  DateTime? _dob;

  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl  = TextEditingController();
  final _passCtrl  = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool get _canContinueStep1 =>
      _nameCtrl.text.trim().length >= 3 &&
      _emailCtrl.text.contains('@') &&
      _phoneCtrl.text.replaceAll(RegExp(r'[^0-9]'), '').length >= 9;

  Future<void> _register() async {
    if (_passCtrl.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    if (!RegExp(r'\d').hasMatch(_passCtrl.text)) {
      setState(() => _error = 'Password must contain a number');
      return;
    }
    if (_passCtrl.text != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final email = _emailCtrl.text.trim();
      await ApiService.register(
        fullName: _nameCtrl.text.trim(),
        email: email,
        phone: _phoneCtrl.text.trim(),
        password: _passCtrl.text,
        dateOfBirth: _dob?.toIso8601String().substring(0, 10),
        city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
      );
      if (mounted) {
        context.go('/login');
      }
    } catch (e) {
      setState(() {
        _loading = false;
        String detail = '';
        if (e is DioException) {
          final data = e.response?.data;
          if (data is Map) detail = data['detail']?.toString() ?? '';
        }
        if (detail.isEmpty) detail = e.toString();
        if (detail.contains('email')) {
          _error = 'An account with this email already exists. Check your inbox for a verification link.';
        } else if (detail.contains('phone')) {
          _error = 'An account with this phone number already exists.';
        } else {
          _error = 'Registration failed. Please try again.';
        }
      });
    }
  }

  Future<void> _pickDOB() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1940),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 13)),
      builder: (ctx, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: AppColors.isDark
              ? ColorScheme.dark(
                  primary: AppColors.primary,
                  onPrimary: AppColors.heroFg,
                  surface: AppColors.surface2,
                  onSurface: AppColors.text1,
                )
              : ColorScheme.light(
                  primary: AppColors.primary,
                  onPrimary: AppColors.heroFg,
                  surface: AppColors.surface1,
                  onSurface: AppColors.text1,
                ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dob = picked);
  }

  String _fmtDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return m[d.month - 1] + ' ' + d.day.toString() + ', ' + d.year.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text1),
          onPressed: () {
            if (_step > 0) setState(() => _step = 0);
            else context.go('/login');
          },
        ),
        title: Text('NkapSave',
            style: AppTextStyles.h3.copyWith(color: AppColors.primary)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Progress indicator
            Row(children: [
              Expanded(child: Container(height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(99)))),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 4,
                  decoration: BoxDecoration(
                      color: _step >= 1 ? AppColors.primary : AppColors.border1,
                      borderRadius: BorderRadius.circular(99)))),
            ]),
            const SizedBox(height: 4),
            Text('Step ' + (_step + 1).toString() + ' of 2',
                style: AppTextStyles.caption),
            const SizedBox(height: 16),
            Text(
              _step == 0
                  ? 'Join the future of finance in Cameroon'
                  : 'Secure Your Account',
              style: AppTextStyles.h2,
            ),
            const SizedBox(height: 4),
            Text(_step == 0
                    ? 'Secure, transparent, and built for your growth.'
                    : 'Create a strong password to protect your money',
                style: AppTextStyles.bodyMuted),
            const SizedBox(height: 24),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.dangerDim,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.danger.withOpacity(0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.danger, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!,
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.danger))),
                ]),
              ),
              const SizedBox(height: 16),
            ],
            if (_step == 0) ..._buildStep1() else ..._buildStep2(),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('Already have an account? ', style: AppTextStyles.bodyMuted),
              GestureDetector(
                onTap: () => context.go('/login'),
                child: Text('Sign In',
                    style: AppTextStyles.label.copyWith(color: AppColors.primary)),
              ),
            ]),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }

  // Decorative hero banner replacing the Stitch stock illustration —
  // a brand-gradient card with soft circular accents and a savings icon.
  Widget _heroBanner() => Container(
    width: double.infinity,
    height: 140,
    margin: const EdgeInsets.only(bottom: 24),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: AppColors.heroBrandGradient,
      ),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Stack(
      children: [
        Positioned(
          top: -30, right: -30,
          child: Container(
            width: 110, height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.heroFg.withOpacity(0.08),
            ),
          ),
        ),
        Positioned(
          bottom: -40, left: -20,
          child: Container(
            width: 130, height: 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.heroFg.withOpacity(0.06),
            ),
          ),
        ),
        Positioned(
          top: 16, right: 16,
          child: Container(
            width: 12, height: 12,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent,
            ),
          ),
        ),
        const Center(
          child: Icon(Icons.savings_rounded,
              size: 48, color: AppColors.heroFg),
        ),
      ],
    ),
  );

  List<Widget> _buildStep1() => [
    _heroBanner(),
    NkapTextField(
      label: 'Full Name *',
      hint: 'e.g. Marie-Claire Ndongo',
      controller: _nameCtrl,
      prefixIcon: Icon(Icons.person_rounded,
          size: 18, color: AppColors.text3),
    ),
    const SizedBox(height: 16),
    NkapTextField(
      label: 'Phone Number *',
      hint: '+237 6XX XXX XXX',
      controller: _phoneCtrl,
      keyboardType: TextInputType.phone,
      prefixIcon: Icon(Icons.phone_rounded,
          size: 18, color: AppColors.text3),
    ),
    const SizedBox(height: 16),
    NkapTextField(
      label: 'Email Address *',
      hint: 'your@email.com',
      controller: _emailCtrl,
      keyboardType: TextInputType.emailAddress,
      prefixIcon: Icon(Icons.email_rounded,
          size: 18, color: AppColors.text3),
    ),
    const SizedBox(height: 16),
    Text('Date of Birth (optional)', style: AppTextStyles.label),
    const SizedBox(height: 7),
    GestureDetector(
      onTap: _pickDOB,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border2),
        ),
        child: Row(children: [
          Icon(Icons.cake_rounded, size: 18, color: AppColors.text3),
          const SizedBox(width: 12),
          Expanded(child: Text(_dob == null ? 'Select your birth date' : _fmtDate(_dob!),
              style: _dob == null ? AppTextStyles.bodyMuted : AppTextStyles.body)),
        ]),
      ),
    ),
    const SizedBox(height: 16),
    NkapTextField(
      label: 'City (optional)',
      hint: 'e.g. Douala, Yaoundé',
      controller: _cityCtrl,
      prefixIcon: Icon(Icons.location_city_rounded,
          size: 18, color: AppColors.text3),
    ),
    const SizedBox(height: 28),
    NkapButton(
      label: 'Continue',
      icon: Icons.arrow_forward_rounded,
      radius: 12,
      onTap: _canContinueStep1 ? () {
        setState(() { _step = 1; _error = null; });
      } : null,
    ),
  ];

  List<Widget> _buildStep2() => [
    Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryDim,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primaryMid),
      ),
      child: Row(children: [
        const Icon(Icons.security_rounded,
            size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(
          'Strong passwords protect your money. Use at least 6 characters with one number.',
          style: AppTextStyles.bodyMuted)),
      ]),
    ),
    const SizedBox(height: 20),
    NkapTextField(
      label: 'Create Password *',
      hint: 'Min. 6 characters with a number',
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
    _passwordStrength(),
    const SizedBox(height: 16),
    NkapTextField(
      label: 'Confirm Password *',
      hint: 'Type it again',
      password: !_showPass,
      controller: _confirmCtrl,
      prefixIcon: Icon(Icons.lock_outline_rounded,
          size: 18, color: AppColors.text3),
    ),
    const SizedBox(height: 24),
    NkapButton(
      label: _loading ? 'Creating Account...' : 'Create My Account',
      icon: Icons.check_rounded,
      radius: 12,
      loading: _loading,
      onTap: _loading ? null : _register,
    ),
    const SizedBox(height: 16),
    Text.rich(
      TextSpan(
        style: AppTextStyles.caption,
        children: [
          const TextSpan(text: 'By creating an account, you agree to our '),
          TextSpan(text: 'Terms & Conditions',
              style: AppTextStyles.caption.copyWith(
                  color: AppColors.primary, fontWeight: FontWeight.w700)),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy Policy',
              style: AppTextStyles.caption.copyWith(
                  color: AppColors.primary, fontWeight: FontWeight.w700)),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 24),
    Opacity(
      opacity: 0.5,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: 14, color: AppColors.text3),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'END-TO-END ENCRYPTED',
              style: AppTextStyles.caption.copyWith(letterSpacing: 1.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
  ];

  Widget _passwordStrength() {
    final pwd = _passCtrl.text;
    final hasLength = pwd.length >= 6;
    final hasNumber = RegExp(r'\d').hasMatch(pwd);
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(pwd);
    final score = [hasLength, hasNumber, hasLetter].where((x) => x).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (int i = 0; i < 3; i++) Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
            height: 3,
            decoration: BoxDecoration(
              color: i < score
                  ? (score == 1 ? AppColors.danger
                      : score == 2 ? AppColors.accent
                      : AppColors.primary)
                  : AppColors.border1,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 12, runSpacing: 4, children: [
        _checkItem('6+ chars', hasLength),
        _checkItem('Number', hasNumber),
        _checkItem('Letter', hasLetter),
      ]),
    ]);
  }

  Widget _checkItem(String label, bool met) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(met ? Icons.check_circle_rounded : Icons.circle_outlined,
          size: 11,
          color: met ? AppColors.primary : AppColors.text3),
      const SizedBox(width: 3),
      Text(label, style: AppTextStyles.caption.copyWith(
          color: met ? AppColors.primary : AppColors.text3,
          fontWeight: met ? FontWeight.w600 : FontWeight.w400)),
    ],
  );
}
