import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/user_preferences.dart';
import '../../../../core/widgets/nkap_button.dart';

class _Page { final String emoji, title, subtitle;
  const _Page(this.emoji, this.title, this.subtitle); }

const _pages = [
  _Page('📊', 'Track Every FCFA', 'See exactly where your money goes with smart expense tracking and AI-powered insights.'),
  _Page('💰', 'Automate Your Savings', 'Connect MTN Money or Orange Money and save automatically with every transfer.'),
  _Page('👥', 'Digital Njangi', 'Manage your rotating savings groups digitally with trust scores and instant payouts.'),
  _Page('🤖', 'AI Financial Advisor', 'Chat with NkapBot anytime for personalized financial advice based on your real data.'),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _current = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextButton(
                  onPressed: () { UserPreferences.instance.markIntroSeen(); context.go('/login'); },
                  child:  Text('Skip', style: TextStyle(color: AppColors.text2)),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _current = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) {
                  final p = _pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 110, height: 110,
                          decoration: BoxDecoration(
                            color: AppColors.primaryDim,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(color: AppColors.primaryMid),
                          ),
                          child: Center(child: Text(p.emoji, style: const TextStyle(fontSize: 46))),
                        ),
                        const SizedBox(height: 36),
                        Text(p.title, textAlign: TextAlign.center,
                            style:  TextStyle(
                              color: AppColors.text1, fontSize: 26,
                              fontWeight: FontWeight.w800, height: 1.2,
                            )),
                        const SizedBox(height: 16),
                        Text(p.subtitle, textAlign: TextAlign.center,
                            style:  TextStyle(color: AppColors.text2, fontSize: 14.5, height: 1.6)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pages.length, (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: i == _current ? 24 : 8, height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: i == _current ? AppColors.primary : AppColors.border2,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    )),
                  ),
                  const SizedBox(height: 28),
                  if (_current < _pages.length - 1)
                    NkapButton(
                      label: 'Next',
                      onTap: () => _ctrl.nextPage(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeInOut,
                      ),
                    )
                  else
                    Column(
                      children: [
                        NkapButton(label: 'Get Started', onTap: () { UserPreferences.instance.markIntroSeen(); context.go('/feature-select'); }),
                        const SizedBox(height: 12),
                        NkapButton(label: 'I already have an account', onTap: () { UserPreferences.instance.markIntroSeen(); context.go('/login'); }, outlined: true),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
