import 'package:flutter/material.dart';

/// Design tokens copied from miniapp/src/index.css: the dark theme (`:root`)
/// and the light theme (`html.light` + its utility remaps). [C.light] selects
/// the palette; the shell rebuilds the whole tree when it changes.
abstract final class C {
  static bool light = false;

  static Color _p(int dark, int lightV) => Color(light ? lightV : dark);

  // theme tokens
  static Color get background => _p(0xFF050505, 0xFFF0EEE8);
  static Color get foreground => _p(0xFFF5F5F5, 0xFF161412);
  static Color get primary => _p(0xFFF5F5F5, 0xFF161412);
  static Color get primaryFg => _p(0xFF0A0A0A, 0xFFF7F5F1);
  static Color get sheet => _p(0xFF111111, 0xFFFFFCF8);
  static Color get sheetElevated => _p(0xFF141414, 0xFFFFFFFF);
  static Color get card => _p(0xC7101010, 0xEBFFFFFF);
  static Color get border => _p(0x1FFFFFFF, 0x241A1816);
  static Color get mutedFg => _p(0xFFA3A3A3, 0xFF5C564F);

  /// `text-white` (light: ink).
  static Color get white => _p(0xFFFFFFFF, 0xFF161412);

  /// Darkest raised surface (connect button at rest).
  static Color get surfaceDeep => _p(0xFF0E0E0E, 0xFFFFFFFF);

  /// Modal barrier (`bg-black/65`, light: warm 45% scrim).
  static Color get scrim => light ? const Color(0x731A1816) : const Color(0xA6000000);

  /// Android navigation bar behind the bottom nav.
  static Color get navBar => _p(0xFF000000, 0xFFFCFBF8);

  // bg-white/N & border-white/N — light remaps to warm ink at similar strength.
  static Color w(int pct) =>
      light ? Color.fromRGBO(26, 24, 22, pct <= 30 ? 0.02 + pct * 0.0085 : pct / 100 * 0.95) : Color.fromRGBO(255, 255, 255, pct / 100);

  // bg-black/N — light remaps to white at the mini app's per-step opacities.
  static const _blackLight = {5: .42, 10: .55, 20: .72, 25: .78, 30: .84, 35: .88, 40: .9, 45: .92, 50: .94, 60: .96, 75: .97, 80: .98};
  static Color b(int pct) {
    if (!light) return Color.fromRGBO(0, 0, 0, pct / 100);
    final keys = _blackLight.keys.toList()..sort();
    var alpha = _blackLight[keys.last]!;
    for (var i = 0; i < keys.length; i++) {
      if (pct <= keys[i]) {
        if (i == 0 || pct == keys[i]) {
          alpha = _blackLight[keys[i]]!;
        } else {
          final lo = keys[i - 1], hi = keys[i];
          alpha = _blackLight[lo]! + (_blackLight[hi]! - _blackLight[lo]!) * (pct - lo) / (hi - lo);
        }
        break;
      }
    }
    return Color.fromRGBO(255, 255, 255, alpha);
  }

  // neutral (text-neutral-* remaps in light)
  static Color get n50 => _p(0xFFFAFAFA, 0xFF161412);
  static Color get n100 => _p(0xFFF5F5F5, 0xFF1A1816);
  static Color get n200 => _p(0xFFE5E5E5, 0xFF241F1C);
  static Color get n300 => _p(0xFFD4D4D4, 0xFF3A342F);
  static Color get n400 => _p(0xFFA3A3A3, 0xFF5C564F);
  static Color get n500 => _p(0xFF737373, 0xFF6A635C);
  static Color get n600 => _p(0xFF525252, 0xFF78716C);
  // Deep neutrals stay dark: they paint "keep-dark" surfaces (Pro chip, error toast).
  static const n700 = Color(0xFF404040);
  static const n800 = Color(0xFF262626);
  static const n900 = Color(0xFF171717);

  // accent text shades (light remaps from index.css)
  static Color get emerald100 => _p(0xFFD1FAE5, 0xFF065F46);
  static Color get emerald200 => _p(0xFFA7F3D0, 0xFF047857);
  static Color get emerald300 => _p(0xFF6EE7B7, 0xFF047857);
  static Color get emerald400 => _p(0xFF34D399, 0xFF059669);
  static Color get red200 => _p(0xFFFECACA, 0xFFB91C1C);
  static Color get red300 => _p(0xFFFCA5A5, 0xFFB91C1C);
  static Color get rose100 => _p(0xFFFFE4E6, 0xFF9F1239);
  static Color get rose200 => _p(0xFFFECDD3, 0xFFBE123C);
  static Color get rose300 => _p(0xFFFDA4AF, 0xFFE11D48);
  static Color get amber50 => _p(0xFFFFFBEB, 0xFF78350F);
  static Color get amber100 => _p(0xFFFEF3C7, 0xFF92400E);
  static Color get amber200 => _p(0xFFFDE68A, 0xFFA16207);
  static Color get amber300 => _p(0xFFFCD34D, 0xFFB45309);
  static Color get amber400 => _p(0xFFFBBF24, 0xFFC2410C);
  static Color get orange100 => _p(0xFFFFEDD5, 0xFF9A3412);
  static Color get orange300 => _p(0xFFFDBA74, 0xFFEA580C);
  static Color get sky50 => _p(0xFFF0F9FF, 0xFF0C4A6E);
  static Color get sky100 => _p(0xFFE0F2FE, 0xFF075985);
  static Color get sky200 => _p(0xFFBAE6FD, 0xFF0369A1);
  static Color get sky300 => _p(0xFF7DD3FC, 0xFF0284C7);
  static Color get teal50 => _p(0xFFF0FDFA, 0xFF115E59);
  static Color get teal100 => _p(0xFFCCFBF1, 0xFF115E59);
  static Color get teal200 => _p(0xFF99F6E4, 0xFF0F766E);
  static Color get violet300 => _p(0xFFC4B5FD, 0xFF7C3AED);

  // base hues (tinted fills/borders via [a]) — identical in both themes
  static const emerald500 = Color(0xFF10B981);
  static const red500 = Color(0xFFEF4444);
  static const rose500 = Color(0xFFF43F5E);
  static const amber500 = Color(0xFFF59E0B);
  static const orange500 = Color(0xFFF97316);
  static const sky500 = Color(0xFF0EA5E9);
  static const teal500 = Color(0xFF14B8A6);
  static const violet500 = Color(0xFF8B5CF6);

  /// Tinted colour. Light mode uses stronger fills so sections read on cream
  /// (index.css "Tinted surfaces — stronger fills").
  static Color a(Color c, double alpha) => c.withValues(alpha: light ? (alpha * 1.45 + 0.01).clamp(0, 1).toDouble() : alpha);
}

const kFont = 'Vazirmatn';
const kBrandMark = 'assets/images/blacklines_mark.png';

/// Text style shorthand: `t(13, w: 600, c: C.n400)`.
TextStyle t(double size, {int w = 400, Color? c, double? h, bool mono = false, TextDecoration? deco}) => TextStyle(
      fontFamily: mono ? 'monospace' : kFont,
      fontSize: size,
      fontWeight: FontWeight.values[(w ~/ 100 - 1).clamp(0, 8)],
      color: c ?? C.foreground,
      height: h,
      decoration: deco,
      decorationColor: c,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

ThemeData blTheme(ThemeData base) {
  final scheme = C.light
      ? ColorScheme.light(surface: C.background, primary: C.primary, onPrimary: C.primaryFg, secondary: C.primary, error: C.red300, outline: C.border)
      : ColorScheme.dark(surface: C.background, primary: C.primary, onPrimary: C.primaryFg, secondary: C.primary, error: C.red300, outline: C.border);
  return base.copyWith(
    brightness: C.light ? Brightness.light : Brightness.dark,
    scaffoldBackgroundColor: C.background,
    canvasColor: C.background,
    colorScheme: scheme,
    textTheme: base.textTheme.apply(fontFamily: kFont, bodyColor: C.foreground, displayColor: C.foreground),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: kFont),
    textSelectionTheme: TextSelectionThemeData(cursorColor: C.foreground, selectionColor: C.w(25), selectionHandleColor: C.foreground),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: C.foreground),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.primaryFg : C.n400),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.foreground : C.w(12)),
      trackOutlineColor: WidgetStateProperty.all(C.w(15)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.foreground : null),
      checkColor: WidgetStateProperty.all(C.primaryFg),
      side: BorderSide(color: C.w(30)),
    ),
    dividerColor: C.w(10),
    dialogTheme: DialogThemeData(backgroundColor: C.sheet),
    datePickerTheme: DatePickerThemeData(backgroundColor: C.sheet),
    timePickerTheme: TimePickerThemeData(backgroundColor: C.sheet),
    splashFactory: InkSparkle.splashFactory,
  );
}
