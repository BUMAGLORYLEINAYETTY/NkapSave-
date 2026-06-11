import 'package:flutter/material.dart';

/// Theme-aware palette delivered through Material 3's [ThemeExtension] hook.
///
/// Read it from anywhere with:
///   `final p = Theme.of(context).palette;`  (see the extension below)
///
/// Tokens that flip between light and dark live here (backgrounds, surfaces,
/// text, borders). Semantic accents (primary, accent, danger, info, purple)
/// stay as compile-time constants on [AppColors] because they read the same
/// on both themes.
class AppPalette extends ThemeExtension<AppPalette> {
  final Color bg;
  final Color surface1, surface2, surface3, surface4;
  final Color text1, text2, text3;
  final Color border1, border2, border3;
  /// Used as the foreground on top of cards that use primary tints — same
  /// black-ish on both light and dark.
  final Color onPrimary;

  const AppPalette({
    required this.bg,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.surface4,
    required this.text1,
    required this.text2,
    required this.text3,
    required this.border1,
    required this.border2,
    required this.border3,
    required this.onPrimary,
  });

  // ── Concrete palettes ──────────────────────────────────────
  // Dark: green-tinted charcoal, derived from the (light-only) Stitch system.
  static const dark = AppPalette(
    bg:        Color(0xFF0C1210),
    surface1:  Color(0xFF121A16),
    surface2:  Color(0xFF18221D),
    surface3:  Color(0xFF1F2C25),
    surface4:  Color(0xFF27362E),
    text1:     Color(0xFFECF3EE),
    text2:     Color(0x8CECF3EE),
    text3:     Color(0x4DECF3EE),
    border1:   Color(0x0FFFFFFF),
    border2:   Color(0x1CFFFFFF),
    border3:   Color(0x2EFFFFFF),
    onPrimary: Color(0xFFFFFFFF), // white reads on Success Green brand
  );

  // Light: straight from the Stitch design system — cool near-white canvas,
  // pure-white cards, tonal blue-tinted containers, deep navy-charcoal text.
  static const light = AppPalette(
    bg:        Color(0xFFF8F9FF), // surface — cool canvas
    surface1:  Color(0xFFFFFFFF), // surface-container-lowest — cards
    surface2:  Color(0xFFEFF4FF), // surface-container-low
    surface3:  Color(0xFFE5EEFF), // surface-container
    surface4:  Color(0xFFDCE9FF), // surface-container-high
    text1:     Color(0xFF0B1C30), // on-surface
    text2:     Color(0x8C0B1C30),
    text3:     Color(0x4D0B1C30),
    border1:   Color(0x0F0B1C30),
    border2:   Color(0x1F0B1C30),
    border3:   Color(0x330B1C30),
    onPrimary: Color(0xFFFFFFFF), // white reads on Success Green brand
  );

  @override
  AppPalette copyWith({
    Color? bg, Color? surface1, Color? surface2, Color? surface3,
    Color? surface4, Color? text1, Color? text2, Color? text3,
    Color? border1, Color? border2, Color? border3, Color? onPrimary,
  }) => AppPalette(
        bg:       bg       ?? this.bg,
        surface1: surface1 ?? this.surface1,
        surface2: surface2 ?? this.surface2,
        surface3: surface3 ?? this.surface3,
        surface4: surface4 ?? this.surface4,
        text1:    text1    ?? this.text1,
        text2:    text2    ?? this.text2,
        text3:    text3    ?? this.text3,
        border1:  border1  ?? this.border1,
        border2:  border2  ?? this.border2,
        border3:  border3  ?? this.border3,
        onPrimary: onPrimary ?? this.onPrimary,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      bg:        Color.lerp(bg,        other.bg,        t)!,
      surface1:  Color.lerp(surface1,  other.surface1,  t)!,
      surface2:  Color.lerp(surface2,  other.surface2,  t)!,
      surface3:  Color.lerp(surface3,  other.surface3,  t)!,
      surface4:  Color.lerp(surface4,  other.surface4,  t)!,
      text1:     Color.lerp(text1,     other.text1,     t)!,
      text2:     Color.lerp(text2,     other.text2,     t)!,
      text3:     Color.lerp(text3,     other.text3,     t)!,
      border1:   Color.lerp(border1,   other.border1,   t)!,
      border2:   Color.lerp(border2,   other.border2,   t)!,
      border3:   Color.lerp(border3,   other.border3,   t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
    );
  }
}

/// Ergonomic accessor: `Theme.of(context).palette.bg`
extension AppPaletteAccess on ThemeData {
  AppPalette get palette =>
      extension<AppPalette>() ?? AppPalette.dark;
}

/// Even shorter: `context.palette.bg`
extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).palette;
}
