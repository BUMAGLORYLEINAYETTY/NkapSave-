import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import '../services/user_preferences.dart';

/// Theme-aware palette. Call sites use `AppColors.bg`, `AppColors.surface1`,
/// etc. exactly as before — but the value is now resolved at read time
/// based on [UserPreferences.themeMode]. When the user flips the theme in
/// the drawer, `UserPreferences.notifyListeners()` fires, the root
/// `MaterialApp` rebuilds, and every widget that reads `AppColors.X` gets
/// the freshly-resolved colour on its next build.
///
/// Brand / status / category colours stay constant across themes — only
/// surfaces, text, and borders flip. This keeps the visual identity stable
/// while letting the chrome breathe in light mode.
class AppColors {
  // ── Theme resolution ────────────────────────────────────────
  static _Palette get _live {
    final mode = UserPreferences.instance.themeMode;
    if (mode == ThemeMode.light) return _light;
    if (mode == ThemeMode.dark)  return _dark;
    // System: follow the platform.
    final b = PlatformDispatcher.instance.platformBrightness;
    return b == Brightness.light ? _light : _dark;
  }

  /// True when the resolved theme is the dark palette. Useful for places
  /// that need to make a logical decision (icon variant, etc.) rather
  /// than reach for a colour.
  static bool get isDark =>
      identical(_live, _dark);

  // ── Backgrounds ─────────────────────────────────────────────
  static Color get bg       => _live.bg;
  static Color get surface1 => _live.surface1;
  static Color get surface2 => _live.surface2;
  static Color get surface3 => _live.surface3;
  static Color get surface4 => _live.surface4;

  // ── Text ────────────────────────────────────────────────────
  static Color get text1 => _live.text1;
  static Color get text2 => _live.text2;
  static Color get text3 => _live.text3;

  // ── Borders ─────────────────────────────────────────────────
  static Color get border1 => _live.border1;
  static Color get border2 => _live.border2;
  static Color get border3 => _live.border3;

  // ── Brand (same in every theme) ─────────────────────────────
  // NkapSave brand identity (Stitch design system): "Success Green" anchors
  // every primary action and positive money state; "Deep Charcoal" provides
  // the bank-grade scaffolding. `primary` is the green anchor; the gradient
  // companion (`magenta` — legacy name kept so call sites don't break) is
  // the deep forest green used for hero cards, the bot, and brand CTAs.
  static const Color primary    = Color(0xFF27A770); // Success Green
  static const Color primaryDim = Color(0x1A27A770);
  static const Color primaryMid = Color(0x3827A770);
  static const Color magenta    = Color(0xFF006C45); // deep green — gradient end (legacy name)

  // Deep Charcoal — headings / critical scaffolding accents.
  static const Color charcoal   = Color(0xFF1A1C1E);

  // ── Accent (same in every theme) ────────────────────────────
  // Vibrant Gold — reserved for savings goals, rewards, and
  // wealth-building milestones (per the Stitch design system).
  static const Color accent     = Color(0xFFF9A825);
  static const Color accentDim  = Color(0x1AF9A825);
  static const Color accentMid  = Color(0x38F9A825);

  // ── Status (same in every theme) ────────────────────────────
  // Success shares the brand green: positive money / "saved" *is* the brand.
  static const Color success   = Color(0xFF27A770);
  static const Color danger    = Color(0xFFE5484D);
  static const Color dangerDim = Color(0x1FE5484D);
  static const Color info      = Color(0xFF60A5FA);
  static const Color infoDim   = Color(0x1F60A5FA);
  static const Color purple    = Color(0xFFA78BFA);
  static const Color purpleDim = Color(0x1FA78BFA);

  // ── Chart palettes (same in every theme) ────────────────────
  static const List<Color> categories = [
    Color(0xFFA78BFA), // Housing
    Color(0xFFFF7043), // Food
    Color(0xFF26C6DA), // Utilities
    Color(0xFF42A5F5), // Transport
    Color(0xFFEC407A), // Shopping
    Color(0xFF27A770), // Other
  ];

  static const List<Color> members = [
    Color(0xFF27A770), Color(0xFF60A5FA), Color(0xFFF9A825),
    Color(0xFFA78BFA), Color(0xFFFF7043), Color(0xFFEC407A),
    Color(0xFF26C6DA), Color(0xFF42A5F5),
  ];

  // ── Palette definitions ─────────────────────────────────────
  // Dark: green-tinted charcoal. The Stitch system ships light-only, so the
  // dark palette is derived — Deep Charcoal pulled toward the brand green.
  static const _Palette _dark = _Palette(
    bg:       Color(0xFF0C1210),
    surface1: Color(0xFF121A16),
    surface2: Color(0xFF18221D),
    surface3: Color(0xFF1F2C25),
    surface4: Color(0xFF27362E),
    text1:    Color(0xFFECF3EE),
    text2:    Color(0x8CECF3EE),
    text3:    Color(0x4DECF3EE),
    border1:  Color(0x0FFFFFFF),
    border2:  Color(0x1CFFFFFF),
    border3:  Color(0x2EFFFFFF),
  );

  // Light palette: straight from the Stitch design system — a crisp cool
  // canvas (#F8F9FF) with pure-white cards and tonal blue-tinted containers,
  // deep navy-charcoal text, Success Green popping on CTAs and balances.
  static const _Palette _light = _Palette(
    bg:       Color(0xFFF8F9FF), // surface — cool near-white canvas
    surface1: Color(0xFFFFFFFF), // surface-container-lowest — cards
    surface2: Color(0xFFEFF4FF), // surface-container-low — nested / secondary
    surface3: Color(0xFFE5EEFF), // surface-container — chip / divider tints
    surface4: Color(0xFFDCE9FF), // surface-container-high
    text1:    Color(0xFF0B1C30), // on-surface — body / titles
    text2:    Color(0xFF3D4A41), // on-surface-variant — strong secondary
    text3:    Color(0xFF6D7A71), // outline — tertiary / hints
    border1:  Color(0xFFE3EAF2), // cool hairline
    border2:  Color(0xFFCBDBF5), // surface-dim — border
    border3:  Color(0xFFBCCABF), // outline-variant — strong border
  );

  // ── Hero card surfaces ──────────────────────────────────────
  // The signature Success-Green brand gradient. Dark mode anchors deeper so
  // white text keeps WCAG AA contrast; light mode runs the vibrant green
  // into the deep forest companion.
  static List<Color> get heroBrandGradient => isDark
      ? const [Color(0xFF004D30), Color(0xFF00714A), Color(0xFF003322)]
      : const [Color(0xFF27A770), Color(0xFF006C45)];

  // Deep Charcoal hero — the "bank-grade" alternative surface.
  static List<Color> get heroNavyGradient => isDark
      ? const [Color(0xFF14171A), Color(0xFF24292E)]
      : const [Color(0xFF1A1C1E), Color(0xFF2E3338)];

  /// Foreground for content on a hero card. Always white-family — both
  /// dark mode (deep green/charcoal hero) and light mode (brand-green hero)
  /// want white text on a saturated surface.
  static const Color heroFg      = Color(0xFFFFFFFF);
  static const Color heroFgMuted = Color(0xCCFFFFFF); // 80%
  static const Color heroFgDim   = Color(0x99FFFFFF); // 60%
}

class _Palette {
  final Color bg, surface1, surface2, surface3, surface4;
  final Color text1, text2, text3;
  final Color border1, border2, border3;
  const _Palette({
    required this.bg, required this.surface1, required this.surface2,
    required this.surface3, required this.surface4,
    required this.text1, required this.text2, required this.text3,
    required this.border1, required this.border2, required this.border3,
  });
}
