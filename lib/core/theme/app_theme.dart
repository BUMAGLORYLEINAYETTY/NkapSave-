import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import '../constants/app_palette.dart';

class AppTheme {
  /// Light Material theme stub. Most screens hard-code [AppColors] today,
  /// so visually this only changes Material-aware widgets (text fields,
  /// dialogs, system overlays). A full light palette migration is
  /// tracked separately — once it lands, every screen will respect this.
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    extensions: const [AppPalette.light],
    scaffoldBackgroundColor: const Color(0xFFF8F9FF),
    colorScheme: const ColorScheme.light(
      primary:   AppColors.primary,
      secondary: AppColors.accent,
      background: Color(0xFFF8F9FF),
      surface:    Colors.white,
      error:      AppColors.danger,
      onPrimary:   Color(0xFFFFFFFF),
      onSecondary: Color(0xFF0B1C30),
      onBackground: Color(0xFF0B1C30),
      onSurface:    Color(0xFF0B1C30),
    ),
    textTheme: GoogleFonts.hankenGroteskTextTheme(ThemeData.light().textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      iconTheme: const IconThemeData(color: Color(0xFF0B1C30)),
      titleTextStyle: GoogleFonts.hankenGrotesk(
        fontSize: 17, fontWeight: FontWeight.w700,
        color: const Color(0xFF0B1C30),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0x14000000), thickness: 1,
    ),
  );

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    extensions: const [AppPalette.dark],
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      background: AppColors.bg,
      surface: AppColors.surface2,
      error: AppColors.danger,
      onPrimary: const Color(0xFFFFFFFF),
      onSecondary: const Color(0xFF0B1C30),
      onBackground: AppColors.text1,
      onSurface: AppColors.text1,
    ),
    textTheme: GoogleFonts.hankenGroteskTextTheme(ThemeData.dark().textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface1,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      iconTheme:  IconThemeData(color: AppColors.text1),
      titleTextStyle: GoogleFonts.hankenGrotesk(
        fontSize: 17, fontWeight: FontWeight.w700,
        color: AppColors.text1,
      ),
    ),
    bottomNavigationBarTheme:  BottomNavigationBarThemeData(
      backgroundColor: AppColors.surface1,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.text3,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    cardTheme: CardTheme(
      color: AppColors.surface2,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side:  BorderSide(color: AppColors.border1, width: 1),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide:  BorderSide(color: AppColors.border2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide:  BorderSide(color: AppColors.border2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      labelStyle:  TextStyle(color: AppColors.text2),
      hintStyle:  TextStyle(color: AppColors.text3),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        textStyle: GoogleFonts.hankenGrotesk(fontWeight: FontWeight.w800, fontSize: 14),
        elevation: 0,
      ),
    ),
    dividerTheme:  DividerThemeData(
      color: AppColors.border1, thickness: 1,
    ),
  );
}
