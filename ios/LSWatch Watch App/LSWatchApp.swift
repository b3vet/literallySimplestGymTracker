//
//  LSWatchApp.swift
//  LSWatch Watch App
//
//  @main entry. Owns the single `WatchWorkoutModel` (which in turn owns the
//  WCSession + HealthKit live workout) and injects the user's accent — mirrored
//  from the phone snapshot — into the SwiftUI environment so every descendant
//  recolors automatically when the snapshot accent changes (LSTheme rule).
//

import SwiftUI

@main
struct LSWatch_Watch_AppApp: App {
    /// Single source of truth for the watch session. @Observable, so reading its
    /// `accentArgb` here re-evaluates `body` (and re-injects the accent) whenever
    /// the phone pushes a new accent.
    @State private var model = WatchWorkoutModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                // Accent is dynamic: decode the snapshot's 0xAARRGGBB ints into
                // the LSAccent pair and push it down the tree. The model exposes
                // these as `Int`; LSAccent wants `Int64?`.
                .environment(
                    \.lsAccent,
                    LSAccent(
                        argb: Int64(model.accentArgb),
                        inkArgb: Int64(model.accentInkArgb)
                    )
                )
        }
    }
}
