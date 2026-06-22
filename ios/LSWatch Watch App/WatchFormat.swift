//
//  WatchFormat.swift
//  LSWatch Watch App
//
//  Small value-formatting helpers shared across the watch screens. These mirror
//  the phone's `WeightConv` (lib/core/util/weight.dart) and the elapsed/duration
//  formatting in `active_workout_screen.dart` / `program_status_sheet.dart` so
//  the wrist reads identically to the phone.
//
//  All weight math is done in kg (the storage/wire unit). The display unit is a
//  String ("kg" | "lb") forwarded in the snapshot — we never carry a unit enum
//  on the watch, just the two cases.
//

import Foundation

/// kg <-> lb conversion + display formatting. Mirrors the Dart `WeightConv`:
///   - kg shows one decimal of precision (`.5`), or no decimals when whole.
///   - lb is rounded to a whole number.
enum WeightConv {
    /// Pounds per kilogram. Matches `WeightConv._lbPerKg` on the phone.
    static let lbPerKg = 2.2046226218

    /// Convert a value the user sees (in `unit`) back into kg for the wire.
    static func toKg(_ display: Double, unit: String) -> Double {
        unit == "lb" ? display / lbPerKg : display
    }

    /// Convert stored kg into the user's chosen display unit.
    static func fromKg(_ kg: Double, unit: String) -> Double {
        unit == "lb" ? kg * lbPerKg : kg
    }

    /// The bare numeric label in the display unit ("21" / "20.5" / "176"), no
    /// unit suffix. kg keeps a half-precision decimal; lb rounds whole.
    static func number(_ kg: Double, unit: String) -> String {
        let v = fromKg(kg, unit: unit)
        if unit == "lb" { return String(Int(v.rounded())) }
        return v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    /// Full label with the unit suffix, uppercased ("21 KG" / "176 LB").
    static func label(_ kg: Double, unit: String) -> String {
        "\(number(kg, unit: unit)) \(unit.uppercased())"
    }

    /// Default per-detent step in the display unit when the exercise carries no
    /// `weightStepKg` (kg 0.5, lb 1) — matches `WeightUnit.defaultStep`.
    static func defaultStep(unit: String) -> Double {
        unit == "lb" ? 1.0 : 0.5
    }

    /// Convert a step stored in kg into a sane step in the display unit. Mirrors
    /// `_stepInUnit` in `set_log_sheet.dart`: lb snaps to 1 / 2.5 / 5.
    static func stepInUnit(_ stepKg: Double, unit: String) -> Double {
        if unit != "lb" { return stepKg }
        let asLb = stepKg * lbPerKg
        if asLb <= 1.25 { return 1.0 }
        if asLb <= 3.75 { return 2.5 }
        return 5.0
    }

    /// Format a raw display value for a focused-cell / picker label: one decimal
    /// when fractional, otherwise whole. (Step-aware values like 20.5 / 21.)
    static func displayValueLabel(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

/// Elapsed / duration formatters mirroring the phone.
enum TimeFormat {
    /// mm:ss, or h:mm:ss past an hour. Mirrors `_HeaderRow._fmt`.
    static func elapsed(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    /// "19M" / "1H 5M" — coarse elapsed for the program header. Mirrors
    /// `_formatDuration` in `program_status_sheet.dart`.
    static func coarse(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)H \(m)M" : "\(m)M"
    }
}
