//
//  LSComponents.swift
//  LSWatch Watch App
//
//  Reusable LS design-system views for the watch — ports of the Live Activity
//  building blocks (`MetaPill`, `SetTile`, `RestPill`) at watch sizes, plus the
//  primary CTA and eyebrow label the watch screens need. Always dark.
//
//  Visual language: precision instrument, no decorative chrome. Flat surfaces
//  with hairlines (never shadows); accent comes from the environment so every
//  component recolors when the phone snapshot's accent changes — read with
//  `@Environment(\.lsAccent)`.
//

import SwiftUI

// MARK: - MetaPill

/// Small target/stat pill — "3 SETS", "8–12", "20 KG". Ports the Live
/// Activity `MetaPill` to the wrist: a value over a tiny mono eyebrow label,
/// on a `surface` chip with a hairline stroke.
struct MetaPill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value.uppercased())
                .font(LSType.monoData)
                .foregroundStyle(LSColor.text)
                .lineLimit(1)
            Text(label.uppercased())
                .font(LSType.monoMeta)
                .tracking(1.0)
                .foregroundStyle(LSColor.text2)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: LSRadius.r2, style: .continuous)
                .fill(LSColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: LSRadius.r2, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - SetChip

/// Progress marker for one set in the strip. Ports the Live Activity `SetTile`
/// glyph treatment to a compact fixed chip:
///   - done    → filled `surface` chip with a check, hairline stroke
///   - current → accent-tinted chip with an accent stroke + index
///   - pending → empty chip with a faint stroke
struct SetChip: View {
    /// 0-based set index (rendered 1-based).
    let index: Int
    let state: State

    enum State { case done, current, pending }

    @Environment(\.lsAccent) private var accent

    private static let side: CGFloat = 26

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LSRadius.r2, style: .continuous)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: LSRadius.r2, style: .continuous)
                        .stroke(stroke, lineWidth: strokeWidth)
                )
            content
        }
        .frame(width: Self.side, height: Self.side)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LSColor.text)
        case .current:
            Text("\(index + 1)")
                .font(LSType.monoMeta)
                .foregroundStyle(accent.accent)
        case .pending:
            Text("\(index + 1)")
                .font(LSType.monoMeta)
                .foregroundStyle(LSColor.text3)
        }
    }

    private var fill: Color {
        switch state {
        case .done:    return LSColor.surface
        case .current: return accent.accentDim
        case .pending: return .clear
        }
    }

    private var stroke: Color {
        switch state {
        case .done:    return .white.opacity(0.12)
        case .current: return accent.accent
        case .pending: return .white.opacity(0.12)
        }
    }

    private var strokeWidth: CGFloat {
        state == .current ? 1.2 : 1
    }
}

// MARK: - RestBanner

/// Active rest-timer banner. Ports `RestPill` to a full-width control: an
/// accent-bordered banner showing a live countdown (`Text(timerInterval:…)`,
/// the discrete-second monotype the design system mandates) with −15 / +15 /
/// cancel controls. Render this only while a rest is active.
struct RestBanner: View {
    let endsAt: Date
    let onMinus: () -> Void
    let onPlus: () -> Void
    let onCancel: () -> Void

    @Environment(\.lsAccent) private var accent

    var body: some View {
        // Two rows: the countdown on top, the controls below. This guarantees the
        // −15 / +15 labels fit (they share the width equally) and never wrap, and
        // gives each control a comfortable wrist tap target.
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent.accent)

                // Discrete-second countdown — never animated, monospaced so it
                // doesn't jitter. SwiftUI re-renders this every second for free.
                Text(timerInterval: Date()...endsAt, countsDown: true)
                    .font(LSType.monoData)
                    .foregroundStyle(LSColor.text)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("REST")
                    .font(LSType.monoMeta)
                    .tracking(1.0)
                    .foregroundStyle(LSColor.text2)
            }

            HStack(spacing: 6) {
                adjustButton("−15", action: onMinus)
                adjustButton("+15", action: onPlus)
                iconButton("xmark", action: onCancel)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: LSRadius.r3, style: .continuous)
                .fill(LSColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: LSRadius.r3, style: .continuous)
                        .stroke(accent.accent, lineWidth: 1)
                )
        )
    }

    /// Fills the available width so −15 / +15 split the row evenly and never
    /// wrap.
    @ViewBuilder private func adjustButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(LSType.monoMeta)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(LSColor.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: LSRadius.r2, style: .continuous)
                        .fill(LSColor.surface2)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LSColor.text2)
                .padding(5)
                .background(
                    RoundedRectangle(cornerRadius: LSRadius.r2, style: .continuous)
                        .fill(LSColor.surface2)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - LSPrimaryButton

/// The one primary CTA per screen — accent fill, `accentInk` foreground, `r3`
/// corner, full width. Mirrors the phone's primary button (display/uppercase
/// label). Uppercases the label for you.
struct LSPrimaryButton: View {
    let label: String
    let action: () -> Void

    @Environment(\.lsAccent) private var accent

    var body: some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(LSType.button)
                .tracking(1.0)
                .foregroundStyle(accent.accentInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: LSRadius.r3, style: .continuous)
                        .fill(accent.accent)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - EyebrowLabel

/// Section eyebrow — uppercase mono, tracked, `text2`. The label that sits
/// above a hero name or section. No leading dash (the design system's eyebrow
/// "dash" is a CSS border on the phone, never a literal character).
struct EyebrowLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(LSType.monoMeta)
            .tracking(1.4)
            .foregroundStyle(LSColor.text2)
            .lineLimit(1)
    }
}

// MARK: - Previews

#Preview("Components") {
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowLabel(text: "Current Lift")

            HStack(spacing: 6) {
                MetaPill(value: "3", label: "Sets")
                MetaPill(value: "8–12", label: "Reps")
                MetaPill(value: "20 KG", label: "Target")
            }

            HStack(spacing: 6) {
                SetChip(index: 0, state: .done)
                SetChip(index: 1, state: .current)
                SetChip(index: 2, state: .pending)
            }

            RestBanner(
                endsAt: Date().addingTimeInterval(87),
                onMinus: {}, onPlus: {}, onCancel: {}
            )

            LSPrimaryButton(label: "Log Set") {}
        }
        .padding(8)
    }
    .background(LSColor.bg)
    .environment(\.lsAccent, .brand)
}
