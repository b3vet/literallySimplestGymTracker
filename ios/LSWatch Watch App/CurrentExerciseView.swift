//
//  CurrentExerciseView.swift
//  LSWatch Watch App
//
//  Root active-workout screen — the watch-adapted `active_workout_screen.dart`
//  (SOW §5.3). Header (elapsed + exercise index + finish affordance), the rest
//  banner when a rest is running, the CURRENT-LIFT block (eyebrow + hero name +
//  meta pills + set-chip strip), the logged-set rows (tap to edit), and the one
//  primary CTA — "LOG SET" until the target is met, then "NEXT EXERCISE ->".
//
//  All content scrolls under the Digital Crown (ScrollView). Mutations go
//  through the model; this view is pure presentation + intent.
//

import SwiftUI
import WatchKit

struct CurrentExerciseView: View {
    @Bindable var model: WatchWorkoutModel
    @Environment(\.lsAccent) private var accent

    /// Presents the set logger. nil = closed; .new logs a fresh set; .edit(set)
    /// edits an existing one (prefilled from it).
    @State private var loggerTarget: SetLoggerTarget?
    @State private var showFinishDialog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LSSpace.s3) {
                header

                if let endsAt = model.restEndsAt {
                    RestBanner(
                        endsAt: endsAt,
                        onMinus: { model.adjustRest(deltaSec: -15) },
                        onPlus: { model.adjustRest(deltaSec: 15) },
                        onCancel: { model.cancelRest() }
                    )
                }

                if let ex = model.currentExercise {
                    liftBlock(ex)
                    setRows(ex)
                    primaryButton(ex)
                } else {
                    finishedBlock
                }
            }
            .padding(.horizontal, LSSpace.s3)
            .padding(.vertical, LSSpace.s2)
        }
        .background(LSColor.bg)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFinishDialog = true
                } label: {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accent.accent)
                }
            }
        }
        .confirmationDialog("Finish workout?", isPresented: $showFinishDialog, titleVisibility: .visible) {
            Button("Finish now") { model.finish() }
            Button("Discard", role: .destructive) { model.discard() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $loggerTarget) { target in
            SetLoggerView(model: model, target: target)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            // Drive a 1 Hz re-render so the elapsed clock actually ticks — a bare
            // `model.elapsed` read only updates when the model changes, so it
            // froze after the first snapshot. (The rest banner ticked because it
            // uses Text(timerInterval:).)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(TimeFormat.elapsed(model.elapsed))
                    .font(LSType.monoNumeral)
                    .foregroundStyle(LSColor.text)
            }
            Spacer()
            // "01/02" — current index in accent, total muted.
            HStack(spacing: 0) {
                Text(pad2(model.exerciseIndex))
                    .foregroundStyle(accent.accent)
                Text("/\(pad2(model.totalExercises))")
                    .foregroundStyle(LSColor.text2)
            }
            .font(LSType.monoData)
        }
    }

    // MARK: Lift block (eyebrow + hero + meta pills + chips)

    @ViewBuilder
    private func liftBlock(_ ex: WatchExerciseVM) -> some View {
        EyebrowLabel(text: "Current Lift")

        Text(ex.name.uppercased())
            .font(LSType.displayHero)
            .foregroundStyle(LSColor.text)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .fixedSize(horizontal: false, vertical: true)

        HStack(spacing: 6) {
            MetaPill(value: "\(ex.targetSets)", label: "Sets")
            MetaPill(value: repsLabel(ex), label: "Reps")
            MetaPill(value: WeightConv.label(ex.defaultWeightKg, unit: model.unit), label: "Target")
        }

        setChips(ex)
    }

    /// Progress strip. done up to loggedCount, the next slot is current, the
    /// rest pending. Mirrors `_SetChipsRow`.
    @ViewBuilder
    private func setChips(_ ex: WatchExerciseVM) -> some View {
        let total = max(ex.targetSets, ex.loggedSets.count)
        let done = ex.loggedSets.count
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(0..<total, id: \.self) { i in
                    SetChip(index: i, state: chipState(i, done: done))
                }
            }
        }
    }

    private func chipState(_ i: Int, done: Int) -> SetChip.State {
        if i < done { return .done }
        if i == done { return .current }
        return .pending
    }

    // MARK: Logged-set rows

    @ViewBuilder
    private func setRows(_ ex: WatchExerciseVM) -> some View {
        let logged = ex.loggedSets
        let total = max(ex.targetSets, logged.count)
        VStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                if i < logged.count {
                    LoggedSetRow(
                        index: i,
                        set: logged[i],
                        unit: model.unit,
                        onTap: { loggerTarget = .edit(logged[i], setNumber: i + 1) },
                        onDelete: { model.deleteSet(setId: logged[i].id) }
                    )
                } else {
                    PendingSetRow(index: i, isNext: i == logged.count)
                }
            }
        }
    }

    // MARK: Primary CTA

    @ViewBuilder
    private func primaryButton(_ ex: WatchExerciseVM) -> some View {
        let targetMet = ex.loggedSets.count >= ex.targetSets
        let hasNext = model.exerciseIndex < model.totalExercises

        if targetMet && hasNext {
            LSPrimaryButton(label: "Next Exercise →") {
                // exerciseIndex is 1-based; the next 0-based index is exactly it.
                model.goToExercise(idx: model.exerciseIndex)
            }
        } else if targetMet {
            // Last exercise complete — offer to finish.
            LSPrimaryButton(label: "Finish →") { showFinishDialog = true }
        } else {
            LSPrimaryButton(label: "Log Set") {
                loggerTarget = .new(setNumber: ex.loggedSets.count + 1)
            }
        }
    }

    // MARK: All-done block (cursor past the last logged-needed exercise)

    private var finishedBlock: some View {
        VStack(spacing: LSSpace.s3) {
            EyebrowLabel(text: "Session")
            Text("ALL DONE")
                .font(LSType.displayHero)
                .foregroundStyle(LSColor.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("Save the session from here or your phone.")
                .font(LSType.body)
                .foregroundStyle(LSColor.text2)
            LSPrimaryButton(label: "Finish") { showFinishDialog = true }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Helpers

    private func repsLabel(_ ex: WatchExerciseVM) -> String {
        ex.targetRepsMin == ex.targetRepsMax
            ? "\(ex.targetRepsMin)"
            : "\(ex.targetRepsMin)–\(ex.targetRepsMax)"
    }

    private func pad2(_ n: Int) -> String { String(format: "%02d", n) }
}

// MARK: - LoggedSetRow

/// One logged set, e.g. "SET 01   21 KG × 10 · RIR 0". Tap to edit; long-press
/// to delete (mirrors the phone's tap-to-edit + long-press-delete).
struct LoggedSetRow: View {
    let index: Int
    let set: WatchSetVM
    let unit: String
    let onTap: () -> Void
    let onDelete: () -> Void

    @Environment(\.lsAccent) private var accent

    /// Long-press surfaces a delete confirmation (the phone's long-press-to-
    /// delete, adapted to the wrist where there's no swipe-to-delete outside a
    /// List).
    @State private var showDelete = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text("SET \(String(format: "%02d", index + 1))")
                    .font(LSType.monoMeta)
                    .tracking(0.8)
                    .foregroundStyle(LSColor.text2)
                    .lineLimit(1)
                    .fixedSize()

                // The whole "21 KG × 10 · RIR 0" cluster is ONE Text (per-segment
                // styling via Text.foregroundStyle, which returns Text on
                // watchOS 10), so it scales down as a single unit to fit the row
                // instead of wrapping the trailing "· RIR n" onto a second line.
                // It takes the remaining width, right-aligned.
                (
                    Text(WeightConv.label(set.weightKg, unit: unit))
                        .font(LSType.monoData)
                        .foregroundStyle(accent.accent)
                    + Text("  ×  ")
                        .font(LSType.monoMeta)
                        .foregroundStyle(LSColor.text2)
                    + Text("\(set.reps)")
                        .font(LSType.monoData)
                        .foregroundStyle(LSColor.text)
                    + Text("   ·  RIR \(set.rir)")
                        .font(LSType.monoMeta)
                        .foregroundStyle(LSColor.text2)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LSRadius.r3, style: .continuous)
                    .fill(LSColor.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: LSRadius.r3, style: .continuous)
                            .stroke(accent.accent.opacity(0.5), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onLongPressGesture { showDelete = true }
        .confirmationDialog("Set \(index + 1)", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Edit", action: onTap)
            Button("Delete set", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - PendingSetRow

/// Placeholder row for an unfilled target set. The next-to-log slot reads
/// "TAP TO LOG" in accent; later slots are inert "— PENDING".
struct PendingSetRow: View {
    let index: Int
    let isNext: Bool

    @Environment(\.lsAccent) private var accent

    var body: some View {
        HStack(spacing: 6) {
            Text("SET \(String(format: "%02d", index + 1))")
                .font(LSType.monoMeta)
                .tracking(0.8)
                .foregroundStyle(LSColor.text2)
            Spacer(minLength: 4)
            Text(isNext ? "TAP TO LOG" : "— PENDING")
                .font(LSType.monoMeta)
                .tracking(0.8)
                .foregroundStyle(isNext ? accent.accent : LSColor.text3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LSRadius.r3, style: .continuous)
                .stroke(isNext ? accent.accent : LSColor.border, lineWidth: 1)
        )
    }
}
