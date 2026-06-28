//
//  SetLoggerView.swift
//  LSWatch Watch App
//
//  Crown-driven set entry — the watch-adapted `set_log_sheet.dart`, a
//  ONE-INPUT-PER-SCREEN flow. A horizontally swipeable pager of full-screen
//  wheel pickers driven by BOTH the Digital Crown and a vertical swipe.
//
//  A normal set is three pages — REPS, WEIGHT, RIR. A DROP-SET exercise extends
//  the pager: the top set (reps · weight · RIR) then, per drop, reps · weight
//  (RIR is top-only), each weight prefilled at −20% of the previous. SAVE on the
//  last page commits the whole group at once (logSetGroup) and starts rest —
//  cancelling logs nothing. Values prefill from the last logged set / target.
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
    private struct PageSpec: Identifiable {
        let id: Int
        let entry: Int
        let field: Field
        let isLast: Bool
    }

    /// Per-entry reps and display-unit weight (entry 0 = top, 1..N = drops).
    @State private var reps: [Int] = []
    @State private var weightDisplay: [Double] = []
    /// RIR is captured on the top entry only.
    @State private var topRir: Int = 0
    @State private var weightStep: Double = 0.5
    @State private var page: Int = 0
    @State private var prefilled = false

    private let repsMin = 1
    private let repsMax = 50
    private let rirMax = 10

    /// 1 for a normal set / an edit; 1 + dropCount for a fresh drop set.
    private var entryCount: Int {
        if target.existing != nil { return 1 }
        guard let ex = model.currentExercise else { return 1 }
        return ex.isDropSet ? 1 + (ex.dropCount ?? 0) : 1
    }

    private var isDropSet: Bool { entryCount > 1 }

    /// The flat list of pages: per entry reps + weight, plus RIR on the top.
    private var pages: [PageSpec] {
        var out: [(Int, Field)] = []
        for e in 0..<entryCount {
            out.append((e, .reps))
            out.append((e, .weight))
            if e == 0 { out.append((e, .rir)) }
        }
        return out.enumerated().map { idx, p in
            PageSpec(id: idx, entry: p.0, field: p.1, isLast: idx == out.count - 1)
        }
    }

    var body: some View {
        TabView(selection: $page) {
            ForEach(pages) { spec in
                stepPage(spec).tag(spec.id)
            }
        }
        .background(LSColor.bg)
        .onAppear {
            guard !prefilled else { return }
            prefill()
            prefilled = true
        }
    }

    // MARK: - A single step page

    @ViewBuilder
    private func stepPage(_ spec: PageSpec) -> some View {
        VStack(spacing: LSSpace.s2) {
            stepHeader(spec)
            switch spec.field {
            case .reps:
                Picker("", selection: bindingReps(spec.entry)) {
                    ForEach(repsMin...repsMax, id: \.self) { v in
                        Text("\(v)")
                            .font(LSType.monoNumeral)
                            .foregroundStyle(LSColor.text)
                            .tag(v)
                    }
                }
                .labelsHidden()
            case .weight:
                Picker("", selection: bindingWeightIndex(spec.entry)) {
                    ForEach(Array(0..<weightCount), id: \.self) { i in
                        Text(WeightConv.displayValueLabel(Double(i) * weightStep))
                            .font(LSType.monoNumeral)
                            .foregroundStyle(LSColor.text)
                            .tag(i)
                    }
                }
                .labelsHidden()
                .id(weightStep)
                plateLine(spec.entry)
                stepPill
            case .rir:
                Picker("", selection: $topRir) {
                    ForEach(0...rirMax, id: \.self) { v in
                        Text("\(v)")
                            .font(LSType.monoNumeral)
                            .foregroundStyle(LSColor.text)
                            .tag(v)
                    }
                }
                .labelsHidden()
            }
            if spec.isLast {
                // Compact inline CTA (shorter than LSPrimaryButton) so it
                // doesn't squeeze the wheel on the final page, pinned to the
                // bottom while the wheel above takes the remaining height.
                Button(action: save) {
                    Text(saveLabel.uppercased())
                        .font(LSType.button)
                        .tracking(1.0)
                        .foregroundStyle(accent.accentInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: LSRadius.r3, style: .continuous)
                                .fill(accent.accent)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, LSSpace.s3)
        .padding(.vertical, LSSpace.s2)
    }

    private var saveLabel: String {
        target.existing != nil ? "Update Set" : (isDropSet ? "Save Drop Set" : "Save Set")
    }

    @ViewBuilder
    private func stepHeader(_ spec: PageSpec) -> some View {
        let fieldName: String = {
            switch spec.field {
            case .reps: return "Reps"
            case .weight: return "Weight · \(model.unit.uppercased())"
            case .rir: return "RIR"
            }
        }()
        let prefix: String = {
            if !isDropSet { return "Set \(target.setNumber)" }
            return spec.entry == 0 ? "Top" : "Drop \(spec.entry)/\(entryCount - 1)"
        }()
        VStack(alignment: .leading, spacing: 2) {
            EyebrowLabel(text: "\(prefix) · \(fieldName)")
            Text(hint(spec))
                .font(LSType.monoMeta)
                .tracking(0.6)
                .foregroundStyle(LSColor.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hint(_ spec: PageSpec) -> String {
        guard let ex = model.currentExercise else { return "—" }
        switch spec.field {
        case .reps:
            return ex.targetRepsMin == ex.targetRepsMax
                ? "Target \(ex.targetRepsMin)"
                : "Target \(ex.targetRepsMin)–\(ex.targetRepsMax)"
        case .weight:
            return spec.entry == 0
                ? "Target \(WeightConv.label(ex.defaultWeightKg, unit: model.unit))"
                : "−20% suggested"
        case .rir:
            return "Reps in reserve"
        }
    }

    // MARK: - Bindings

    private func bindingReps(_ entry: Int) -> Binding<Int> {
        Binding(
            get: { entry < reps.count ? reps[entry] : 10 },
            set: { if entry < reps.count { reps[entry] = $0 } }
        )
    }

    private func bindingWeightIndex(_ entry: Int) -> Binding<Int> {
        Binding(
            get: {
                let w = entry < weightDisplay.count ? weightDisplay[entry] : 0
                return Int((w / weightStep).rounded()).clamped(to: 0...(weightCount - 1))
            },
            set: { newIndex in
                if entry < weightDisplay.count {
                    weightDisplay[entry] =
                        (Double(newIndex) * weightStep).clamped(to: 0...weightRangeMax)
                }
            }
        )
    }

    private var weightRangeMax: Double { model.unit == "lb" ? 660 : 300 }
    private var weightCount: Int { Int((weightRangeMax / weightStep).rounded()) + 1 }

    // MARK: - Plate breakdown (offline, recomputed as the Crown turns)

    /// A single passive plate-loading readout under the WEIGHT wheel, recomputed
    /// from the current entry weight every time the Crown moves it. Mirrors the
    /// phone's one-line plate readout (eyebrow + per-side breakdown): muted
    /// eyebrow + glue, accent numerals, auto-scaling to fit the wrist width.
    @ViewBuilder
    private func plateLine(_ entry: Int) -> some View {
        let display = entry < weightDisplay.count ? weightDisplay[entry] : 0
        let targetKg = WeightConv.toKg(display, unit: model.unit)
        let result = solvePlates(
            targetKg: targetKg,
            barKg: model.barKg,
            inventoryKg: model.plateInventory
        )
        VStack(spacing: 1) {
            Text(PlateFormat.eyebrow(model.barKg, unit: model.unit))
                .font(LSType.monoMeta)
                .tracking(0.8)
                .foregroundStyle(LSColor.text3)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            plateBreakdownText(result)
                .font(LSType.monoData)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
    }

    /// The per-side breakdown as one auto-scaling Text: numerals in accent, the
    /// `+` / `≈` glue, the trailing signed delta and the bar-only / empty-bar
    /// fallbacks in `text2`. Mirrors `PlateFormat.line(..., compact: true)`
    /// segment-for-segment — including the trailing `(−x)` the phone's PlateLine
    /// shows for the closest (non-exact) case.
    private func plateBreakdownText(_ r: PlateResult) -> Text {
        if r.belowBar {
            return Text("EMPTY BAR").foregroundStyle(LSColor.text2)
        }
        if r.barOnly {
            return Text("BAR ONLY").foregroundStyle(LSColor.text2)
        }
        var out = Text("")
        if !r.exact {
            out = out
                + Text("≈\(PlateFormat.approxTotal(r, unit: model.unit)) ")
                    .foregroundStyle(LSColor.text2)
        }
        for (i, kg) in r.perSide.enumerated() {
            if i > 0 {
                out = out + Text("+").foregroundStyle(LSColor.text2)
            }
            out = out
                + Text(PlateFormat.plateNum(kg, unit: model.unit))
                    .foregroundStyle(accent.accent)
        }
        if !r.exact {
            // Hardcoded `−` to mirror the phone's PlateLine: this nearest-at-or-
            // below DP is always UNDER target when non-exact, so the trailing
            // magnitude is a deficit.
            out = out
                + Text(" (−\(PlateFormat.deltaNum(r, unit: model.unit)))")
                    .foregroundStyle(LSColor.text2)
        }
        return out
    }

    // MARK: - Weight-step switcher

    private var stepOptions: [Double] {
        model.unit == "lb" ? [1, 2.5, 5] : [0.5, 1, 2.5, 5]
    }

    private var stepPill: some View {
        Button(action: cycleStep) {
            HStack(spacing: 5) {
                Image(systemName: "plusminus")
                    .font(.system(size: 11, weight: .bold))
                Text("\(WeightConv.displayValueLabel(weightStep)) \(model.unit.uppercased())")
                    .font(LSType.monoMeta)
                    .tracking(0.5)
                    .lineLimit(1)
            }
            .foregroundStyle(accent.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(LSColor.surface2))
        }
        .buttonStyle(.plain)
    }

    private func cycleStep() {
        let opts = stepOptions
        let idx = opts.firstIndex(where: { abs($0 - weightStep) < 0.0001 }) ?? -1
        weightStep = opts[(idx + 1) % opts.count]
        weightDisplay = weightDisplay.map {
            (($0 / weightStep).rounded() * weightStep).clamped(to: 0...weightRangeMax)
        }
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: - Prefill

    private func prefill() {
        guard let ex = model.currentExercise else { return }
        let stepKg = ex.weightStepKg ?? 0.5
        weightStep = WeightConv.stepInUnit(stepKg, unit: model.unit)

        if let existing = target.existing {
            reps = [existing.reps]
            topRir = existing.rir
            weightDisplay = [snappedWeight(fromKg: existing.weightKg)]
            return
        }

        let defaultReps = (ex.targetRepsMin + ex.targetRepsMax) / 2
        let topKg: Double = ex.loggedSets.last?.weightKg ?? ex.defaultWeightKg
        // Prefill reps + RIR from the last set of this exercise too (SOW-03
        // decision #3) — crown parity with the phone, so the wheel starts on
        // the right number. Only for a plain exercise (entryCount == 1): for a
        // drop set, loggedSets.last is the last DROP (lowest weight, rir 0), not
        // the working top — so its top keeps target-mid / 0, matching the phone.
        let topReps = entryCount == 1 ? (ex.loggedSets.last?.reps ?? defaultReps) : defaultReps
        topRir = entryCount == 1 ? (ex.loggedSets.last?.rir ?? 0) : 0

        var repsOut: [Int] = []
        var weightsOut: [Double] = []
        for e in 0..<entryCount {
            repsOut.append((e == 0 ? topReps : defaultReps).clamped(to: repsMin...repsMax))
            if e == 0 {
                weightsOut.append(snappedWeight(fromKg: topKg))
            } else {
                // −20% of the previous entry, snapped; editable.
                let prev = weightsOut[e - 1]
                weightsOut.append((prev * 0.8 / weightStep).rounded() * weightStep)
            }
        }
        reps = repsOut
        weightDisplay = weightsOut
    }

    private func snappedWeight(fromKg kg: Double) -> Double {
        let raw = WeightConv.fromKg(kg, unit: model.unit)
        let snapped = (raw / weightStep).rounded() * weightStep
        return snapped.clamped(to: 0...weightRangeMax)
    }

    // MARK: - Save

    private func save() {
        WKInterfaceDevice.current().play(.success)
        guard !reps.isEmpty, !weightDisplay.isEmpty else { dismiss(); return }

        if let existing = target.existing {
            model.editSet(
                setId: existing.id,
                reps: reps[0],
                weightKg: WeightConv.toKg(weightDisplay[0], unit: model.unit),
                rir: topRir
            )
        } else if entryCount == 1 {
            model.logSet(
                reps: reps[0],
                weightKg: WeightConv.toKg(weightDisplay[0], unit: model.unit),
                rir: topRir
            )
        } else {
            let entries: [(reps: Int, weightKg: Double, rir: Int)] =
                (0..<entryCount).map { e in
                    (
                        reps: reps[e],
                        weightKg: WeightConv.toKg(weightDisplay[e], unit: model.unit),
                        rir: e == 0 ? topRir : 0
                    )
                }
            model.logSetGroup(entries)
        }
        dismiss()
    }
}

// MARK: - Clamp helper

private extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
