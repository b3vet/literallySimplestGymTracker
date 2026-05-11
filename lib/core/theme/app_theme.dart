// LS Gym Track — design tokens & theme.
//
// Three layers of tokens:
//   1. LsAccent + LsAccentSpec  → user-selectable accent palette (5 swatches).
//   2. LsSurface (lsDark/lsLight) → surface palette, swaps with brightness.
//   3. LsType                     → editorial type scale (display / body / mono).
//
// Consumers read tokens via LsTheme.of(context), which is an InheritedWidget
// installed in MaterialApp.builder. The MaterialApp's ThemeData mirrors the
// same tokens so Material widgets still pick up the right colors/typography
// out of the box.
//
// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

// ─────────────────────────────────────────────────────────────────────────────
//  ACCENT PALETTE
// ─────────────────────────────────────────────────────────────────────────────

enum LsAccent { red, lime, yellow, cyan, magenta }

class LsAccentSpec {
  final LsAccent id;
  final String label;
  final Color accent;
  final Color accentHi;

  /// Text/icon color to draw ON TOP of an accent fill. White for dark accents
  /// (red, magenta), near-black for light accents (lime, yellow, cyan). Never
  /// hardcode Colors.white on a primary button — read this instead.
  final Color accentInk;

  /// Light-mode replacement for `accent.withOpacity(0.16)` — the translucent
  /// version washes out text on a white surface, so we ship an opaque tint.
  final Color accentDimSolidLight;

  const LsAccentSpec({
    required this.id,
    required this.label,
    required this.accent,
    required this.accentHi,
    required this.accentInk,
    required this.accentDimSolidLight,
  });

  Color get accentDim => accent.withValues(alpha: 0.16);
}

const lsAccents = <LsAccentSpec>[
  LsAccentSpec(
    id: LsAccent.red,
    label: 'Red',
    accent: Color(0xFFFF4D2E),
    accentHi: Color(0xFFFF7A5F),
    accentInk: Color(0xFFFFFFFF),
    accentDimSolidLight: Color(0xFFFFE5DF),
  ),
  LsAccentSpec(
    id: LsAccent.lime,
    label: 'Lime',
    accent: Color(0xFFD4FF3A),
    accentHi: Color(0xFFE4FF6E),
    accentInk: Color(0xFF0A0B0C),
    accentDimSolidLight: Color(0xFFEDFFB8),
  ),
  LsAccentSpec(
    id: LsAccent.yellow,
    label: 'Yellow',
    accent: Color(0xFFFFB400),
    accentHi: Color(0xFFFFC533),
    accentInk: Color(0xFF0A0B0C),
    accentDimSolidLight: Color(0xFFFFEFC2),
  ),
  LsAccentSpec(
    id: LsAccent.cyan,
    label: 'Cyan',
    accent: Color(0xFF3DD9FF),
    accentHi: Color(0xFF6FE4FF),
    accentInk: Color(0xFF0A0B0C),
    accentDimSolidLight: Color(0xFFD2F4FF),
  ),
  LsAccentSpec(
    id: LsAccent.magenta,
    label: 'Magenta',
    accent: Color(0xFFFF4DA6),
    accentHi: Color(0xFFFF7ABF),
    accentInk: Color(0xFFFFFFFF),
    accentDimSolidLight: Color(0xFFFFDFEF),
  ),
];

LsAccentSpec lsAccentSpec(LsAccent id) =>
    lsAccents.firstWhere((a) => a.id == id);

// ─────────────────────────────────────────────────────────────────────────────
//  SURFACE PALETTES
// ─────────────────────────────────────────────────────────────────────────────

class LsSurface {
  final Color bg;
  final Color bg2;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color text2;
  final Color text3;
  final Color grid;
  final Color sheetBackdrop;

  const LsSurface({
    required this.bg,
    required this.bg2,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.text2,
    required this.text3,
    required this.grid,
    required this.sheetBackdrop,
  });
}

const lsDark = LsSurface(
  bg: Color(0xFF0A0B0C),
  bg2: Color(0xFF121316),
  surface: Color(0xFF16181C),
  surface2: Color(0xFF1D2025),
  surface3: Color(0xFF262A31),
  border: Color(0xFF23262C),
  borderStrong: Color(0xFF3A3F47),
  text: Color(0xFFF3F5F6),
  text2: Color(0xFF9098A0),
  text3: Color(0xFF5A6068),
  grid: Color(0x0AFFFFFF),
  sheetBackdrop: Color(0x8C000000),
);

// Light surface — values pulled verbatim from the standalone HTML prototype.
// Do not "soften" these; they were tuned so accent fills (red/lime/yellow) sit
// cleanly on top.
const lsLight = LsSurface(
  bg: Color(0xFFF4F5F6),
  bg2: Color(0xFFE9EAEC),
  surface: Color(0xFFFFFFFF),
  surface2: Color(0xFFECEEF0),
  surface3: Color(0xFFE0E3E6),
  border: Color(0xFFD9DCDF),
  borderStrong: Color(0xFFBFC4C9),
  text: Color(0xFF0A0B0C),
  text2: Color(0xFF4A5057),
  text3: Color(0xFF7A8088),
  grid: Color(0x0A000000),
  sheetBackdrop: Color(0x66000000),
);

// ─────────────────────────────────────────────────────────────────────────────
//  SIGNALS (independent of user accent)
// ─────────────────────────────────────────────────────────────────────────────

class LsSignals {
  static const danger = Color(0xFFFF5547);
  static const pr = Color(0xFFFFB400);
}

// ─────────────────────────────────────────────────────────────────────────────
//  SPACING / RADII / MOTION
// ─────────────────────────────────────────────────────────────────────────────

class LsSpace {
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s7 = 32;
  static const double s8 = 48;
  static const double s9 = 64;

  static const double screen = 16;
  static const double cardHero = 20;
  static const double card = 16;
  static const double sheet = 20;
}

class LsRadius {
  static const double r1 = 2;
  static const double r2 = 6;
  static const double r3 = 12;
  static const double r4 = 18;
  static const double r5 = 28;

  static BorderRadius get button => BorderRadius.circular(r3);
  static BorderRadius get card => BorderRadius.circular(r3);
  static BorderRadius get fab => BorderRadius.circular(r3);
  static BorderRadius get sheet =>
      const BorderRadius.vertical(top: Radius.circular(r5));
}

class LsMotion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);
  static const slowCurve = Cubic(0.2, 0.7, 0.2, 1);
}

// ─────────────────────────────────────────────────────────────────────────────
//  TYPE SCALE
// ─────────────────────────────────────────────────────────────────────────────
//
// Three bundled families, each registered as discrete static weights in
// pubspec.yaml. We don't use FontVariation — every weight points at a real
// file (Antonio-Regular/SemiBold/Bold, JetBrainsMono-Regular/Medium/SemiBold/
// Bold, IBMPlexSans-Regular/Medium/SemiBold/Bold). Setting `fontWeight:` on
// the TextStyle is sufficient.

TextStyle _antonio(
  double size,
  FontWeight w, {
  double lh = 1.0,
  double tracking = 0,
}) => TextStyle(
  fontFamily: 'Antonio',
  fontSize: size,
  height: lh,
  fontWeight: w,
  letterSpacing: tracking,
);

TextStyle _plex(
  double size,
  FontWeight w, {
  double lh = 1.45,
  double tracking = 0,
}) => TextStyle(
  fontFamily: 'IBMPlexSans',
  fontSize: size,
  height: lh,
  fontWeight: w,
  letterSpacing: tracking,
);

TextStyle _mono(
  double size,
  FontWeight w, {
  double lh = 1.0,
  double tracking = 0,
}) => TextStyle(
  fontFamily: 'JetBrainsMono',
  fontSize: size,
  height: lh,
  fontWeight: w,
  letterSpacing: tracking,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// LS type scale. Values calibrated against the standalone HTML prototype as
/// rendered on a desktop monitor — the designer's phone-frame previews are
/// wider than a real iPhone's logical width, so literal CSS `px` numbers
/// render smaller than expected on a 393pt device. The scale below pushes
/// everything 1.4–1.5× the spec to recover that visual presence.
///
/// **Weights:** Antonio is a variable font with a `wght` axis that maxes at
/// 700 (Bold). Requests for w800 in the CSS spec clamp to 700 in the browser
/// too, so we use FontWeight.w700 here — same visual result, but explicit.
///
/// CSS `letter-spacing` is in `em`; Flutter `letterSpacing` is in logical px,
/// so `0.06em` at 14px = `0.84`, etc. All `display*` styles are uppercased
/// at the call site.
class LsType {
  // ── Display (Antonio condensed) ─────────────────────────────────────────
  /// Marketing/doc-style only.
  static TextStyle get displayHero =>
      _antonio(84, FontWeight.w700, lh: 0.86, tracking: -1.68);

  /// Active-workout exercise name. CSS spec: 48-54px.
  static TextStyle get displayXL =>
      _antonio(68, FontWeight.w700, lh: 0.9, tracking: -1.36);

  /// Home hero ("TRAIN HEAVY. / LOG CLEAN."). CSS spec: 54px lh 1.05.
  static TextStyle get displayHome =>
      _antonio(76, FontWeight.w700, lh: 1.05, tracking: -1.52);

  /// Right-aligned screen titles (Settings, Programs, History, …). CSS spec:
  /// `.h-title.lg` is 26px.
  static TextStyle get displayL =>
      _antonio(38, FontWeight.w700, lh: 1.0, tracking: -0.38);

  /// Card/sheet titles, big stat numbers.
  static TextStyle get displayM => _antonio(26, FontWeight.w700, lh: 1.0);

  /// In-row titles (tile name, list-row title, day name in cards).
  /// CSS spec: 15px.
  static TextStyle get displayS =>
      _antonio(20, FontWeight.w700, lh: 1.0, tracking: 0.8);

  /// CTA labels (uppercase). CSS spec: 14px / 0.06em.
  static TextStyle get button =>
      _antonio(28, FontWeight.w700, lh: 1.0, tracking: 1.08);

  // ── Body (IBM Plex Sans) ────────────────────────────────────────────────
  static TextStyle get bodyL => _plex(17, FontWeight.w400, lh: 1.4);
  static TextStyle get bodyM => _plex(15, FontWeight.w400, lh: 1.45);
  static TextStyle get bodyS => _plex(13, FontWeight.w400, lh: 1.4);

  // ── Mono (JetBrains Mono) ───────────────────────────────────────────────
  /// Big read-only numeral (selected wheel value, hero stat).
  static TextStyle get monoNumeral => _mono(32, FontWeight.w600, lh: 1.0);

  /// In-row numeric data (logged set values).
  static TextStyle get monoData => _mono(22, FontWeight.w500, lh: 1.0);

  /// Eyebrows / meta labels (UPPERCASE). CSS spec: 9.5-11px / 0.14em.
  static TextStyle get monoMeta =>
      _mono(13, FontWeight.w500, lh: 1.2, tracking: 1.82);

  /// Section/sub-eyebrow (UPPERCASE).
  static TextStyle get monoMicro =>
      _mono(12, FontWeight.w500, lh: 1.2, tracking: 1.92);
}

// ─────────────────────────────────────────────────────────────────────────────
//  THEME WRAPPER
// ─────────────────────────────────────────────────────────────────────────────

class LsTheme extends InheritedWidget {
  final LsSurface surface;
  final LsAccentSpec accent;
  final Brightness brightness;

  const LsTheme({
    super.key,
    required this.surface,
    required this.accent,
    required this.brightness,
    required super.child,
  });

  static LsTheme of(BuildContext context) {
    final t = context.dependOnInheritedWidgetOfExactType<LsTheme>();
    assert(t != null, 'LsTheme missing from widget tree');
    return t!;
  }

  bool get isLight => brightness == Brightness.light;

  /// Use this — NOT `accent.accentDim` — when the dimmed accent appears as a
  /// background behind text. In light mode the alpha tint washes out wheel
  /// values and chip labels, so we swap to the opaque variant.
  Color get accentDimBg =>
      isLight ? accent.accentDimSolidLight : accent.accentDim;

  @override
  bool updateShouldNotify(LsTheme old) =>
      surface != old.surface ||
      accent != old.accent ||
      brightness != old.brightness;

  static ThemeData buildThemeData({
    required LsSurface s,
    required LsAccentSpec a,
    required Brightness brightness,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: s.bg,
      canvasColor: s.bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: a.accent,
        onPrimary: a.accentInk,
        secondary: a.accentHi,
        onSecondary: a.accentInk,
        surface: s.surface,
        onSurface: s.text,
        error: LsSignals.danger,
        onError: Colors.white,
      ),
      dividerColor: s.border,
      splashFactory: InkRipple.splashFactory,
      splashColor: s.surface3,
      highlightColor: s.surface2,
      textTheme: TextTheme(
        displayLarge: LsType.displayL.copyWith(color: s.text),
        headlineLarge: LsType.displayM.copyWith(color: s.text),
        titleLarge: LsType.displayS.copyWith(color: s.text),
        bodyLarge: LsType.bodyL.copyWith(color: s.text),
        bodyMedium: LsType.bodyM.copyWith(color: s.text),
        bodySmall: LsType.bodyS.copyWith(color: s.text2),
        labelLarge: LsType.button.copyWith(color: a.accentInk),
        labelMedium: LsType.monoMeta.copyWith(color: s.text2),
        labelSmall: LsType.monoMicro.copyWith(color: s.text3),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: a.accent,
          foregroundColor: a.accentInk,
          textStyle: LsType.button,
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: LsRadius.button),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: s.surface2,
          foregroundColor: s.text,
          side: BorderSide(color: s.borderStrong),
          textStyle: LsType.button,
          minimumSize: const Size.fromHeight(54),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: LsRadius.button),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: s.text,
          textStyle: LsType.button,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: LsRadius.button),
        ),
      ),
      cardTheme: CardThemeData(
        color: s.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: s.border),
          borderRadius: LsRadius.card,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: s.sheetBackdrop,
        shape: RoundedRectangleBorder(borderRadius: LsRadius.sheet),
        // We render our own drag handle inside `LsSheet` (sits on the sheet's
        // own background, sized to the design spec). Disable Material's
        // default handle so the two don't stack.
        showDragHandle: false,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: s.bg,
        foregroundColor: s.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: LsType.displayS.copyWith(color: s.text),
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LsRadius.r3),
          side: BorderSide(color: s.border),
        ),
        titleTextStyle: LsType.displayM.copyWith(color: s.text),
        contentTextStyle: LsType.bodyM.copyWith(color: s.text),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LsRadius.r3),
          borderSide: BorderSide(color: s.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LsRadius.r3),
          borderSide: BorderSide(color: s.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LsRadius.r3),
          borderSide: BorderSide(color: a.accent, width: 1.5),
        ),
        labelStyle: LsType.monoMeta.copyWith(color: s.text2),
        hintStyle: LsType.bodyM.copyWith(color: s.text3),
      ),
      listTileTheme: ListTileThemeData(
        tileColor: s.surface,
        iconColor: s.text2,
        textColor: s.text,
      ),
      iconTheme: IconThemeData(color: s.text, size: 20),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  LEGACY SHIM — AppColors / AppDisplay
// ─────────────────────────────────────────────────────────────────────────────
//
// The original codebase imports `AppColors` and `AppDisplay` directly. Keeping
// those names as a thin shim lets existing files continue to compile while we
// migrate screens to LsTheme/LsType incrementally. New code should reference
// `LsTheme.of(context)` and `LsType` instead.

class AppColors {
  // Map to dark-mode tokens — the legacy callers only ever ran in dark.
  static const bg = Color(0xFF0A0B0C);
  static const surface = Color(0xFF16181C);
  static const elevated = Color(0xFF1D2025);
  static const primary = Color(0xFFFF4D2E);
  static const primaryDim = Color(0x29FF4D2E);
  static const success = Color(0xFF22C55E);
  static const danger = Color(0xFFFF5547);
  static const textPrimary = Color(0xFFF3F5F6);
  static const textSecondary = Color(0xFF9098A0);
  static const textMuted = Color(0xFF5A6068);
  static const divider = Color(0xFF23262C);
}

class AppDisplay {
  static TextStyle get hero => LsType.displayXL.copyWith(color: lsDark.text);
  static TextStyle get megaNumber =>
      LsType.displayHero.copyWith(color: lsDark.text);
  static TextStyle get eyebrow => LsType.monoMeta.copyWith(color: lsDark.text2);
  static TextStyle get stat => LsType.monoNumeral.copyWith(color: lsDark.text);
  static TextStyle get mono => LsType.monoMeta.copyWith(color: lsDark.text2);
}

class AppTheme {
  /// Legacy entry point — call sites pre-redesign use this. The redesigned
  /// app builds its theme inline in `app.dart`; this stays as a compile-time
  /// fallback returning the default red-dark theme.
  static ThemeData dark() {
    return LsTheme.buildThemeData(
      s: lsDark,
      a: lsAccentSpec(LsAccent.red),
      brightness: Brightness.dark,
    );
  }
}
