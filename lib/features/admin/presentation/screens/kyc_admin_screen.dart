import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/widgets/nkap_button.dart';
import '../../../../core/widgets/nkap_card.dart';

/// Reviewer-only screen for processing CNI / KYC submissions.
///
/// Access is gated by the backend — non-reviewers calling
/// `/kyc/admin/*` get a 403, which we render as a friendly "you
/// don't have access" panel. Approving an item flips the underlying
/// user's `is_verified` to true on the backend, which unlocks njangi
/// money actions for them.
class KycAdminScreen extends StatefulWidget {
  const KycAdminScreen({super.key});
  @override
  State<KycAdminScreen> createState() => _KycAdminScreenState();
}

class _KycAdminScreenState extends State<KycAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  // One list per tab — null while loading, a (possibly empty) list when loaded,
  // a string when the fetch errored (e.g. 403 for non-reviewers).
  List<Map<String, dynamic>>? _pending;
  List<Map<String, dynamic>>? _approved;
  List<Map<String, dynamic>>? _rejected;
  String? _error;
  bool _firstLoad = true;

  static const _statuses = ['pending', 'approved', 'rejected'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
    _refresh();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _error = null;
      if (_firstLoad) {
        _pending = null;
        _approved = null;
        _rejected = null;
      }
    });
    try {
      final results = await Future.wait([
        ApiService.listKycPending(),                      // status=null → pending
        ApiService.listKycPending(status: 'approved'),
        ApiService.listKycPending(status: 'rejected'),
      ]);
      if (!mounted) return;
      setState(() {
        _pending  = results[0];
        _approved = results[1];
        _rejected = results[2];
        _firstLoad = false;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _error = msg.contains('403')
            ? 'Reviewer access only. Ask an admin to enable this on your account.'
            : 'Could not load the review queue. Pull to retry.';
        _firstLoad = false;
      });
    }
  }

  List<Map<String, dynamic>>? _currentList() {
    switch (_statuses[_tabs.index]) {
      case 'approved': return _approved;
      case 'rejected': return _rejected;
      default:          return _pending;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface1,
        elevation: 0,
        title: Text('ID Verification', style: GoogleFonts.hankenGrotesk(
            color: AppColors.text1, fontWeight: FontWeight.w800, fontSize: 17)),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.text3,
          indicatorColor: AppColors.primary,
          labelStyle: GoogleFonts.hankenGrotesk(
              fontWeight: FontWeight.w800, fontSize: 13),
          tabs: [
            Tab(text: 'Pending'  + _badge(_pending)),
            Tab(text: 'Approved' + _badge(_approved)),
            Tab(text: 'Rejected' + _badge(_rejected)),
          ],
        ),
      ),
      body: _error != null
          ? _errorPanel(_error!)
          : RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.surface1,
              onRefresh: _refresh,
              child: _body(),
            ),
    );
  }

  String _badge(List? list) {
    if (list == null) return '';
    return ' (${list.length})';
  }

  Widget _body() {
    final list = _currentList();
    if (list == null) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (list.isEmpty) {
      final status = _statuses[_tabs.index];
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(child: Column(children: [
            Icon(Icons.fact_check_outlined,
                size: 48, color: AppColors.text3),
            const SizedBox(height: 12),
            Text('No $status submissions',
                style: GoogleFonts.hankenGrotesk(
                    color: AppColors.text2, fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              status == 'pending'
                  ? 'New ID submissions will appear here.'
                  : 'History for $status will appear here.',
              style: GoogleFonts.hankenGrotesk(
                  color: AppColors.text3, fontSize: 12),
            ),
          ])),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _row(list[i]),
    );
  }

  Widget _errorPanel(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline_rounded, size: 48, color: AppColors.text3),
            const SizedBox(height: 14),
            Text(msg, textAlign: TextAlign.center,
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 13, color: AppColors.text2, height: 1.45)),
            const SizedBox(height: 16),
            NkapButton(
              label: 'Try again',
              icon: Icons.refresh_rounded,
              onTap: () { setState(() => _firstLoad = true); _refresh(); },
            ),
          ]),
        ),
      );

  Widget _row(Map<String, dynamic> v) {
    final name   = (v['user_name'] ?? 'Unknown').toString();
    final cni    = (v['cni_number'] ?? '').toString();
    final phone  = (v['user_phone'] ?? '').toString();
    final status = (v['status'] ?? 'pending').toString();
    final submitted = _shortDate(v['submitted_at']?.toString());
    final selfieUrl = v['selfie_url']?.toString();

    final (Color color, IconData icon) = switch (status) {
      'approved' => (AppColors.primary, Icons.verified_rounded),
      'rejected' => (AppColors.danger, Icons.cancel_rounded),
      _           => (AppColors.accent, Icons.hourglass_top_rounded),
    };

    return NkapCard(
      onTap: () => _openDetail(v),
      child: Row(children: [
        // Selfie thumbnail (or a placeholder) so the reviewer can match
        // face → CNI at a glance even before opening the full card.
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border2),
          ),
          clipBehavior: Clip.antiAlias,
          child: selfieUrl != null && selfieUrl.isNotEmpty
              ? Image.network(ApiService.kycDocUrl(selfieUrl), fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      Icon(Icons.person_outline,
                          color: AppColors.text3, size: 24))
              : Icon(Icons.person_outline,
                  color: AppColors.text3, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 14, fontWeight: FontWeight.w800,
                  color: AppColors.text1)),
          const SizedBox(height: 2),
          Text('CNI $cni', style: GoogleFonts.hankenGrotesk(
              fontSize: 12, color: AppColors.text2)),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(phone, style: GoogleFonts.hankenGrotesk(
                fontSize: 11, color: AppColors.text3)),
          ],
        ])),
        const SizedBox(width: 8),
        Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 4),
              Text(submitted,
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 10, color: AppColors.text3)),
            ]),
      ]),
    );
  }

  String _shortDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year.toString().substring(2)}';
  }

  Future<void> _openDetail(Map<String, dynamic> v) async {
    final action = await showModalBottomSheet<_ReviewAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ReviewSheet(v: v),
    );
    if (action == null || !mounted) return;
    await _runReview(v, action);
  }

  Future<void> _runReview(Map<String, dynamic> v, _ReviewAction a) async {
    final id = v['id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      if (a.approve) {
        await ApiService.approveKyc(id, notes: a.notes);
      } else {
        await ApiService.rejectKyc(id, notes: a.notes);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          a.approve ? 'Approved ${v['user_name']}' : 'Rejected ${v['user_name']}',
          style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700),
        ),
        backgroundColor: (a.approve ? AppColors.primary : AppColors.danger)
            .withOpacity(0.95),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Review failed. Try again.',
            style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.danger,
      ));
    }
  }
}

class _ReviewAction {
  final bool approve;
  final String? notes;
  const _ReviewAction({required this.approve, this.notes});
}

class _ReviewSheet extends StatefulWidget {
  final Map<String, dynamic> v;
  const _ReviewSheet({required this.v});
  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _notes = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.v;
    final isPending = (v['status'] ?? 'pending') == 'pending';
    final name  = (v['user_name'] ?? 'Unknown').toString();
    final email = (v['user_email'] ?? '').toString();
    final phone = (v['user_phone'] ?? '').toString();
    final cni   = (v['cni_number'] ?? '').toString();
    final notesExisting = (v['reviewer_notes'] ?? '').toString();
    final frontUrl  = v['cni_front_url']?.toString();
    final backUrl   = v['cni_back_url']?.toString();
    final selfieUrl = v['selfie_url']?.toString();

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border2,
                  borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 14),
          Expanded(child: ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            children: [
              Text(name, style: GoogleFonts.hankenGrotesk(
                  fontSize: 18, fontWeight: FontWeight.w800,
                  color: AppColors.text1)),
              const SizedBox(height: 4),
              _kv('Email', email),
              if (phone.isNotEmpty) _kv('Phone', phone),
              _kv('CNI number', cni),
              const SizedBox(height: 16),
              Text('CNI — front',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 12, fontWeight: FontWeight.w800,
                      color: AppColors.text2)),
              const SizedBox(height: 6),
              _photo(frontUrl),
              const SizedBox(height: 14),
              Text('CNI — back',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 12, fontWeight: FontWeight.w800,
                      color: AppColors.text2)),
              const SizedBox(height: 6),
              _photo(backUrl),
              const SizedBox(height: 14),
              Text('Selfie',
                  style: GoogleFonts.hankenGrotesk(
                      fontSize: 12, fontWeight: FontWeight.w800,
                      color: AppColors.text2)),
              const SizedBox(height: 6),
              _photo(selfieUrl),
              const SizedBox(height: 18),
              if (!isPending && notesExisting.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface3,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border2),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Reviewer notes',
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 11, fontWeight: FontWeight.w800,
                            color: AppColors.text3)),
                    const SizedBox(height: 4),
                    Text(notesExisting,
                        style: GoogleFonts.hankenGrotesk(
                            fontSize: 13, color: AppColors.text1)),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
              if (isPending) ...[
                TextField(
                  controller: _notes,
                  maxLines: 3, maxLength: 500,
                  decoration: InputDecoration(
                    hintText: 'Notes (optional — shown to the user if rejected)',
                    hintStyle: GoogleFonts.hankenGrotesk(
                        fontSize: 13, color: AppColors.text3),
                    filled: true,
                    fillColor: AppColors.surface2,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border2),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.border2),
                    ),
                  ),
                ),
              ],
            ],
          )),
          if (isPending)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(children: [
                  Expanded(child: NkapButton(
                    label: _busy ? 'Working…' : 'Reject',
                    color: AppColors.danger,
                    outlined: true,
                    loading: _busy,
                    onTap: _busy ? null : () => _close(approve: false),
                  )),
                  const SizedBox(width: 12),
                  Expanded(child: NkapButton(
                    label: _busy ? 'Working…' : 'Approve',
                    icon: Icons.check_rounded,
                    loading: _busy,
                    onTap: _busy ? null : () => _close(approve: true),
                  )),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  void _close({required bool approve}) {
    setState(() => _busy = true);
    Navigator.of(context).pop(_ReviewAction(
      approve: approve,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    ));
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          Text('$k: ',
              style: GoogleFonts.hankenGrotesk(
                  fontSize: 12.5, color: AppColors.text3,
                  fontWeight: FontWeight.w700)),
          Flexible(
            child: Text(v,
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 12.5, color: AppColors.text1)),
          ),
        ]),
      );

  Widget _photo(String? relativeUrl) {
    if (relativeUrl == null || relativeUrl.isEmpty) {
      return _photoPlaceholder('Missing image');
    }
    final url = ApiService.kycDocUrl(relativeUrl);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, p) => p == null
              ? child
              : Container(
                  color: AppColors.surface3,
                  child: const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary, strokeWidth: 2))),
          errorBuilder: (_, __, ___) => _photoPlaceholder('Could not load'),
        ),
      ),
    );
  }

  Widget _photoPlaceholder(String label) => Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border2),
        ),
        child: Center(
            child: Text(label,
                style: GoogleFonts.hankenGrotesk(
                    color: AppColors.text3, fontSize: 12))),
      );
}
