//
//  ContentView.swift
//  LSWatch Watch App
//
//  Root of the watch UI. Branches on session state:
//    - idle (model.session == nil) -> IdleView ("NO WORKOUT").
//    - active -> NavigationStack hosting a vertical-paged TabView over
//      [CurrentExerciseView, ProgramListView]. Crown scrolls each page; a swipe
//      between pages mirrors the phone's [Current · Program] toggle (SOW §5.1).
//
//  The accent is injected from LSWatchApp; nothing here re-reads it.
//

import SwiftUI

struct ContentView: View {
    /// Owned by LSWatchApp; @Bindable so child views can drive mutations.
    @Bindable var model: WatchWorkoutModel

    var body: some View {
        Group {
            if model.session == nil {
                // No active workout. Distinguish "just finished here" (celebrate
                // + point to the phone) from a plain idle state.
                if model.justFinished {
                    WorkoutCompleteView(onDone: model.dismissFinished)
                } else {
                    IdleView()
                }
            } else {
                NavigationStack {
                    TabView {
                        CurrentExerciseView(model: model)
                        ProgramListView(model: model)
                    }
                    .tabViewStyle(.verticalPage)
                }
            }
        }
        .background(LSColor.bg.ignoresSafeArea())
        // The whole app is dark, always.
        .preferredColorScheme(.dark)
    }
}

// MARK: - Idle

/// Shown when there's no active workout. Mirrors the phone's
/// `_NoActiveWorkoutScaffold`: a condensed-uppercase headline + a body hint that
/// the workout is started from the phone (the watch is a companion, not a
/// launcher).
struct IdleView: View {
    var body: some View {
        VStack(spacing: LSSpace.s2) {
            Spacer(minLength: 0)
            Text("NO WORKOUT")
                .font(LSType.displayM)
                .foregroundStyle(LSColor.text)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Start one on your iPhone")
                .font(LSType.body)
                .foregroundStyle(LSColor.text2)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, LSSpace.s3)
        .background(LSColor.bg)
    }
}

// MARK: - Workout complete

/// Shown briefly after a watch-initiated finish: a celebratory "well done" with
/// a pointer to the phone (the full summary lives there), and a Done button to
/// return to idle.
struct WorkoutCompleteView: View {
    let onDone: () -> Void
    @Environment(\.lsAccent) private var accent

    var body: some View {
        VStack(spacing: LSSpace.s2) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(accent.accent)
            Text("WORKOUT COMPLETE")
                .font(LSType.displayM)
                .foregroundStyle(LSColor.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text("Well done. Check the summary on your iPhone.")
                .font(LSType.body)
                .foregroundStyle(LSColor.text2)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            LSPrimaryButton(label: "Done", action: onDone)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, LSSpace.s3)
        .background(LSColor.bg)
    }
}

#Preview("Idle") {
    IdleView()
        .environment(\.lsAccent, .brand)
}

#Preview("Complete") {
    WorkoutCompleteView(onDone: {})
        .environment(\.lsAccent, .brand)
}
