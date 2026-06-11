import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';

class PinScreen extends StatefulWidget {
  const PinScreen({super.key});
  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen> {
  final List<String> _pin = [];

  void _add(String d) {
    if (_pin.length < 4) {
      setState(() => _pin.add(d));
      if (_pin.length == 4) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) context.go('/home');
        });
      }
    }
  }

  void _del() { if (_pin.isNotEmpty) setState(() => _pin.removeLast()); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
             Text('Set Security PIN',
                style: TextStyle(color: AppColors.text1, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
             Text('This PIN protects your financial data',
                style: TextStyle(color: AppColors.text2, fontSize: 13)),
            const SizedBox(height: 48),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 16, height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? AppColors.primary : AppColors.surface3,
                  border: Border.all(color: AppColors.border2),
                  boxShadow: i < _pin.length
                      ? [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 10)]
                      : null,
                ),
              )),
            ),
            const SizedBox(height: 56),
            ...List.generate(3, (row) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (col) {
                  final n = (row * 3 + col + 1).toString();
                  return _PinBtn(label: n, onTap: () => _add(n));
                }),
              ),
            )),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PinBtn(label: '⌫', onTap: _del, accent: true),
                  _PinBtn(label: '0', onTap: () => _add('0')),
                  _PinBtn(label: '✓', onTap: () {}, accent: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool accent;
  const _PinBtn({required this.label, required this.onTap, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 76, height: 76, margin: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent ? AppColors.primaryDim : AppColors.surface2,
          border: Border.all(color: accent ? AppColors.primaryMid : AppColors.border1),
        ),
        child: Center(child: Text(label, style: TextStyle(
          color: accent ? AppColors.primary : AppColors.text1,
          fontSize: 20, fontWeight: FontWeight.w700,
        ))),
      ),
    );
  }
}
