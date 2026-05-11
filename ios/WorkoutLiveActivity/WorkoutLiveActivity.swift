import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Plugin attributes
//
// MUST match the `LiveActivitiesAppAttributes` struct embedded inside the
// `live_activities` Flutter plugin (LiveActivitiesPlugin.swift). The widget
// extension reads its data from the shared app-group `UserDefaults` keyed by
// `<UUID>_<fieldName>` — the plugin writes each map entry into that bag.

struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState

    public struct ContentState: Codable, Hashable {
        var appGroupId: String
    }

    var id = UUID()
}

extension LiveActivitiesAppAttributes {
    func prefixedKey(_ key: String) -> String { "\(id)_\(key)" }
}

// MARK: - App-group shared defaults
//
// MUST match `liveActivityAppGroup` in
// lib/features/workout/application/live_activity_controller.dart and the
// App Group capability ID configured on both targets in Xcode.
let workoutSharedDefaults =
    UserDefaults(suiteName: "group.com.berke.literallySimplestGymTracker")

// MARK: - Decoded view-model

private struct WorkoutVM {
    let exerciseName: String
    let exerciseIndex: Int
    let totalExercises: Int
    let setIndex: Int
    let targetSets: Int
    let targetRepsMin: Int
    let targetRepsMax: Int
    let targetWeightLabel: String
    let lastWeightLabel: String
    let lastReps: Int
    let setLines: [String]
    let restEndsAtSec: Double
    let isFinished: Bool

    /// Only count rest as active if the timestamp is in the future at body
    /// evaluation time — guards against showing a stale `0:00` countdown if
    /// the Dart side somehow misses the expiry update.
    var hasRest: Bool { restEndsAtSec > Date().timeIntervalSince1970 }
    var restEnd: Date { Date(timeIntervalSince1970: restEndsAtSec) }
    var hasLastSet: Bool { lastReps > 0 || !lastWeightLabel.isEmpty }

    var setLabel: String {
        if isFinished { return "Workout finished" }
        if targetSets == 0 { return "Set \(setIndex)" }
        return "Set \(setIndex) of \(targetSets)"
    }

    var repsLabel: String {
        if targetRepsMin == 0 && targetRepsMax == 0 { return "" }
        if targetRepsMin == targetRepsMax { return "\(targetRepsMin) REPS" }
        return "\(targetRepsMin)–\(targetRepsMax) REPS"
    }

    static func load(from attrs: LiveActivitiesAppAttributes) -> WorkoutVM {
        let d = workoutSharedDefaults
        return WorkoutVM(
            exerciseName: d?.string(forKey: attrs.prefixedKey("exerciseName")) ?? "Workout",
            exerciseIndex: d?.integer(forKey: attrs.prefixedKey("exerciseIndex")) ?? 0,
            totalExercises: d?.integer(forKey: attrs.prefixedKey("totalExercises")) ?? 0,
            setIndex: d?.integer(forKey: attrs.prefixedKey("setIndex")) ?? 0,
            targetSets: d?.integer(forKey: attrs.prefixedKey("targetSets")) ?? 0,
            targetRepsMin: d?.integer(forKey: attrs.prefixedKey("targetRepsMin")) ?? 0,
            targetRepsMax: d?.integer(forKey: attrs.prefixedKey("targetRepsMax")) ?? 0,
            targetWeightLabel: d?.string(forKey: attrs.prefixedKey("targetWeightLabel")) ?? "",
            lastWeightLabel: d?.string(forKey: attrs.prefixedKey("lastWeightLabel")) ?? "",
            lastReps: d?.integer(forKey: attrs.prefixedKey("lastReps")) ?? 0,
            setLines: d?.stringArray(forKey: attrs.prefixedKey("setLines")) ?? [],
            restEndsAtSec: d?.double(forKey: attrs.prefixedKey("restEndsAtSec")) ?? 0,
            isFinished: d?.bool(forKey: attrs.prefixedKey("isFinished")) ?? false
        )
    }
}

// MARK: - Theme tokens
//
// These match the Dart-side `lsDark` surface + the default "Red" accent
// (LsAccent.red). The user can pick a different accent in-app, but the iOS
// Widget Extension can't observe Dart-runtime settings without an extra
// bridge — we keep the lock-screen rendering in the default accent for
// simplicity. The surface tokens are kept in sync with `lsDark` in
// `lib/core/theme/app_theme.dart`.
private let brandOrange  = Color(red: 1.0,   green: 0.302, blue: 0.180) // #FF4D2E
private let brandBg      = Color(red: 0.039, green: 0.043, blue: 0.047) // #0A0B0C
private let brandSurface = Color(red: 0.086, green: 0.094, blue: 0.110) // #16181C
private let brandSurface2 = Color(red: 0.114, green: 0.125, blue: 0.145) // #1D2025

// MARK: - Building blocks

private struct RestPill: View {
    let vm: WorkoutVM
    var body: some View {
        if vm.hasRest {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(brandOrange)
                Text(timerInterval: Date()...vm.restEnd, countsDown: true)
                    .font(.system(.subheadline, design: .rounded).monospacedDigit().weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(minWidth: 44, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(brandOrange, lineWidth: 1)
            )
        }
    }
}

private struct MetaPill: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .heavy))
            .tracking(1.2)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(brandSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    )
            )
    }
}

/// Tile dimensions used by both the lock-screen single-row strip and the
/// Dynamic-Island compact row. Apple caps the lock-screen activity at 160pt
/// total height, so wrapping the set strip to a second row overflows. The
/// row stays at a fixed height; tiles flex-share the available width and
/// each tile's *content* adapts via `ViewThatFits` to whatever width it
/// ends up with.
private enum SetTileMetrics {
    static let height: CGFloat = 30
    static let spacing: CGFloat = 4
}

private enum SetTileState {
    case done(String)   // "80×8"
    case current
    case pending
}

private struct SetLogStrip: View {
    let vm: WorkoutVM

    var body: some View {
        let total = max(vm.targetSets, vm.setLines.count, 1)
        HStack(spacing: SetTileMetrics.spacing) {
            ForEach(0..<total, id: \.self) { i in
                let state: SetTileState =
                    i < vm.setLines.count ? .done(vm.setLines[i])
                    : i == vm.setLines.count ? .current
                    : .pending
                SetTile(state: state)
            }
        }
        .frame(height: SetTileMetrics.height)
    }
}

/// Adaptive set tile. Each tile gets an equal share of the row width via
/// `.frame(maxWidth: .infinity)`. The content inside picks the *largest*
/// representation that fits the allocated width using `ViewThatFits`:
///   1. Full mono text ("80×8") when the tile is wide enough.
///   2. A compact glyph (✓ for done, • for current, blank for pending) when
///      it isn't.
/// That way a 3-set workout shows weight × reps per tile and a 12-set
/// workout shows a tidy row of progress markers — never overflowing.
private struct SetTile: View {
    let state: SetTileState

    var body: some View {
        let fg: Color = {
            switch state {
            case .done:    return .primary
            case .current: return brandOrange
            case .pending: return .secondary
            }
        }()
        let bg: Color = {
            switch state {
            case .done:    return brandSurface
            default:       return .clear
            }
        }()
        let borderColor: Color = {
            switch state {
            case .current: return brandOrange
            default:       return .white.opacity(0.12)
            }
        }()
        let borderWidth: CGFloat = {
            switch state {
            case .current: return 1.2
            default:       return 1
            }
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(borderColor, lineWidth: borderWidth)
                )

            ViewThatFits(in: .horizontal) {
                // Widest: full "80×8" detail. Used when the row has few sets.
                if case .done(let text) = state {
                    Text(text)
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
                // Medium: just the rep count digits ("8"), so even narrow
                // tiles still convey detail.
                if case .done(let text) = state {
                    Text(repsOnly(text))
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .lineLimit(1)
                        .padding(.horizontal, 2)
                }
                // Narrow fallback: state glyph only.
                glyph
            }
            .foregroundStyle(fg)
        }
        .frame(maxWidth: .infinity)
        .frame(height: SetTileMetrics.height)
    }

    /// Extract the reps half of a "weight×reps" string. Used as a medium
    /// representation when the tile is too narrow for the full text but
    /// wide enough for a couple of digits.
    private func repsOnly(_ text: String) -> String {
        // Tolerate either the math sign "×" or a plain "x".
        if let r = text.range(of: "×") ?? text.range(of: "x") {
            return String(text[r.upperBound...])
        }
        return text
    }

    @ViewBuilder
    private var glyph: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
        case .current:
            Circle()
                .fill(brandOrange)
                .frame(width: 6, height: 6)
        case .pending:
            Circle()
                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                .frame(width: 6, height: 6)
        }
    }
}

// MARK: - Lock-screen banner

private struct LockScreenView: View {
    let vm: WorkoutVM

    /// Apple caps the lock-screen Live Activity at **160pt** total height.
    /// Anything beyond that is clipped by the system. The previous attempt
    /// reserved `minHeight: 184` which the OS silently truncated — and the
    /// wrapping set grid overflowed for any workout with >5 sets.
    ///
    /// Budget breakdown (all in pt) inside 160pt:
    ///
    ///   vertical padding (top + bottom)          24   (12 + 12)
    ///   header row (icon + label / rest pill)    22
    ///   spacer                                    8
    ///   hero name (single line, scaled)          30
    ///   spacer                                    8
    ///   meta pills + index                       24
    ///   spacer                                   10
    ///   set strip (single row, fixed height)     30
    ///   ──────────────────────────────────────────
    ///   total                                   156   ✓ fits
    ///
    /// The set strip stays on ONE line; per-tile content shrinks
    /// (full text → reps-only → glyph) as the count grows, via
    /// `ViewThatFits` inside `SetTile`.
    private static let totalHeight: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row: set label + rest countdown.
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "dumbbell.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(brandOrange)
                    Text(vm.setLabel.uppercased())
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                RestPill(vm: vm)
            }

            Spacer(minLength: 8)

            // Hero — exercise name. Force single-line so the row stays
            // predictable inside the 160pt budget.
            Text(vm.exerciseName.uppercased())
                .font(.system(size: 26, weight: .heavy))
                .tracking(-0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Spacer(minLength: 8)

            // Meta pills row — target + last set + exercise index.
            HStack(spacing: 8) {
                if !vm.repsLabel.isEmpty {
                    MetaPill(label: vm.repsLabel)
                }
                if !vm.targetWeightLabel.isEmpty {
                    MetaPill(label: vm.targetWeightLabel.uppercased())
                }
                Spacer()
                if vm.totalExercises > 0 {
                    Text("\(vm.exerciseIndex)/\(vm.totalExercises)")
                        .font(.system(size: 12, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 10)

            // Set-log strip — ALWAYS single row. Each tile flexes to share
            // the available width; tile content downgrades as it narrows.
            SetLogStrip(vm: vm)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(
            maxWidth: .infinity,
            minHeight: Self.totalHeight,
            maxHeight: Self.totalHeight,
            alignment: .topLeading
        )
        .activityBackgroundTint(brandBg)
        .activitySystemActionForegroundColor(.white)
    }
}

// MARK: - Widget

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            let vm = WorkoutVM.load(from: context.attributes)
            LockScreenView(vm: vm)
        } dynamicIsland: { context in
            let vm = WorkoutVM.load(from: context.attributes)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(vm.setIndex)/\(vm.targetSets)",
                          systemImage: "dumbbell.fill")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(brandOrange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if vm.hasRest {
                        Label {
                            Text(timerInterval: Date()...vm.restEnd, countsDown: true)
                                .font(.system(.caption, design: .rounded).monospacedDigit().weight(.bold))
                        } icon: {
                            Image(systemName: "timer")
                                .foregroundStyle(brandOrange)
                        }
                    } else {
                        Text("\(vm.exerciseIndex)/\(vm.totalExercises)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(vm.exerciseName)
                            .font(.headline.weight(.heavy))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        SetLogStrip(vm: vm)
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(brandOrange)
            } compactTrailing: {
                if vm.hasRest {
                    Text(timerInterval: Date()...vm.restEnd, countsDown: true)
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: 56)
                } else {
                    Text("\(vm.exerciseIndex)/\(vm.totalExercises)")
                        .font(.caption.weight(.heavy))
                }
            } minimal: {
                if vm.hasRest {
                    Text(timerInterval: Date()...vm.restEnd, countsDown: true)
                        .font(.caption2.monospacedDigit())
                } else {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(brandOrange)
                }
            }
        }
    }
}
