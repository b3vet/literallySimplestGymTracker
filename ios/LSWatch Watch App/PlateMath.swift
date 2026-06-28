//
//  PlateMath.swift
//  LSWatch Watch App
//
//  Pure plate-loading math for a barbell, mirrored LINE-FOR-LINE from the phone's
//  `lib/features/workout/domain/plate_math.dart` (solvePlates + PlateResult) so
//  the watch computes the per-side breakdown OFFLINE from the same kg inputs and
//  reads identically to the phone.
//
//  All weights are in KILOGRAMS (the app's canonical/wire unit). Display-unit
//  (kg/lb) conversion is a separate formatting concern — see `PlateFormat` below,
//  which mirrors `lib/features/workout/application/plate_format.dart` and reuses
//  the `WeightConv` kg->display conversion in `WatchFormat.swift`.
//

import Foundation

/// Result of solving how to load a barbell to a target weight. Mirrors the Dart
/// `PlateResult` (same fields + same `exact`/`barOnly`/`belowBar`/`deltaKg`
/// getters).
struct PlateResult {
    /// Plates for ONE side, largest-first (kg). Whole pairs only — every entry is
    /// mirrored on the other side. Empty when only the bar is loaded.
    let perSide: [Double]

    /// The total barbell weight actually achievable with `perSide`:
    /// `barKg + 2 * sum(perSide)`. Equals `requestedTargetKg` when `exact`.
    let achievableTotalKg: Double

    /// The weight the caller asked for.
    let requestedTargetKg: Double

    /// The bar weight used (kg).
    let barKg: Double

    private static let eps = 1e-6

    /// True when the achievable total hits the requested target exactly.
    var exact: Bool { abs(achievableTotalKg - requestedTargetKg) < Self.eps }

    /// True when nothing is loaded beyond the bar.
    var barOnly: Bool { perSide.isEmpty }

    /// True when the requested target is strictly below the empty bar — you can't
    /// load a barbell lighter than its own bar, so the UI shows "EMPTY BAR".
    var belowBar: Bool { requestedTargetKg < barKg - Self.eps }

    /// Signed difference between what you'll actually load and what you asked for.
    /// Negative => under target; positive => over target; zero when `exact`.
    var deltaKg: Double { achievableTotalKg - requestedTargetKg }
}

/// Solve the per-side plate breakdown to load a barbell to `targetKg`.
///
/// A LINE-FOR-LINE port of the Dart `solvePlates` (lib/features/workout/domain/
/// plate_math.dart): a BOUNDED MIN-PLATES DP over the per-side half-target,
/// working in integer CENTI-KG (×100) to avoid float drift. Returns the loadout
/// whose total is the nearest achievable AT OR BELOW `targetKg` — exact when
/// reachable — using the FEWEST plates, largest-first. Because it's a true
/// bounded subset-sum search it never misses an exact/nearest-below loadout even
/// for non-canonical or capped inventories — unlike a naive greedy pass (which
/// e.g. returns [25] for 90/20/{25,20,15} instead of the correct [20,15]).
///
/// `maxPairs` caps the available PAIRS of a denomination (keyed by its kg value);
/// absent denominations are unlimited.
func solvePlates(
    targetKg: Double,
    barKg: Double,
    inventoryKg: [Double],
    maxPairs: [Double: Int]? = nil
) -> PlateResult {
    let eps = 1e-6

    // At or below the bar: nothing to load. (belowBar / exact getters
    // disambiguate "EMPTY BAR" vs "BAR ONLY" downstream.)
    if targetKg <= barKg + eps {
        return PlateResult(
            perSide: [],
            achievableTotalKg: barKg,
            requestedTargetKg: targetKg,
            barKg: barKg
        )
    }

    let perSideTarget = (targetKg - barKg) / 2.0

    // Work in integer CENTI-KG (×100) to avoid float drift — every plate the app
    // offers is an exact 0.01 kg multiple. `t` is the per-side target in centi-kg.
    let t = Int((perSideTarget * 100).rounded())
    if t <= 0 {
        return PlateResult(
            perSide: [],
            achievableTotalKg: barKg,
            requestedTargetKg: targetKg,
            barKg: barKg
        )
    }

    // Denominations as centi-kg ints (deduped, descending, only those that fit).
    let denomKg = Array(Set(inventoryKg.filter { $0 > eps })).sorted(by: >)
    var denomCenti: [Int] = []
    var centiToKg: [Int: Double] = [:]
    for d in denomKg {
        let c = Int((d * 100).rounded())
        if c > 0 && c <= t && centiToKg[c] == nil {
            denomCenti.append(c)
            centiToKg[c] = d
        }
    }

    // Min-plates DP: best[s] = fewest plates to reach EXACTLY s centi-kg per side.
    let big = 1 << 30
    var best = [Int](repeating: big, count: t + 1)
    best[0] = 0
    for c in denomCenti {
        let cap = maxPairs?[centiToKg[c]!]
        if cap == nil {
            // Unbounded — relax forward.
            var s = c
            while s <= t {
                if best[s - c] + 1 < best[s] { best[s] = best[s - c] + 1 }
                s += 1
            }
        } else {
            // Bounded to `cap` pairs — `cap` rounds of 0/1 relaxation (s descending).
            for _ in 0..<cap! {
                var s = t
                while s >= c {
                    if best[s - c] + 1 < best[s] { best[s] = best[s - c] + 1 }
                    s -= 1
                }
            }
        }
    }

    // Largest reachable per-side sum at or below the target (always >= 0).
    var bestS = 0
    var s = t
    while s >= 0 {
        if best[s] < big {
            bestS = s
            break
        }
        s -= 1
    }

    // Reconstruct a fewest-plate, largest-first loadout for bestS, respecting
    // remaining pair caps so a capped denomination is never over-placed.
    var remaining: [Int: Int] = [:]
    for c in denomCenti { remaining[c] = maxPairs?[centiToKg[c]!] ?? big }
    var used: [Double] = []
    var sr = bestS
    while sr > 0 {
        var picked = false
        for c in denomCenti {
            if c <= sr && (remaining[c] ?? 0) > 0 && best[sr - c] == best[sr] - 1 {
                used.append(centiToKg[c]!)
                remaining[c] = remaining[c]! - 1
                sr -= c
                picked = true
                break
            }
        }
        if !picked { break } // unreachable in practice; guards against an infinite loop
    }

    return PlateResult(
        perSide: used,
        achievableTotalKg: barKg + 2 * (Double(bestS) / 100.0),
        requestedTargetKg: targetKg,
        barKg: barKg
    )
}

/// Formats a `PlateResult` into the plate-breakdown string. Mirrors the phone's
/// `PlateFormat` (lib/features/workout/application/plate_format.dart). The watch
/// always renders the COMPACT form for the narrow wrist surface:
/// `"20+15+5"` / `"BAR ONLY"` / `"EMPTY BAR"` / `"≈97.5 25+10+2.5+1.25"`.
/// Plate values render in the display `unit`; the math itself is always kg.
enum PlateFormat {
    /// The full one-line compact string. Mirrors the phone's STRING-level
    /// `PlateFormat.line(..., compact: true)` (plate_format.dart) EXACTLY — which
    /// is `"≈97.5 25+10+2.5+1.25"` with NO trailing delta. (The trailing signed
    /// `(−x)` is a property of the VISUAL widget `PlateLine`, mirrored by the
    /// per-segment `plateBreakdownText` builders in the views, not by this string
    /// helper.) Convenience only — the views render via segment builders, so this
    /// is currently unused but kept faithful for parity/tests.
    static func line(_ r: PlateResult, unit: String) -> String {
        if r.belowBar { return "EMPTY BAR" }
        if r.barOnly { return "BAR ONLY" }
        let plates = self.plates(r, unit: unit)
        if r.exact { return plates }
        let approx = approxTotal(r, unit: unit)
        return "≈\(approx) \(plates)"
    }

    /// Just the `+`-joined plate list (compact, no spaces). Mirrors
    /// `PlateFormat.plates_(..., compact: true)`.
    static func plates(_ r: PlateResult, unit: String) -> String {
        r.perSide.map { plateNum($0, unit: unit) }.joined(separator: "+")
    }

    /// A bare numeric value in the display unit with no unit suffix. Mirrors
    /// `PlateFormat.plateNum`: kg keeps fractional precision (`20`, `2.5`,
    /// `1.25`); lb rounds to whole.
    static func plateNum(_ kg: Double, unit: String) -> String {
        fmtNum(displayValue(kg, unit: unit), unit: unit)
    }

    /// The "≈ total" value (display unit, no suffix). Derived from the DISPLAYED
    /// bar + plate values so it always equals the sum of the plates shown — this
    /// avoids an lb-rounding artefact where independently-rounded plates wouldn't
    /// sum to a separately-rounded total. Mirrors `PlateFormat.approxTotal`.
    static func approxTotal(_ r: PlateResult, unit: String) -> String {
        fmtNum(displayedTotal(r, unit: unit), unit: unit)
    }

    /// Magnitude of how far the achievable total is from the request, in the
    /// display unit (no sign — the caller prefixes `−`/`+`). Only meaningful when
    /// the result is not exact. Mirrors `PlateFormat.deltaNum`.
    static func deltaNum(_ r: PlateResult, unit: String) -> String {
        fmtNum(displayValue(abs(r.deltaKg), unit: unit), unit: unit)
    }

    /// Eyebrow label, e.g. `"PER SIDE · BAR 20"` (bar weight in display unit).
    /// Mirrors `PlateFormat.eyebrow`.
    static func eyebrow(_ barKg: Double, unit: String) -> String {
        "PER SIDE · BAR \(plateNum(barKg, unit: unit))"
    }

    // ── internals (mirror plate_format.dart) ─────────────────────────────────

    /// The value as DISPLAYED: kg keeps fractional precision; lb rounds to whole.
    /// Mirrors `_displayValue`.
    static func displayValue(_ kg: Double, unit: String) -> Double {
        let v = WeightConv.fromKg(kg, unit: unit)
        return unit == "lb" ? v.rounded() : v
    }

    /// Achievable total computed from the DISPLAYED bar + plate values. Mirrors
    /// `_displayedTotal`.
    static func displayedTotal(_ r: PlateResult, unit: String) -> Double {
        let bar = displayValue(r.barKg, unit: unit)
        let plates = r.perSide.reduce(0.0) { $0 + displayValue($1, unit: unit) }
        return bar + 2 * plates
    }

    /// Mirrors `_fmtNum`: lb rounds whole; kg trims trailing zeros after up to
    /// two decimals.
    static func fmtNum(_ v: Double, unit: String) -> String {
        if unit == "lb" { return String(Int(v.rounded())) }
        if v == v.rounded() { return String(format: "%.0f", v) }
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
