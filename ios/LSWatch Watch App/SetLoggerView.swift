//
//  SetLoggerView.swift
//  LSWatch Watch App
//
//  Crown-driven set entry — the watch-adapted `set_log_sheet.dart` (SOW §5.4).
//  Three focusable cells (REPS / WEIGHT / RIR) prefilled from the last logged
//  set, else the target midpoint / defaultWeightKg / 0. Tapping a cell focuses
//  it and binds the Digital Crown to that value; the step is the exercise's
//  weightStepKg (or the unit default) for WEIGHT, ±1 for REPS and RIR. Each
//  Crown detent plays a selection haptic. SAVE -> logSet/editSet (the displayed
//  weight is converted back to kg). Default focus = WEIGHT.
//

import SwiftUI
import WatchKit

/// What the logger is doing — a fresh set at `setNumber`, or editing an
/// existing one (prefilled from it). Identifiable so it drives `.sheet(item:)`.
enum SetLoggerTarget: Identifiable {
    case new(setNumber: Int)
    case edit(WatchSetVM, setNumber: Int)

    var id: String {
        switch self {
        case .new(let n): return "new-\(n)"
        case .edit(let set, _): return "edit-\(set.id)"
        }
    }

    var setNumber: Int {
        switch self {
        case .new(let n): return n
        case .edit(_, let n): return n
        }
    }

    var existing: WatchSetVM? {
        if case .edit(let set, _) = self { return set }
        return nil
    }
}

struct SetLoggerView: View {
    @Bindable var model: WatchWorkoutModel
    let target: SetLoggerTarget

    @Environment(\.lsAccent) private var accent
    @Environment(\.dismiss) private var dismiss

    private enum Field { case reps, weight, rir }

    @State private var reps: Double = 10
    /// Weight in the DISPLAY unit (kg or lb), stepped by `weightStep`.
    @State private var weightDisplay: Double = 0
    @State private var rir: Double = 0
    @State private var focus: Field = .weight
    /// The whole screen is the Crown target; this keeps it focused so the Crown
    /// is live (a ScrollView would otherwise steal the Crown for scrolling).
    @FocusState private var crownFocused: Bool

    /// Per-detent step for the weight cell, in the display unit.
    @State private var weightStep: Double = 0.5

    /// Bounds, mirroring the phone's picker ranges.
    private let repsMin = 1.0
    private let repsMax = 50.0
    private let rirMax = 10.0

    var body: some View {
        VStack(alignment: .leading, spacing: LSSpace.s2) {
            header

            HStack(spacing: 4) {
                cell("REPS", value: WeightConv.displayValueLabel(reps), field: .reps)
                cell("WEIGHT", value: WeightConv.displayValueLabel(weightDisplay), field: .weight)
                cell("RIR", value: WeightConv.displayValueLabel(rir), field: .rir)
            }

            stepCycler

            LSPrimaryButton(label: "Save Set", action: save)
        }
        .padding(.horizontal, LSSpace.s3)
        .padding(.vertical, LSSpace.s2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(LSColor.bg)
        // No ScrollView: the whole screen is the Crown target so the Crown drives
        // the focused cell instead of being captured for scrolling. The bound
        // value + step/range swap with `focus`; force focus on appear so the
        // Crown is live immediately.
        .focusable(true)
        .focused($crownFocused)
        .digitalCrownRotation(
            crownBinding,
            from: crownRange.lowerBound,
            through: crownRange.upperBound,
            by: crownStep,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear {
            prefill()
            crownFocused = true
        }
    }

    // MARK: Header (eyebrow + target line)

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            EyebrowLabel(text: "Set \(target.setNumber)")
            if let ex = model.currentExercise {
                Text("\(repsTarget(ex)) · \(WeightConv.label(ex.defaultWeightKg, unit: model.unit))")
                    .font(LSType.monoMeta)
                    .tracking(0.8)
                    .foregroundStyle(LSColor.text2)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Cell

    /// A focusable value cell. Uses a tap GESTURE (not a Button) so tapping it
    /// doesn't steal the Crown focus from the screen — it just routes the Crown
    /// to this field. Both the value and the label are single-line + scalable so
    /// nothing wraps in the narrow third-of-screen width (incl. "RIR" / "WEIGHT"
    /// / two-digit values).
    @ViewBuilder
    private func cell(_ label: String, value: String, field: Field) -> some View {
        let isFocused = focus == field
        VStack(spacing: 2) {
            Text(value)
                .font(LSType.monoNumeral)
                .foregroundStyle(isFocused ? accent.accentInk : LSColor.text)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text(label)
                .font(LSType.monoMeta)
                .tracking(0.5)
                .foregroundStyle(isFocused ? accent.accentInk.opacity(0.8) : LSColor.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: LSRadius.r3, style: .continuous)
                .fill(isFocused ? accent.accent : LSColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: LSRadius.r3, style: .continuous)
                        .stroke(isFocused ? accent.accent : .white.opacity(0.08), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            focus = field
            crownFocused = true
            WKInterfaceDevice.current().play(.click)
        }
    }

    // MARK: Crown wiring

    /// The value the Crown currently drives, routed by focus. Each setter SNAPS
    /// the incoming (continuous) Crown value to its field's grid — reps/RIR to
    /// whole integers, weight to the current `weightStep` — so a fractional Crown
    /// position can never produce 7.5 reps or 1.5 RIR, regardless of the shared
    /// modifier's detent stride. The haptic only ticks when the snapped value
    /// actually changes, giving a clean one-click-per-step feel.
    private var crownBinding: Binding<Double> {
        switch focus {
        case .reps:
            return Binding(get: { reps }, set: { newValue in
                let v = newValue.rounded().clamped(to: repsMin...repsMax)
                if v != reps { reps = v; tick() }
            })
        case .weight:
            return Binding(get: { weightDisplay }, set: { newValue in
                let v = ((newValue / weightStep).rounded() * weightStep)
                    .clamped(to: 0...weightRangeMax)
                if abs(v - weightDisplay) > 0.0001 { weightDisplay = v; tick() }
            })
        case .rir:
            return Binding(get: { rir }, set: { newValue in
                let v = newValue.rounded().clamped(to: 0...rirMax)
                if v != rir { rir = v; tick() }
            })
        }
    }

    private var crownRange: ClosedRange<Double> {
        switch focus {
        case .reps:   return repsMin...repsMax
        case .weight: return 0...weightRangeMax
        case .rir:    return 0...rirMax
        }
    }

    private var crownStep: Double {
        switch focus {
        case .reps, .rir: return 1
        case .weight:     return weightStep
        }
    }

    private var weightRangeMax: Double { model.unit == "lb" ? 660 : 300 }

    // MARK: Weight-step switcher

    /// Selectable per-detent weight steps, by unit (mirrors the phone's inline
    /// step cycler). The exercise's own step seeds the initial value in
    /// `prefill`; this lets the lifter switch to a finer/coarser step mid-entry.
    private var stepOptions: [Double] {
        model.unit == "lb" ? [1, 2.5, 5] : [0.5, 1, 2.5, 5]
    }

    /// Cycle to the next weight step and re-snap the current weight onto it.
    private func cycleStep() {
        let opts = stepOptions
        let idx = opts.firstIndex(where: { abs($0 - weightStep) < 0.0001 }) ?? -1
        weightStep = opts[(idx + 1) % opts.count]
        weightDisplay = ((weightDisplay / weightStep).rounded() * weightStep)
            .clamped(to: 0...weightRangeMax)
        WKInterfaceDevice.current().play(.click)
    }

    /// Tappable pill showing the active weight step; tap to cycle. Tapping also
    /// routes the Crown to WEIGHT (and re-grabs Crown focus) since the step only
    /// affects weight. Tap gesture (not a Button) to avoid stealing Crown focus.
    private var stepCycler: some View {
        HStack {
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "plusminus")
                    .font(.system(size: 11, weight: .bold))
                Text("\(WeightConv.displayValueLabel(weightStep)) \(model.unit.uppercased())")
                    .font(LSType.monoMeta)
                    .tracking(0.5)
                    .lineLimit(1)
            }
            .foregroundStyle(focus == .weight ? accent.accent : LSColor.text2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(LSColor.surface2))
            .contentShape(Capsule())
            .onTapGesture {
                focus = .weight
                crownFocused = true
                cycleStep()
            }
        }
    }

    /// Selection haptic on each Crown detent.
    private func tick() {
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: Prefill (last set -> midpoint/default/0)

    private func prefill() {
        guard let ex = model.currentExercise else { return }

        // Weight step: per-exercise kg step wins, else the unit default.
        let stepKg = ex.weightStepKg ?? 0.5
        weightStep = WeightConv.stepInUnit(stepKg, unit: model.unit)

        if let existing = target.existing {
            reps = Double(existing.reps)
            rir = Double(existing.rir)
            weightDisplay = snappedWeight(fromKg: existing.weightKg)
        } else if let last = ex.loggedSets.last {
            // Prefill from the last logged set on this exercise.
            reps = Double(last.reps)
            rir = Double(last.rir)
            weightDisplay = snappedWeight(fromKg: last.weightKg)
        } else {
            reps = Double((ex.targetRepsMin + ex.targetRepsMax) / 2)
            rir = 0
            weightDisplay = snappedWeight(fromKg: ex.defaultWeightKg)
        }

        reps = reps.clamped(to: repsMin...repsMax)
        rir = rir.clamped(to: 0...rirMax)
    }

    /// Convert kg -> display unit and snap to the current step / range.
    private func snappedWeight(fromKg kg: Double) -> Double {
        let raw = WeightConv.fromKg(kg, unit: model.unit)
        let snapped = (raw / weightStep).rounded() * weightStep
        return snapped.clamped(to: 0...weightRangeMax)
    }

    // MARK: Save

    private func save() {
        WKInterfaceDevice.current().play(.success)
        let weightKg = WeightConv.toKg(weightDisplay, unit: model.unit)
        let r = Int(reps.rounded())
        let rr = Int(rir.rounded())

        if let existing = target.existing {
            model.editSet(setId: existing.id, reps: r, weightKg: weightKg, rir: rr)
        } else {
            // logSet handles the success haptic + auto-rest internally too; the
            // extra .success above is the explicit save confirmation.
            model.logSet(reps: r, weightKg: weightKg, rir: rr)
        }
        dismiss()
    }

    private func repsTarget(_ ex: WatchExerciseVM) -> String {
        ex.targetRepsMin == ex.targetRepsMax
            ? "\(ex.targetRepsMin)"
            : "\(ex.targetRepsMin)–\(ex.targetRepsMax)"
    }
}

// MARK: - Clamp helper

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
