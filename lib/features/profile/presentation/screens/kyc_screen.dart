import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/api_service.dart';
import '../../../../core/widgets/nkap_button.dart';
import '../../../../core/widgets/nkap_card.dart';
import '../../../../core/widgets/nkap_text_field.dart';

/// Identity verification flow.
///
/// Shows the user's current status (unsubmitted / pending / approved / rejected)
/// and — when [VerificationStatusOut.can_resubmit] is true — a form to capture
/// CNI number, CNI front photo, CNI back photo, and a selfie.
class KycScreen extends StatefulWidget {
  const KycScreen({super.key});
  @override State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  Map<String, dynamic>? _status;
  bool _loading = true;
  bool _submitting = false;

  final _cniCtrl = TextEditingController();
  _PickedImage? _front;
  _PickedImage? _back;
  _PickedImage? _selfie;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cniCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final s = await ApiService.getMyKycStatus();
      if (mounted) setState(() { _status = s; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pick(_Role role) async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border2,
                  borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 20),
          _sourceTile(Icons.photo_camera_rounded, 'Take photo', ImageSource.camera),
          const SizedBox(height: 10),
          _sourceTile(Icons.photo_library_rounded, 'Choose from gallery', ImageSource.gallery),
        ]),
      ),
    );
    if (source == null) return;
    final file = await picker.pickImage(
      source: source, imageQuality: 82, maxWidth: 1600,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      final picked = _PickedImage(bytes: bytes, filename: file.name);
      switch (role) {
        case _Role.front:  _front  = picked; break;
        case _Role.back:   _back   = picked; break;
        case _Role.selfie: _selfie = picked; break;
      }
    });
  }

  Widget _sourceTile(IconData icon, String label, ImageSource src) =>
      GestureDetector(
        onTap: () => Navigator.pop(context, src),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Text(label, style: GoogleFonts.hankenGrotesk(
                fontSize: 14, fontWeight: FontWeight.w700,
                color: AppColors.text1)),
          ]),
        ),
      );

  Future<void> _submit() async {
    final cni = _cniCtrl.text.trim();
    if (cni.length < 3) {
      _snack('Enter your CNI number', error: true);
      return;
    }
    if (_front == null || _back == null || _selfie == null) {
      _snack('Add all three photos to continue', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final s = await ApiService.submitKyc(
        cniNumber: cni,
        frontBytes: _front!.bytes,   frontFilename: _front!.filename,
        backBytes:  _back!.bytes,    backFilename:  _back!.filename,
        selfieBytes: _selfie!.bytes, selfieFilename: _selfie!.filename,
      );
      if (mounted) {
        setState(() {
          _status = s;
          _front = null; _back = null; _selfie = null;
          _cniCtrl.clear();
        });
        _snack('Submitted! We\'ll review and notify you.');
      }
    } catch (e) {
      _snack(_extractError(e), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _extractError(Object e) {
    final s = e.toString();
    final m = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(s);
    return m?.group(1) ?? 'Submission failed. Try again.';
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w600)),
      backgroundColor: error ? AppColors.danger : AppColors.primary.withOpacity(0.95),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface1, elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.text1),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Verify Identity', style: GoogleFonts.hankenGrotesk(
            color: AppColors.text1, fontWeight: FontWeight.w800, fontSize: 17)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _statusBanner(),
                const SizedBox(height: 16),
                if (_canSubmit) _form() else _hint(),
              ]),
            ),
    );
  }

  bool get _canSubmit {
    final s = _status?['status'] as String? ?? 'unsubmitted';
    if (s == 'unsubmitted') return true;
    return (_status?['can_resubmit'] as bool?) ?? false;
  }

  Widget _statusBanner() {
    final s = _status?['status'] as String? ?? 'unsubmitted';
    final (IconData icon, Color color, String title, String body) info = switch (s) {
      'approved' => (
        Icons.verified_rounded,
        AppColors.primary,
        'Verified',
        'Your identity has been confirmed. You\'re cleared to join groups and receive payouts.',
      ),
      'pending' => (
        Icons.hourglass_top_rounded,
        AppColors.accent,
        'Under review',
        'We\'re checking your documents. This usually takes 1–2 business days.',
      ),
      'rejected' => (
        Icons.error_outline_rounded,
        AppColors.danger,
        'Not approved',
        (_status?['reviewer_notes'] as String?)?.trim().isNotEmpty == true
            ? _status!['reviewer_notes']
            : 'Your submission couldn\'t be approved. Please resubmit with clearer photos.',
      ),
      _ => (
        Icons.badge_outlined,
        AppColors.info,
        'Verify your identity',
        'Required to join njangi groups and receive payouts. Submit your CNI and a selfie.',
      ),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: info.$2.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: info.$2.withOpacity(0.35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(info.$1, color: info.$2, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(info.$3, style: GoogleFonts.hankenGrotesk(
              fontSize: 14, fontWeight: FontWeight.w800, color: info.$2)),
          const SizedBox(height: 4),
          Text(info.$4, style: GoogleFonts.hankenGrotesk(
              fontSize: 12, color: AppColors.text2, height: 1.45)),
          if ((_status?['cni_number'] as String?)?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text('CNI: ${_status!['cni_number']}',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 11, color: AppColors.text3,
                    fontWeight: FontWeight.w600)),
          ],
        ])),
      ]),
    );
  }

  Widget _hint() => NkapCard(
    child: Row(children: [
      Icon(Icons.info_outline_rounded, color: AppColors.text3, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(
        'Nothing for you to do here right now.',
        style: GoogleFonts.hankenGrotesk(fontSize: 12.5, color: AppColors.text2),
      )),
    ]),
  );

  Widget _form() => NkapCard(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Your documents', style: GoogleFonts.hankenGrotesk(
          fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.text1)),
      const SizedBox(height: 4),
      Text('We use these only to verify it\'s really you. Photos stay private.',
          style: GoogleFonts.hankenGrotesk(fontSize: 11.5, color: AppColors.text3, height: 1.4)),
      const SizedBox(height: 16),
      NkapTextField(
        label: 'CNI number',
        hint: 'e.g. 1234567890',
        controller: _cniCtrl,
        keyboardType: TextInputType.text,
        prefixIcon: Icon(Icons.badge_rounded, size: 18, color: AppColors.text3),
      ),
      const SizedBox(height: 16),
      _docPicker('CNI — front', _front, _Role.front),
      const SizedBox(height: 10),
      _docPicker('CNI — back',  _back,  _Role.back),
      const SizedBox(height: 10),
      _docPicker('Selfie',      _selfie, _Role.selfie),
      const SizedBox(height: 18),
      NkapButton(
        label: _submitting ? 'Submitting...' : 'Submit for review',
        icon: Icons.send_rounded,
        loading: _submitting,
        onTap: _submitting ? null : _submit,
      ),
    ]),
  );

  Widget _docPicker(String label, _PickedImage? image, _Role role) {
    final has = image != null;
    return GestureDetector(
      onTap: () => _pick(role),
      child: Container(
        height: 78,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: has ? AppColors.primary.withOpacity(0.5) : AppColors.border2,
          ),
        ),
        child: Row(children: [
          Container(
            width: 58, height: 58,
            decoration: BoxDecoration(
              color: AppColors.surface4,
              borderRadius: BorderRadius.circular(10),
            ),
            child: has
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(image.bytes, fit: BoxFit.cover))
                : Icon(Icons.add_a_photo_rounded,
                    color: AppColors.text3, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label, style: GoogleFonts.hankenGrotesk(
                fontSize: 13, fontWeight: FontWeight.w700,
                color: AppColors.text1)),
            const SizedBox(height: 3),
            Text(has ? 'Tap to replace' : 'Tap to add',
                style: GoogleFonts.hankenGrotesk(
                    fontSize: 11.5,
                    color: has ? AppColors.primary : AppColors.text3)),
          ])),
          if (has)
            const Icon(Icons.check_circle_rounded,
                color: AppColors.primary, size: 20),
        ]),
      ),
    );
  }
}

enum _Role { front, back, selfie }

class _PickedImage {
  final Uint8List bytes;
  final String filename;
  _PickedImage({required this.bytes, required this.filename});
}
