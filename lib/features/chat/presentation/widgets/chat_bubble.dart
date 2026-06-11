import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../domain/entities/chat_message.dart';
import 'chat_action_cards.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == ChatRole.user;
    return Padding(
      padding: EdgeInsets.fromLTRB(isUser ? 60 : 12, 4, isUser ? 12 : 60, 4),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) _botAvatar(),
              if (!isUser) const SizedBox(width: 8),
              Flexible(child: _textBubble(isUser)),
            ],
          ),
          if (message.payload != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.only(left: isUser ? 0 : 36),
              child: ChatActionCard(payload: message.payload!),
            ),
          ],
        ],
      ),
    );
  }

  Widget _botAvatar() => Container(
    width: 28, height: 28,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: AppColors.heroBrandGradient),
      border: Border.all(color: AppColors.primaryMid),
      boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 8)],
    ),
    child: const Icon(Icons.smart_toy_rounded, color: AppColors.heroFg, size: 14),
  );

  Widget _textBubble(bool isUser) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: isUser ? AppColors.primary : AppColors.surface2,
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft: Radius.circular(isUser ? 16 : 4),
        bottomRight: Radius.circular(isUser ? 4 : 16),
      ),
      border: isUser ? null : Border.all(color: AppColors.border1),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message.text,
          style: AppTextStyles.body.copyWith(
            color: isUser ? AppColors.heroFg : AppColors.text1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          DateFormat('h:mm a').format(message.time),
          style: AppTextStyles.caption.copyWith(
            color: isUser ? AppColors.heroFgDim : AppColors.text3,
          ),
        ),
      ],
    ),
  );
}
