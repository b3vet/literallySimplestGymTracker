//
//  LSType.swift
//  LSWatch Watch App
//
//  LS type scale, watch-sized. Three bundled families used strictly by role
//  (mirrors `LsType` in `lib/core/theme/app_theme.dart`, scaled DOWN for the
//  wrist):
//
//    display : Antonio        — condensed, ALL-CAPS UI (hero name, CTA labels)
//    mono    : JetBrains Mono  — numerals + meta labels, TABULAR figures
//    body    : IBM Plex Sans   — hints / captions / paragraph
//
//  The 6 TTFs are copied into the watch target and listed under `UIAppFonts`
//  by the config agent. We ALWAYS reference them via `Font.custom(PostScript,
//  size:)`: SwiftUI falls back to the system font gracefully when a face isn't
//  present yet, so this code never crashes if a font is missing during early
//  bring-up.
//
//  Casing rule (enforced at the call site, not here): display text and mono
//  eyebrows are ALWAYS uppercase; body text is sentence-case. Hero names use
//  `.minimumScaleFactor` to fit the watch width.
//

import SwiftUI

/// Bundled font PostScript names. Keep these exact — `Font.custom` matches on
/// the PostScript name, not the filename or family.
private enum LSFontName {
    static let antonioBold      = "Antonio-Bold"
    static let antonioSemiBold  = "Antonio-SemiBold"
    static let monoMedium       = "JetBrainsMono-Medium"
    static let monoSemiBold     = "JetBrainsMono-SemiBold"
    static let bodyRegular      = "IBMPlexSans-Regular"
    static let bodyMedium       = "IBMPlexSans-Medium"
}

/// Watch-sized LS type roles. Each is `Font.custom` over a bundled PostScript
/// name with a graceful system fallback. Mono roles return monospaced/tabular
/// variants so columns of numerals stay aligned.
enum LSType {

    // MARK: Display (Antonio condensed — uppercase at use-site)

    /// Display hero — the exercise name. ~30pt. Pair with `.lineLimit(1)` +
    /// `.minimumScaleFactor(…)` so long names shrink to fit the watch width.
    static var displayHero: Font {
        .custom(LSFontName.antonioBold, size: 30)
    }

    /// Medium display — card / sheet section titles. ~20pt.
    static var displayM: Font {
        .custom(LSFontName.antonioBold, size: 20)
    }

    /// CTA / button label. ~16pt, uppercase at use-site.
    static var button: Font {
        .custom(LSFontName.antonioBold, size: 16)
    }

    /// Antonio SemiBold — secondary display weight where Bold is too heavy
    /// (e.g. an inline day name). Exposed for parity with the Dart scale.
    static var displaySemibold: Font {
        .custom(LSFontName.antonioSemiBold, size: 20)
    }

    // MARK: Mono (JetBrains Mono — tabular numerals)

    /// Big read-only numeral (focused set-logger value, hero stat). ~24pt,
    /// monospaced/tabular so digits don't jitter while the Crown spins.
    static var monoNumeral: Font {
        .custom(LSFontName.monoSemiBold, size: 24).monospacedDigit()
    }

    /// In-row numeric data (logged set values "21KG × 10"). ~16pt, tabular.
    static var monoData: Font {
        .custom(LSFontName.monoMedium, size: 16).monospacedDigit()
    }

    /// Eyebrows / meta labels (UPPERCASE, tracked at use-site). ~11pt, tabular.
    static var monoMeta: Font {
        .custom(LSFontName.monoMedium, size: 11).monospacedDigit()
    }

    // MARK: Body (IBM Plex Sans)

    /// Default body — hints, captions. ~14pt.
    static var body: Font {
        .custom(LSFontName.bodyRegular, size: 14)
    }

    /// Medium body — emphasized inline body text. ~14pt.
    static var bodyMed: Font {
        .custom(LSFontName.bodyMedium, size: 14)
    }
}
