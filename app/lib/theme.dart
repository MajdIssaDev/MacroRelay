import 'package:flutter/material.dart';

import 'settings.dart';

class Palette {
  const Palette({
    required this.id,
    required this.label,
    required this.bg,
    required this.panel,
    required this.card,
    required this.line,
    required this.accent,
    required this.accentDim,
    required this.text,
    required this.muted,
    required this.danger,
    this.light = false,
  });

  final String id;
  final String label;
  final Color bg;
  final Color panel;
  final Color card;
  final Color line;
  final Color accent;
  final Color accentDim;
  final Color text;
  final Color muted;
  final Color danger;
  final bool light;
}

const palettes = <Palette>[
  Palette(
    id: 'ops',
    label: 'Ops',
    bg: Color(0xFF070A0D),
    panel: Color(0xFF10161D),
    card: Color(0xFF161E27),
    line: Color(0xFF243040),
    accent: Color(0xFF3DDC97),
    accentDim: Color(0xFF1B3D30),
    text: Color(0xFFE8EEF4),
    muted: Color(0xFF8A9AAB),
    danger: Color(0xFFFF5C7A),
  ),
  Palette(
    id: 'cobalt',
    label: 'Cobalt',
    bg: Color(0xFF070B14),
    panel: Color(0xFF10182A),
    card: Color(0xFF162036),
    line: Color(0xFF243552),
    accent: Color(0xFF5B9DFF),
    accentDim: Color(0xFF1A335C),
    text: Color(0xFFE8EEF8),
    muted: Color(0xFF8A9BB8),
    danger: Color(0xFFFF6B8A),
  ),
  Palette(
    id: 'ember',
    label: 'Ember',
    bg: Color(0xFF0E0907),
    panel: Color(0xFF1A120E),
    card: Color(0xFF241914),
    line: Color(0xFF3A2A22),
    accent: Color(0xFFFF8A4C),
    accentDim: Color(0xFF4A2A18),
    text: Color(0xFFF6EEE8),
    muted: Color(0xFFB59A8A),
    danger: Color(0xFFFF5C7A),
  ),
  Palette(
    id: 'orchid',
    label: 'Orchid',
    bg: Color(0xFF0C0912),
    panel: Color(0xFF161221),
    card: Color(0xFF1E1830),
    line: Color(0xFF322A4A),
    accent: Color(0xFFC084FC),
    accentDim: Color(0xFF3A2458),
    text: Color(0xFFF0EAF8),
    muted: Color(0xFFA090B8),
    danger: Color(0xFFFF6B9A),
  ),
  Palette(
    id: 'frost',
    label: 'Frost',
    bg: Color(0xFFF3F5F8),
    panel: Color(0xFFFFFFFF),
    card: Color(0xFFE8EDF3),
    line: Color(0xFFCDD6E0),
    accent: Color(0xFF0F9D73),
    accentDim: Color(0xFFD4F0E6),
    text: Color(0xFF15202B),
    muted: Color(0xFF5B6B7A),
    danger: Color(0xFFD63B5D),
    light: true,
  ),
];

Palette paletteById(String id) =>
    palettes.firstWhere((p) => p.id == id, orElse: () => palettes.first);

ThemeData themeFrom(Palette p) {
  final brightness = p.light ? Brightness.light : Brightness.dark;
  return ThemeData(
    brightness: brightness,
    useMaterial3: true,
    scaffoldBackgroundColor: p.bg,
    fontFamily: 'Segoe UI',
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: p.accent,
      onPrimary: p.light ? Colors.white : Colors.black,
      secondary: p.accent,
      onSecondary: p.light ? Colors.white : Colors.black,
      error: p.danger,
      onError: Colors.white,
      surface: p.panel,
      onSurface: p.text,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.card,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}

class ThemeController extends ChangeNotifier {
  ThemeController() {
    _load();
  }

  Palette palette = palettes.first;

  Future<void> _load() async {
    try {
      final data = await SettingsStore.read();
      palette = paletteById(data['theme'] as String? ?? 'ops');
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setId(String id) async {
    palette = paletteById(id);
    notifyListeners();
    try {
      await SettingsStore.patch({'theme': palette.id});
    } catch (_) {}
  }
}

class AppTheme extends InheritedNotifier<ThemeController> {
  const AppTheme({super.key, required ThemeController controller, required super.child})
      : super(notifier: controller);

  static ThemeController controllerOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppTheme>();
    return scope!.notifier!;
  }

  static Palette of(BuildContext context) => controllerOf(context).palette;
}
