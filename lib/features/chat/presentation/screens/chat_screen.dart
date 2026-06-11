import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body:  Center(
        child: Text('ChatScreen — Coming Soon',
            style: TextStyle(color: AppColors.text2)),
      ),
    );
  }
}
