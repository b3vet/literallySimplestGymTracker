//
//  ProgramListView.swift
//  LSWatch Watch App
//
//  Watch-adapted `program_status_sheet.dart` (SOW §5.5). The full queue: a
//  header (program day + "x of n done · elapsed"), then one row per exercise
//  with a state chip (done / current / upcoming / skipped — same rule as the
//  phone's `_stateOf`) and a "x/n SETS · reps · weight" meta line. Tapping a row
//  jumps the cursor there and pages back to Current.
//

import SwiftUI

struct ProgramListView: View {
    @Bindable var model: WatchWorkoutModel
    @Environment(\.lsAccent) private var accent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LSSpace.s2) {
                if let session = model.session {
                    headerBlock(session)
                    Rectangle()
                        .fill(LSColor.border)
                        .frame(height: 1)

                    ForEach(Array(session.queue.enumerated()), id: \.element.id) { idx, ex in
                        let rowState = state(session, idx: idx)
                        ProgramRow(
                            index: idx,
                            exercise: ex,
                            state: rowState,
                            unit: model.unit,
                            onTap: { model.goToExercise(idx: idx) }
                        )
                        // Skipped exercises are out of the session for good —
                        // their row is non-tappable so the cursor can't jump back.
                        .disabled(rowState == .skipped)
                        if idx < session.queue.count - 1 {
                            Rectangle()
                                .fill(LSColor.border)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, LSSpace.s3)
            .padding(.vertical, LSSpace.s2)
        }
        .background(LSColor.bg)
    }

    // MARK: Header

    @ViewBuilder
    private func headerBlock(_ session: WatchSession) -> some View {
        EyebrowLabel(text: session.programDayName.isEmpty ? "Program" : "Program · \(session.programDayName)")
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            Text("\(completedCount(session)) OF \(session.queue.count) DONE · \(TimeFormat.coarse(model.elapsed))")
                .font(LSType.monoMeta)
                .tracking(0.8)
                .foregroundStyle(LSColor.text2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: State rule (mirrors `_stateOf`)

    private func state(_ session: WatchSession, idx: Int) -> ProgramRowState {
        let ex = session.queue[idx]
        // A durably-skipped slot always reads as skipped, regardless of cursor.
        if ex.isSkipped { return .skipped }
        let logged = ex.completedGroups
        if logged >= ex.targetSets { return .done }
        if idx == session.cursorExerciseIdx { return .current }
        if idx < session.cursorExerciseIdx { return .skipped }
        return .upcoming
    }

    private func completedCount(_ session: WatchSession) -> Int {
        session.queue.reduce(0) { acc, ex in
            acc + (ex.completedGroups >= ex.targetSets ? 1 : 0)
        }
    }
}

// MARK: - Row state

enum ProgramRowState { case done, current, upcoming, skipped }

// MARK: - ProgramRow

struct ProgramRow: View {
    let index: Int
    let exercise: WatchExerciseVM
    let state: ProgramRowState
    let unit: String
    let onTap: () -> Void

    @Environment(\.lsAccent) private var accent

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                stateChip
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name.uppercased())
                        .font(LSType.displaySemibold)
                        .foregroundStyle(state == .skipped ? LSColor.text3 : LSColor.text)
                        .strikethrough(state == .skipped, color: LSColor.text3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(metaLine)
                        .font(LSType.monoMeta)
                        .tracking(0.6)
                        .foregroundStyle(LSColor.text2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                if state == .current {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accent.accent)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    // MARK: State chip — mirrors `_StateChip`

    private var stateChip: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LSRadius.r2, style: .continuous)
                .fill(chipFill)
                .overlay(
                    RoundedRectangle(cornerRadius: LSRadius.r2, style: .continuous)
                        .stroke(chipStroke, lineWidth: 1)
                )
            if state == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent.accentInk)
            } else if state == .skipped {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LSColor.text3)
            } else {
                Text(String(format: "%02d", index + 1))
                    .font(LSType.monoMeta)
                    .foregroundStyle(chipText)
            }
        }
        .frame(width: 30, height: 30)
    }

    private var chipFill: Color {
        switch state {
        case .done:    return accent.accent
        case .current: return accent.accentDim
        case .upcoming, .skipped: return LSColor.surface
        }
    }

    private var chipStroke: Color {
        switch state {
        case .done:    return accent.accent
        case .current: return accent.accent
        case .upcoming, .skipped: return LSColor.border
        }
    }

    private var chipText: Color {
        switch state {
        case .current: return accent.accent
        case .skipped: return LSColor.text3
        default:       return LSColor.text2
        }
    }

    private var metaLine: String {
        let logged = exercise.completedGroups
        let reps = exercise.targetRepsMin == exercise.targetRepsMax
            ? "\(exercise.targetRepsMin)"
            : "\(exercise.targetRepsMin)–\(exercise.targetRepsMax)"
        let weight = WeightConv.label(exercise.defaultWeightKg, unit: unit)
        return "\(logged)/\(exercise.targetSets) SETS · \(reps) REPS · \(weight)"
    }
}
