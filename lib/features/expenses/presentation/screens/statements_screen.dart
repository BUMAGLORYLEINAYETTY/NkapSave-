import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/services/download_helper.dart';
import '../../../../core/widgets/nkap_button.dart';

class StatementsScreen extends StatefulWidget {
  const StatementsScreen({super.key});
  @override
  State<StatementsScreen> createState() => _StatementsScreenState();
}

class _StatementsScreenState extends State<StatementsScreen> {
  bool _loading = true;
  bool _generating = false;
  String? _error;
  List<_Stmt> _items = const [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await ApiService.listStatements();
      if (!mounted) return;
      setState(() {
        _items = list.cast<Map<String, dynamic>>()
            .map(_Stmt.fromJson).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = _apiErr(e); });
    }
  }

  Future<void> _generateLastMonth() async {
    final now = DateTime.now();
    final last = DateTime(now.year, now.month - 1, 1);
    setState(() => _generating = true);
    try {
      await ApiService.generateStatement(
          year: last.year, month: last.month);
      if (!mounted) return;
      _toast(context, 'Statement generated.');
      await _load();
    } catch (e) {
      if (mounted) _toast(context, _apiErr(e), error: true);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _download(_Stmt s) async {
    _toast(context, 'Preparing ${s.label}…');
    try {
      final file = await ApiService.downloadStatement(s.id);
      try {
        await downloadBytes(
          bytes: file.bytes,
          filename: file.filename,
          mimeType: file.mimeType,
        );
      } on UnsupportedError catch (e) {
        if (mounted) _toast(context, e.message ?? 'Not supported here', error: true);
      }
    } catch (e) {
      if (mounted) _toast(context, _apiErr(e), error: true);
    }
  }

  Future<void> _confirmDelete(_Stmt s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface2,
        title: Text('Delete statement?',
            style: GoogleFonts.hankenGrotesk(
                fontWeight: FontWeight.w800, color: AppColors.text1)),
        content: Text('This removes the saved PDF for ${s.label}. You can '
            'always regenerate it later from any month with activity.',
            style: GoogleFonts.hankenGrotesk(
                color: AppColors.text2, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.hankenGrotesk(color: AppColors.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete',
                style: GoogleFonts.hankenGrotesk(
                    color: AppColors.danger, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.deleteStatement(s.id);
      _toast(context, 'Removed.');
      _load();
    } catch (e) {
      if (mounted) _toast(context, _apiErr(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.bg,
    appBar: AppBar(
      backgroundColor: AppColors.surface1,
      elevation: 0,
      title: Text('Statements', style: GoogleFonts.hankenGrotesk(
          color: AppColors.text1, fontWeight: FontWeight.w800, fontSize: 18)),
      actions: [
        IconButton(
          icon:  Icon(Icons.refresh_rounded,
              color: AppColors.text2, size: 20),
          onPressed: _load,
        ),
      ],
    ),
    body: RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.surface1,
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2))
          : _error != null
              ? _buildError(_error!)
              : _items.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
    ),
  );

  Widget _buildList() => ListView.separated(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
    itemCount: _items.length + 1,
    separatorBuilder: (_, __) => const SizedBox(height: 10),
    itemBuilder: (_, i) {
      if (i == 0) return _buildHeaderCard();
      final s = _items[i - 1];
      return _buildCard(s);
    },
  );

  Widget _buildHeaderCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        AppColors.primary.withOpacity(0.10),
        AppColors.primary.withOpacity(0.03),
      ]),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.primary.withOpacity(0.22)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.receipt_long_rounded,
            color: AppColors.primary, size: 18),
        const SizedBox(width: 8),
        Text('Generate last month',
            style: GoogleFonts.hankenGrotesk(
                fontWeight: FontWeight.w800, fontSize: 13,
                color: AppColors.primary)),
      ]),
      const SizedBox(height: 6),
      Text(
        'Don\'t wait for the 1st — pull last month\'s statement on demand. '
        'It\'s sent to your email + WhatsApp if available, and always saved here.',
        style: GoogleFonts.hankenGrotesk(
            fontSize: 11.5, color: AppColors.text2, height: 1.5),
      ),
      const SizedBox(height: 12),
      NkapButton(
        label: 'Generate now',
        icon: Icons.auto_awesome_rounded,
        loading: _generating,
        onTap: _generating ? null : _generateLastMonth,
      ),
    ]),
  );

  Widget _buildCard(_Stmt s) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.border1),
    ),
    child: Column(children: [
      Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.danger.withOpacity(0.14),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.picture_as_pdf_rounded,
              color: AppColors.danger, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.label, style: GoogleFonts.hankenGrotesk(
              fontSize: 14, fontWeight: FontWeight.w800,
              color: AppColors.text1)),
          const SizedBox(height: 2),
          Text('${_formatSize(s.sizeBytes)} · ${_formatWhen(s.createdAt)}',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 11, color: AppColors.text3)),
        ])),
        IconButton(
          icon:  Icon(Icons.delete_outline_rounded,
              color: AppColors.text3, size: 18),
          onPressed: () => _confirmDelete(s),
        ),
        IconButton(
          icon: const Icon(Icons.download_rounded,
              color: AppColors.primary, size: 20),
          onPressed: () => _download(s),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _ChannelBadge(
          icon: Icons.email_rounded,
          label: 'Email',
          state: s.channels['email'] ?? 'skipped',
        ),
        const SizedBox(width: 6),
        _ChannelBadge(
          icon: Icons.chat_rounded,
          label: 'WhatsApp',
          state: s.channels['whatsapp'] ?? 'skipped',
        ),
        const SizedBox(width: 6),
        _ChannelBadge(
          icon: Icons.phone_iphone_rounded,
          label: 'In-app',
          state: s.channels['in_app'] ?? 'sent',
        ),
      ]),
    ]),
  );

  Widget _buildEmpty() => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(16, 60, 16, 100),
    children: [
      _buildHeaderCard(),
      const SizedBox(height: 22),
      Center(child: Column(children: [
         Icon(Icons.inbox_rounded,
            size: 36, color: AppColors.text3),
        const SizedBox(height: 10),
        Text('No statements yet',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: AppColors.text1)),
        const SizedBox(height: 4),
        Text(
          'The first statement arrives on the 1st of each month, or '
          'tap "Generate now" above to pull last month right away.',
          textAlign: TextAlign.center,
          style: GoogleFonts.hankenGrotesk(
              fontSize: 12, color: AppColors.text3, height: 1.5),
        ),
      ])),
    ],
  );

  Widget _buildError(String msg) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      const SizedBox(height: 120),
      Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(children: [
          const Icon(Icons.error_outline_rounded,
              color: AppColors.danger, size: 36),
          const SizedBox(height: 12),
          Text("Couldn't load statements",
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 16, fontWeight: FontWeight.w800,
                  color: AppColors.text1)),
          const SizedBox(height: 6),
          Text(msg, textAlign: TextAlign.center,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 12, color: AppColors.text3)),
          const SizedBox(height: 20),
          NkapButton(label: 'Retry', onTap: _load),
        ]),
      )),
    ],
  );
}

class _ChannelBadge extends StatelessWidget {
  final IconData icon;
  final String label, state;       // 'sent' | 'failed' | 'skipped'
  const _ChannelBadge({required this.icon, required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    final (color, tooltipText) = switch (state) {
      'sent'    => (AppColors.primary, 'Sent to $label'),
      'failed'  => (AppColors.danger,  '$label delivery failed'),
      _         => (AppColors.text3,   '$label not configured for you'),
    };
    return Tooltip(
      message: tooltipText,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            state == 'sent' ? label
            : state == 'failed' ? '$label ✕'
            : '$label —',
            style: GoogleFonts.hankenGrotesk(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: color),
          ),
        ]),
      ),
    );
  }
}

// ─── Model ───────────────────────────────────────────────────────────────────

class _Stmt {
  final String id, label;
  final int year, month, sizeBytes;
  final Map<String, dynamic> channels;
  final DateTime? createdAt;
  const _Stmt({
    required this.id, required this.label,
    required this.year, required this.month, required this.sizeBytes,
    required this.channels, this.createdAt,
  });
  factory _Stmt.fromJson(Map<String, dynamic> j) => _Stmt(
        id:       j['id'] as String,
        label:    j['period_label'] as String,
        year:     j['period_year'] as int,
        month:    j['period_month'] as int,
        sizeBytes: j['size_bytes'] as int,
        channels: Map<String, dynamic>.from(j['channels'] as Map? ?? {}),
        createdAt: j['created_at'] != null
            ? DateTime.tryParse(j['created_at'] as String)
            : null,
      );
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

String _formatSize(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

String _formatWhen(DateTime? t) {
  if (t == null) return '';
  final d = t.toLocal();
  return '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}

String _apiErr(Object e, [String fallback = 'Something went wrong']) {
  if (e is DioException) {
    final detail = e.response?.data is Map ? e.response?.data['detail'] : null;
    if (detail is String) return detail;
  }
  return fallback;
}

void _toast(BuildContext ctx, String msg, {bool error = false}) {
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
    content: Text(msg, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
    backgroundColor:
        (error ? AppColors.danger : AppColors.primary).withOpacity(0.9),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}
