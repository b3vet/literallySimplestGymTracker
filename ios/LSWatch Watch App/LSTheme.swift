//
//  LSTheme.swift
//  LSWatch Watch App
//
//  LS design system — color/spacing/radius tokens for the watch. The watch is
//  ALWAYS dark (watchOS has no light mode that matters here), so only the dark
//  surface palette is ported. Values are kept in lock-step with the Dart
//  `lsDark` palette in `lib/core/theme/app_theme.dart` and the already-ported
//  Swift tokens in `ios/WorkoutLiveActivity/WorkoutLiveActivity.swift`.
//
//  The accent is DYNAMIC: it mirrors whatever the user picked on the phone,
//  forwarded as a `0xAARRGGBB` Int in the session snapshot (`accentArgb` /
//  `accentInkArgb`). We decode it with `LSAccent(argb:inkArgb:)` and expose the
//  current accent down the view tree via a SwiftUI Environment value so any view
//  recolors automatically when the snapshot accent changes.
//

import SwiftUI

// MARK: - Surface tokens (dark, static)

/// Dark-mode surface palette. Mirrors `lsDark` in the Dart theme. The watch
/// never uses the light palette, so only these are defined.
enum LSColor {
    /// App background (under everything). `#0A0B0C`.
    static let bg       = Color(red: 0.039, green: 0.043, blue: 0.047)
    /// Cards, list rows, sheets. `#16181C`.
    static let surface  = Color(red: 0.086, green: 0.094, blue: 0.110)
    /// Sub-cards, segmented controls, chips. `#1D2025`.
    static let surface2 = Color(red: 0.114, green: 0.125, blue: 0.145)
    /// Hover / pressed surfaces. `#262A31`.
    static let surface3 = Color(red: 0.149, green: 0.165, blue: 0.192)
    /// Default hairline. `#23262C`.
    static let border   = Color(red: 0.137, green: 0.149, blue: 0.173)
    /// Primary text. `#F3F5F6`.
    static let text     = Color(red: 0.953, green: 0.961, blue: 0.965)
    /// Secondary text (mono labels). `#9098A0`.
    static let text2    = Color(red: 0.565, green: 0.596, blue: 0.627)
    /// Tertiary / placeholder — inert labels only. `#5A6068`.
    static let text3    = Color(red: 0.353, green: 0.376, blue: 0.408)

    /// Destructive actions / errors. `#FF5547`.
    static let danger   = Color(red: 1.0, green: 0.333, blue: 0.278)
}

// MARK: - Spacing & radii

/// 4-base spacing scale (watch-relevant subset). Mirrors `LsSpace`.
enum LSSpace {
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
}

/// Corner radii. Mirrors `LsRadius`. `r2` for small chips/pills, `r3` for the
/// workhorse (buttons, banners, cards).
enum LSRadius {
    static let r2: CGFloat = 6
    static let r3: CGFloat = 12
}

// MARK: - Accent (decoded from the phone's 0xAARRGGBB snapshot)

/// The dynamic signal color, decoded from the phone snapshot so the watch
/// tracks whatever accent the user chose in Settings. Carries BOTH the accent
/// and its ink (the text/icon color to draw *on top of* an accent fill) — the
/// accent-ink rule is luminance-based and computed once on the phone, so we
/// just mirror the pair rather than re-deriving it.
struct LSAccent: Equatable {
    let accent: Color
    /// Text/icon color on top of an accent fill. White for dark accents (red,
    /// magenta); near-black for light accents (lime, yellow, cyan).
    let accentInk: Color

    /// Brand-red default (`#FF4D2E` on white ink) — used until a snapshot
    /// arrives, and as the fallback when a snapshot omits/zeroes the accent.
    static let brand = LSAccent(
        accent: Color(red: 1.0, green: 0.302, blue: 0.180),
        accentInk: .white
    )

    /// Build from the raw ARGB ints in the snapshot. Either value may be nil/0
    /// (defaults never store an Int) — we fall back to the brand pair so the
    /// watch never renders a transparent/black accent.
    init(argb: Int64?, inkArgb: Int64?) {
        self.accent = LSAccent.color(fromArgb: argb) ?? LSAccent.brand.accent
        self.accentInk = LSAccent.color(fromArgb: inkArgb) ?? LSAccent.brand.accentInk
    }

    private init(accent: Color, accentInk: Color) {
        self.accent = accent
        self.accentInk = accentInk
    }

    /// `accent` at 16% alpha — for chip/active-set tints. Mirrors `accentDim`.
    var accentDim: Color { accent.opacity(0.16) }

    /// Decode a `0xAARRGGBB` int into a SwiftUI Color. Ported verbatim from
    /// `colorFromArgb` in `WorkoutLiveActivity.swift`. Returns nil when the
    /// value is missing or zero so the caller can pick a hardcoded fallback.
    static func color(fromArgb raw: Int64?) -> Color? {
        guard let raw, raw != 0 else { return nil }
        let a = Double((raw >> 24) & 0xff) / 255.0
        let r = Double((raw >> 16) & 0xff) / 255.0
        let g = Double((raw >> 8)  & 0xff) / 255.0
        let b = Double(raw         & 0xff) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Environment plumbing

private struct LSAccentKey: EnvironmentKey {
    /// Default to the brand red / white ink, so views render sensibly before
    /// the first snapshot lands.
    static let defaultValue: LSAccent = .brand
}

extension EnvironmentValues {
    /// The current accent (mirrored from the phone). Read with
    /// `@Environment(\.lsAccent) private var accent`; inject at the root with
    /// `.environment(\.lsAccent, LSAccent(argb:…, inkArgb:…))` whenever the
    /// snapshot changes, and every descendant recolors automatically.
    var lsAccent: LSAccent {
        get { self[LSAccentKey.self] }
        set { self[LSAccentKey.self] = newValue }
    }
}
