import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';

/// Live chat for one njangi group.
///
/// Two transports run side-by-side:
///   * History loads via REST on open (oldest → newest).
///   * Live messages stream over the group's WebSocket. The same WS is
///     used for sending. When the socket isn't connected (yet, or after
///     a drop) we fall back to the REST POST so the user never sees a
///     blocked send button.
class GroupChatScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final Set<String> _seenIds = <String>{};
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  bool _loading = true;
  bool _connected = false;
  bool _sending = false;
  Timer? _reconnectTimer;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _connect();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _wsSub?.cancel();
    _channel?.sink.close();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final list = await ApiService.getGroupMessages(widget.groupId);
      if (!mounted) return;
      setState(() {
        for (final m in list) {
          final id = m['id']?.toString();
          if (id != null && _seenIds.add(id)) _messages.add(m);
        }
        _loading = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _connect() {
    final url = ApiService.groupChatWsUrl(widget.groupId);
    if (url == null) return;
    try {
      final ch = WebSocketChannel.connect(Uri.parse(url));
      _channel = ch;
      _wsSub = ch.stream.listen(
        _onWsData,
        onDone: _onWsClosed,
        onError: (_) => _onWsClosed(),
        cancelOnError: true,
      );
      setState(() => _connected = true);
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onWsData(dynamic raw) {
    try {
      final data = raw is String
          ? jsonDecode(raw) as Map<String, dynamic>
          : Map<String, dynamic>.from(raw as Map);
      if (data['type'] != null && data['type'] != 'message') return;
      final id = data['id']?.toString();
      if (id == null || !_seenIds.add(id)) return;
      setState(() => _messages.add(data));
      _scrollToBottom();
    } catch (_) {/* malformed frame — ignore */}
  }

  void _onWsClosed() {
    if (!mounted) return;
    setState(() => _connected = false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _connect();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    _input.clear();

    final ch = _channel;
    if (_connected && ch != null) {
      try {
        ch.sink.add(jsonEncode({'content': text}));
      } catch (_) {
        await _restFallbackSend(text);
      }
    } else {
      await _restFallbackSend(text);
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _restFallbackSend(String text) async {
    try {
      final m = await ApiService.sendGroupMessage(widget.groupId, text);
      if (!mounted) return;
      final id = m['id']?.toString();
      // The WS broadcast also delivers this back; dedupe on id.
      if (id != null && _seenIds.add(id)) {
        setState(() => _messages.add({...m, 'is_me': true}));
        _scrollToBottom();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to send message',
            style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface1,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.text1),
        title: Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.groupName,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.hankenGrotesk(
                      color: AppColors.text1,
                      fontWeight: FontWeight.w800, fontSize: 16)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _connected ? AppColors.primary : AppColors.text3,
                  ),
                ),
                const SizedBox(width: 6),
                Text(_connected ? 'Live' : 'Reconnecting…',
                    style: GoogleFonts.hankenGrotesk(
                        fontSize: 11, color: AppColors.text3)),
              ]),
            ],
          )),
        ]),
      ),
      body: SafeArea(child: Column(children: [
        Expanded(child: _loading
            ? Center(child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(AppColors.primary)))
            : _messages.isEmpty
                ? _emptyState()
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final m = _messages[i];
                      final prev = i > 0 ? _messages[i - 1] : null;
                      final showHeader = prev == null ||
                          prev['sender_id'] != m['sender_id'];
                      return _MessageBubble(
                        message: m,
                        showHeader: showHeader,
                      );
                    },
                  )),
        _buildComposer(),
      ])),
    );
  }

  Widget _emptyState() => Center(child: Padding(
    padding: const EdgeInsets.all(40),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('💬', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 14),
      Text('Say hi to the group',
          style: GoogleFonts.hankenGrotesk(
              color: AppColors.text2, fontSize: 15,
              fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('Messages here are visible to every member',
          textAlign: TextAlign.center,
          style: GoogleFonts.hankenGrotesk(
              color: AppColors.text3, fontSize: 12)),
    ]),
  ));

  Widget _buildComposer() => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    decoration: BoxDecoration(
      color: AppColors.surface1,
      border: Border(top: BorderSide(color: AppColors.border1)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(child: Container(
        constraints: const BoxConstraints(maxHeight: 140),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border2),
        ),
        child: TextField(
          controller: _input,
          maxLines: null,
          textCapitalization: TextCapitalization.sentences,
          style: GoogleFonts.hankenGrotesk(
              fontSize: 14, color: AppColors.text1),
          decoration: InputDecoration(
            hintText: 'Message…',
            hintStyle: GoogleFonts.hankenGrotesk(
                color: AppColors.text3, fontSize: 14),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _send(),
        ),
      )),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: _send,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary,
            boxShadow: [BoxShadow(
              color: AppColors.primary.withOpacity(0.35),
              blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: _sending
              ? const Center(child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Color(0xFFFFFFFF)))))
              : const Icon(Icons.send_rounded,
                  color: Color(0xFFFFFFFF), size: 20),
        ),
      ),
    ]),
  );
}

class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool showHeader;
  const _MessageBubble({required this.message, required this.showHeader});

  @override
  Widget build(BuildContext context) {
    final isMe = (message['is_me'] ?? false) as bool;
    final content = (message['content'] ?? '').toString();
    final name = (message['sender_name'] ?? '').toString();
    final picPath = message['sender_picture'] as String?;
    final createdAt = message['created_at']?.toString();
    final timeLabel = _formatTime(createdAt);

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: isMe ? AppColors.primary : AppColors.surface2,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isMe ? 16 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(content,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 14, height: 1.35,
                  color: isMe ? const Color(0xFFFFFFFF) : AppColors.text1)),
          if (timeLabel.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(timeLabel,
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 9.5,
                    color: isMe
                        ? const Color(0xFFFFFFFF).withOpacity(0.55)
                        : AppColors.text3)),
          ],
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: showHeader ? 10 : 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            SizedBox(
              width: 28,
              child: showHeader ? _avatar(name, picPath) : const SizedBox(),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (showHeader && !isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 2),
                  child: Text(name,
                      style: GoogleFonts.hankenGrotesk(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: AppColors.text3)),
                ),
              bubble,
            ],
          )),
        ],
      ),
    );
  }

  Widget _avatar(String name, String? picPath) {
    final url = ApiService.pictureUrl(picPath);
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface3,
        image: url.isEmpty
            ? null
            : DecorationImage(image: NetworkImage(url), fit: BoxFit.cover),
      ),
      child: url.isEmpty
          ? Center(child: Text(initial,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11, fontWeight: FontWeight.w800,
                  color: AppColors.text2)))
          : null,
    );
  }

  /// Compact local time. We tolerate any ISO-8601 we get back; on parse
  /// failure we just hide the timestamp rather than crash the bubble.
  String _formatTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final sameDay = dt.year == now.year &&
          dt.month == now.month && dt.day == now.day;
      return sameDay
          ? DateFormat.jm().format(dt)
          : DateFormat('MMM d · HH:mm').format(dt);
    } catch (_) {
      return '';
    }
  }
}
