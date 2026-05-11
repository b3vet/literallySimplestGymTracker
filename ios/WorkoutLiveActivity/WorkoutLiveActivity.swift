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

private let brandOrange = Color(red: 1.0, green: 0.353, blue: 0.122)
private let brandBg     = Color(red: 0.055, green: 0.059, blue: 0.071)
private let brandSurface = Color(red: 0.102, green: 0.110, blue: 0.129)

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
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.0)
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
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

private struct SetLogStrip: View {
    let vm: WorkoutVM
    var body: some View {
        // Compact row: one tile per set up to targetSets. Logged sets show
        // their `weight × reps` line; pending sets show a dot.
        let total = max(vm.targetSets, vm.setLines.count, 1)
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                if i < vm.setLines.count {
                    SetTile(text: vm.setLines[i], filled: true, current: false)
                } else if i == vm.setLines.count {
                    SetTile(text: "•••", filled: false, current: true)
                } else {
                    SetTile(text: "—", filled: false, current: false)
                }
            }
        }
    }
}

private struct SetTile: View {
    let text: String
    let filled: Bool
    let current: Bool
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(filled ? .primary : (current ? brandOrange : .secondary))
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(filled ? brandSurface : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                current ? brandOrange : .white.opacity(0.12),
                                lineWidth: current ? 1.2 : 1
                            )
                    )
            )
    }
}

// MARK: - Lock-screen banner

private struct LockScreenView: View {
    let vm: WorkoutVM

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: set label + rest countdown.
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "dumbbell.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(brandOrange)
                    Text(vm.setLabel.uppercased())
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                RestPill(vm: vm)
            }

            // Hero — exercise name.
            Text(vm.exerciseName.uppercased())
                .font(.system(size: 24, weight: .heavy))
                .tracking(-0.4)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            // Meta pills row — target + last set.
            HStack(spacing: 6) {
                if !vm.repsLabel.isEmpty {
                    MetaPill(label: vm.repsLabel)
                }
                if !vm.targetWeightLabel.isEmpty {
                    MetaPill(label: vm.targetWeightLabel.uppercased())
                }
                Spacer()
                if vm.totalExercises > 0 {
                    Text("\(vm.exerciseIndex)/\(vm.totalExercises)")
                        .font(.system(size: 11, weight: .heavy)).tracking(1.2)
                        .foregroundStyle(.secondary)
                }
            }

            // Set-log strip — one tile per set.
            SetLogStrip(vm: vm)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
