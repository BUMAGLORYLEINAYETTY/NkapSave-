import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';
import '../preferences/app_feature.dart';
import '../preferences/auto_save_config.dart';

/// Persists which features the user has enabled and their answers to
/// onboarding profile questions. Backed by SharedPreferences.
///
/// Single source of truth: read [enabledFeatures] from anywhere; listen for
/// changes via [addListener] (e.g. MainShell rebuilds when a feature is
/// toggled from the Profile screen).
class UserPreferences extends ChangeNotifier {
  UserPreferences._();
  static final UserPreferences instance = UserPreferences._();

  static const _kIntroSeen        = 'pref.intro_seen';
  static const _kFeatures         = 'pref.features';
  static const _kProfile          = 'pref.profile';
  static const _kAutoSave         = 'pref.autosave_config';
  static const _kThemePreference  = 'pref.theme';   // dark | light | system

  SharedPreferences? _prefs;
  Set<AppFeature> _features = {};
  Map<String, String> _profile = {};
  AutoSaveConfig _autoSave = const AutoSaveConfig();
  String _themePref = 'light';   // 'dark' | 'light' | 'system'
  bool _introSeen = false;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  bool get introSeen => _introSeen;
  bool get hasCompletedSetup => _features.isNotEmpty;

  /// Defaults to ALL features when the user has not yet picked any.
  /// This keeps existing accounts working without forcing them through
  /// the new onboarding flow.
  Set<AppFeature> get enabledFeatures =>
      _features.isEmpty ? AppFeature.values.toSet() : _features.toSet();

  /// True only after the user has explicitly picked features (post-onboarding).
  Set<AppFeature> get explicitFeatures => _features.toSet();

  Map<String, String> get profile => Map.unmodifiable(_profile);

  AutoSaveConfig get autoSave => _autoSave;

  /// The persisted theme choice as a Flutter [ThemeMode]. Defaults to light
  /// (the cream/violet RE-NEO look); users can still switch to dark or system
  /// from the drawer.
  ThemeMode get themeMode {
    switch (_themePref) {
      case 'dark':   return ThemeMode.dark;
      case 'system': return ThemeMode.system;
      default:        return ThemeMode.light;
    }
  }

  /// Raw string ('dark' / 'light' / 'system') for the picker UI.
  String get themePreferenceId => _themePref;

  bool isEnabled(AppFeature f) => enabledFeatures.contains(f);

  Future<void> load() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    _introSeen = _prefs!.getBool(_kIntroSeen) ?? false;
    _features = (_prefs!.getStringList(_kFeatures) ?? const [])
        .map(AppFeature.fromId)
        .whereType<AppFeature>()
        .toSet();
    final raw = _prefs!.getString(_kProfile);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        _profile = decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {
        _profile = {};
      }
    }
    final autoSaveRaw = _prefs!.getString(_kAutoSave);
    if (autoSaveRaw != null && autoSaveRaw.isNotEmpty) {
      try {
        _autoSave = AutoSaveConfig.decode(autoSaveRaw);
      } catch (_) {
        _autoSave = const AutoSaveConfig();
      }
    }
    final theme = _prefs!.getString(_kThemePreference);
    if (theme == 'dark' || theme == 'light' || theme == 'system') {
      _themePref = theme!;
    }
    _loaded = true;
  }

  Future<void> setAutoSave(AutoSaveConfig config) async {
    _autoSave = config;
    await _prefs?.setString(_kAutoSave, config.encode());
    notifyListeners();
  }

  /// Persists the user's theme choice. Accepts 'dark' / 'light' / 'system'.
  Future<void> setThemePreference(String id) async {
    if (id != 'dark' && id != 'light' && id != 'system') return;
    if (id == _themePref) return;
    _themePref = id;
    await _prefs?.setString(_kThemePreference, id);
    notifyListeners();
  }

  /// Per-njangi-group notification flags. Stored as a JSON map keyed by
  /// group id, with each value a map of toggle key → bool. Defaults to
  /// all-on for any group the user hasn't touched yet. No network call —
  /// this is purely local so opening the toggles is instant; if/when a
  /// backend endpoint lands, mirror writes there from the call site.
  static const _kNjangiNotifs = 'pref.njangi_notifs';

  /// Returns the saved toggles for [groupId]. Missing keys default to true
  /// so a brand-new group opts in to every notification by default.
  Map<String, bool> njangiNotifs(String groupId) {
    final raw = _prefs?.getString(_kNjangiNotifs);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final all = json.decode(raw) as Map<String, dynamic>;
      final mine = all[groupId];
      if (mine is Map) {
        return mine.map((k, v) => MapEntry(k.toString(), v == true));
      }
    } catch (_) {}
    return const {};
  }

  Future<void> setNjangiNotif(
      String groupId, String key, bool value) async {
    final raw = _prefs?.getString(_kNjangiNotifs) ?? '{}';
    Map<String, dynamic> all;
    try {
      all = json.decode(raw) as Map<String, dynamic>;
    } catch (_) {
      all = {};
    }
    final mine = Map<String, dynamic>.from(
        (all[groupId] as Map?) ?? const {});
    mine[key] = value;
    all[groupId] = mine;
    await _prefs?.setString(_kNjangiNotifs, json.encode(all));
    notifyListeners();
  }

  Future<void> markIntroSeen() async {
    if (_introSeen) return;
    _introSeen = true;
    await _prefs?.setBool(_kIntroSeen, true);
    notifyListeners();
  }

  Future<void> setFeatures(Set<AppFeature> features) async {
    _features = features;
    await _prefs?.setStringList(_kFeatures, features.map((f) => f.id).toList());
    notifyListeners();
  }

  Future<void> enableFeature(AppFeature f) async {
    if (_features.contains(f)) return;
    _features = {..._features, f};
    await _prefs?.setStringList(_kFeatures, _features.map((f) => f.id).toList());
    notifyListeners();
  }

  Future<void> disableFeature(AppFeature f) async {
    if (!_features.contains(f)) return;
    _features = _features.where((x) => x != f).toSet();
    await _prefs?.setStringList(_kFeatures, _features.map((f) => f.id).toList());
    notifyListeners();
  }

  Future<void> setProfileAnswers(Map<String, String> answers) async {
    _profile = {..._profile, ...answers};
    await _prefs?.setString(_kProfile, json.encode(_profile));
    notifyListeners();
  }

  String? answer(String questionId) => _profile[questionId];

  Future<void> reset() async {
    _features = {};
    _profile = {};
    _introSeen = false;
    await _prefs?.remove(_kFeatures);
    await _prefs?.remove(_kProfile);
    await _prefs?.remove(_kIntroSeen);
    notifyListeners();
  }
}
