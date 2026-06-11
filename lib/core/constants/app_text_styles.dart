import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Typography — Hanken Grotesk across all levels (Stitch design system):
/// sharp, contemporary, highly legible. Numerical data (balances, amounts)
/// uses SemiBold/Bold weights for immediate recognition.
class AppTextStyles {
  static TextStyle get h1 => GoogleFonts.hankenGrotesk(
    fontSize: 30, fontWeight: FontWeight.w700,
    color: AppColors.text1, letterSpacing: -0.6,
  );
  static TextStyle get h2 => GoogleFonts.hankenGrotesk(
    fontSize: 22, fontWeight: FontWeight.w700,
    color: AppColors.text1, letterSpacing: -0.3,
  );
  static TextStyle get h3 => GoogleFonts.hankenGrotesk(
    fontSize: 17, fontWeight: FontWeight.w600,
    color: AppColors.text1,
  );
  static TextStyle get h4 => GoogleFonts.hankenGrotesk(
    fontSize: 14, fontWeight: FontWeight.w600,
    color: AppColors.text1,
  );
  static TextStyle get body => GoogleFonts.hankenGrotesk(
    fontSize: 13, fontWeight: FontWeight.w400,
    color: AppColors.text1, height: 1.55,
  );
  static TextStyle get bodyMuted => GoogleFonts.hankenGrotesk(
    fontSize: 12, fontWeight: FontWeight.w400,
    color: AppColors.text2, height: 1.5,
  );
  static TextStyle get caption => GoogleFonts.hankenGrotesk(
    fontSize: 10.5, fontWeight: FontWeight.w400,
    color: AppColors.text3,
  );
  static TextStyle get label => GoogleFonts.hankenGrotesk(
    fontSize: 11, fontWeight: FontWeight.w600,
    color: AppColors.text1, letterSpacing: 0.3,
  );
  static TextStyle get balance => GoogleFonts.hankenGrotesk(
    fontSize: 30, fontWeight: FontWeight.w700,
    color: Colors.white, letterSpacing: -0.8,
  );
  static TextStyle get chip => GoogleFonts.hankenGrotesk(
    fontSize: 10, fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );
}
