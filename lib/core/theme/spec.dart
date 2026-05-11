// LS Gym Track — type / spacing / container reference matrix.
//
// All app screens read from this file (via `LsType`, `LsGap`, `LsBox`) so we
// only ever tune values in one place. The home screen is the calibration
// reference: the user signed off on those exact sizes, and every other
// screen's metrics are derived from them via the ratios below.
//
// =============================================================================
// FONT-SIZE MATRIX
// =============================================================================
//
// CSS spec  → Flutter size  → ratio  → where used
// ────────────────────────────────────────────────────────────────────────────
// DISPLAY (Antonio, condensed all-caps; weights 400/600/700 only — Antonio's
// `wght` axis caps at 700, so requesting w800 in CSS still resolves to 700)
//
//   54px  →  76  →  1.41x   displayHome     Home hero "TRAIN HEAVY. / LOG CLEAN."
//   48px  →  68  →  1.42x   displayXL       Active-workout exercise name
//   64px  →  84  →  1.31x   displayHero     Marketing/doc only
//   36px  →  38  →  1.06x   displayL        Screen titles right-aligned
//   24px  →  26  →  1.08x   displayM        Card titles, sheet titles
//   16px  →  20  →  1.25x   displayS        Tile labels, list-row titles
//   14px  →  16  →  1.14x   button          CTA button labels
//
//   Overrides (used by widgets that need a chunkier element than the scale):
//   20px  →  30   .btn-cta lbl   "START WORKOUT" hero CTA
//    9.5  →  13   .btn-cta sub   "PICK A PROGRAM DAY" caption
//   13px  →  24   LS monogram    BrandMark only
//   15px  →  23   tile-row name  Home numbered tile labels
//
// BODY (IBM Plex Sans, sentence-case)
//   17  →  17  bodyL          Settings rows
//   15  →  15  bodyM          Default body
//   13  →  13  bodyS          Subtitles/captions
//
// MONO (JetBrains Mono, tabular numerals, UPPERCASE labels)
//   24px  →  32  →  1.33x   monoNumeral     Wheel selected value, hero stat
//   20px  →  22  →  1.10x   monoData        Logged set values
//   11px  →  13  →  1.18x   monoMeta        Eyebrows, meta labels
//    9.5  →  12  →  1.26x   monoMicro       Section eyebrows
//
//   Overrides:
//   10px  →  14   tile-row index   Home numbered "01" "02" tags
//   10px  →  14   LS caption       "GYM TRACKER" caption
//
// =============================================================================
// SPACING MATRIX
// =============================================================================
//
// Semantic gaps (use `LsGap.X` everywhere, never magic numbers):
//
//   LsGap.section   = 16   Between major UI blocks (hero ↔ CTA, CTA ↔ tiles)
//   LsGap.sub       = 12   Within a section (eyebrow ↔ hero, label ↔ value)
//   LsGap.item      = 10   Between rows in a list (between tiles)
//   LsGap.inline    = 12   Icon ↔ text, chip ↔ chip
//   LsGap.tight     =  8   Tightest gap (sub-row separators)
//   LsGap.loose     = 22   Major break (after hero into CTA, end-of-section)
//   LsGap.screenTop =  6   Screen content offset under safe-area
//   LsGap.screenBot = 10   Screen bottom inset above home-indicator
//
// Card / row internal padding (use these as starting points; per-element tune
// only when the design specifies a different metric):
//
//   LsPad.cardTight   = EdgeInsets.symmetric(horizontal: 16, vertical: 14)
//   LsPad.cardStd     = EdgeInsets.symmetric(horizontal: 18, vertical: 18)
//   LsPad.cardSpacious= EdgeInsets.symmetric(horizontal: 20, vertical: 20)
//   LsPad.cta         = EdgeInsets.fromLTRB(22, 22, 16, 22)    accent CTA
//   LsPad.sheet       = EdgeInsets.fromLTRB(20, 8, 20, 24)     bottom-sheet content
//
// =============================================================================
// CONTAINER-SIZE MATRIX
// =============================================================================
//
//   LsBox.topbarIcon    = 44     back / close / settings square in topbars
//   LsBox.brandLs       = 52     home BrandMark "LS" square
//   LsBox.ctaArrow      = 52     dark inner arrow box on home start CTA
//   LsBox.tileIndex     = 44     home tile "01" index square
//   LsBox.setChipW      = 48     set chip width (active workout)
//   LsBox.setChipH      = 40     set chip height (active workout)
//   LsBox.choiceChip    = 56     unit/theme/step buttons in Settings
//   LsBox.button        = 54     LsButton min height (primary CTA buttons)
//   LsBox.cta           = 60     hero CTA button min height
//
// =============================================================================
// COLOR / RADIUS / MOTION
// =============================================================================
//
// Defined in app_theme.dart — this file only covers size + spacing tokens.

import 'package:flutter/widgets.dart';

class LsGap {
  /// Between major UI blocks (hero ↔ CTA, CTA ↔ tiles).
  static const double section = 16;

  /// Within a section (eyebrow ↔ hero).
  static const double sub = 12;

  /// Between rows in a list (between tiles).
  static const double item = 10;

  /// Icon ↔ text, chip ↔ chip.
  static const double inline = 12;

  /// Tightest gap (sub-row separators).
  static const double tight = 8;

  /// Major break (after hero into CTA, end-of-section).
  static const double loose = 22;

  /// Screen content offset under safe-area.
  static const double screenTop = 6;

  /// Screen bottom inset above home-indicator.
  static const double screenBot = 10;
}

class LsPad {
  static const cardTight = EdgeInsets.symmetric(horizontal: 16, vertical: 14);
  static const cardStd = EdgeInsets.symmetric(horizontal: 18, vertical: 18);
  static const cardSpacious =
      EdgeInsets.symmetric(horizontal: 20, vertical: 20);

  /// Accent CTA padding (extra vertical for the hero "START WORKOUT" button).
  static const cta = EdgeInsets.fromLTRB(22, 22, 16, 22);

  /// Bottom-sheet content padding.
  static const sheet = EdgeInsets.fromLTRB(20, 8, 20, 24);
}

class LsBox {
  /// Back / close / settings square chip in topbars.
  static const double topbarIcon = 44;

  /// Home BrandMark "LS" square.
  static const double brandLs = 52;

  /// LS monogram font size inside the BrandMark.
  static const double brandLsLabel = 24;

  /// Dark inner arrow box on home start CTA.
  static const double ctaArrow = 52;

  /// Home tile "01" index square.
  static const double tileIndex = 44;

  /// Set chip dimensions (active workout).
  static const double setChipW = 60;
  static const double setChipH = 50;

  /// Unit/theme/step buttons in Settings.
  static const double choiceChip = 56;

  /// LsButton min height (standard).
  static const double button = 54;

  /// Hero CTA button min height (LOG SET, FINISH WORKOUT).
  static const double cta = 64;

  /// Footer FAB pair button min height. Tall enough for thumb-comfort plus
  /// a chunky 16px label.
  static const double fab = 64;

  /// Play button on Start Workout day cards.
  static const double playButton = 56;
}
