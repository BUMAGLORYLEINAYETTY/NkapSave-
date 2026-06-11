import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

class NkapTextField extends StatefulWidget {
  final String label;
  final String? hint;
  final bool password;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final void Function(String)? onChanged;

  const NkapTextField({
    super.key,
    required this.label,
    this.hint,
    this.password = false,
    this.controller,
    this.keyboardType,
    this.validator,
    this.prefixIcon,
    this.suffixIcon,
    this.onChanged,
  });

  @override
  State<NkapTextField> createState() => _NkapTextFieldState();
}

class _NkapTextFieldState extends State<NkapTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: GoogleFonts.hankenGrotesk(
          fontSize: 11.5, fontWeight: FontWeight.w700,
          color: AppColors.text2, letterSpacing: 0.2,
        )),
        const SizedBox(height: 7),
        TextFormField(
          controller: widget.controller,
          obscureText: widget.password && _obscure,
          keyboardType: widget.keyboardType,
          onChanged: widget.onChanged,
          validator: widget.validator,
          style: GoogleFonts.hankenGrotesk(fontSize: 14, color: AppColors.text1),
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: widget.prefixIcon,
            suffixIcon: widget.password
                ? IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: AppColors.text3, size: 18,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  )
                : widget.suffixIcon,
          ),
        ),
      ],
    );
  }
}
