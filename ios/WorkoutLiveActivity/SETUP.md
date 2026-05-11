# iOS Live Activity setup

The Dart side, Podfile, Info.plist, and the Swift sources for the Widget
Extension are all in place. The one step that has to be done by hand in
Xcode is creating the actual Widget Extension target — Xcode owns the
project file format and editing it externally is fragile.

## Prerequisites

- macOS with Xcode 15 or newer
- The app's iOS deployment target is already 16.2 (set in `Podfile` and
  `Runner.xcodeproj`).
- Run `cd ios && pod install` once after pulling, so the
  `live_activities` Pod is wired up.

## Steps in Xcode

1. **Open the workspace** (`ios/Runner.xcworkspace`, not the .xcodeproj).
2. **File → New → Target…** and pick **Widget Extension**. Click *Next*.
3. Set:
   - **Product Name**: `WorkoutLiveActivity`
   - **Bundle Identifier**: `com.berke.literallySimplestGymTracker.WorkoutLiveActivity`
     (must be the main app bundle ID + `.WorkoutLiveActivity`)
   - **Include Live Activity**: **checked**
   - **Include Configuration Intent**: unchecked
   - **Embed in Application**: `Runner`
4. Click *Finish* and **don't activate the new scheme** when prompted.
5. Xcode generates template files inside `ios/WorkoutLiveActivity/`. Their
   names collide with the ones we want to keep
   (`WorkoutLiveActivityBundle.swift` and `WorkoutLiveActivity.swift`),
   and Xcode's "Move to Trash" will wipe out the originals too.
   **In Xcode**, right-click each generated file in the project navigator
   and choose **Delete → Remove References** (not Move to Trash). Then
   restore the originals from git:
   `git checkout HEAD -- ios/WorkoutLiveActivity/WorkoutLiveActivityBundle.swift ios/WorkoutLiveActivity/WorkoutLiveActivity.swift`
   Confirm with `ls ios/WorkoutLiveActivity/*.swift` — you should see
   exactly those two files.
6. In Finder, the directory `ios/WorkoutLiveActivity/` now contains the
   Swift sources we want. Drag them into the `WorkoutLiveActivity` group
   in Xcode:
   - `WorkoutLiveActivityBundle.swift`
   - `WorkoutLiveActivity.swift`
   When prompted, set **Copy items if needed = OFF**, **Added folders =
   Create groups**, and **Add to targets = WorkoutLiveActivity** only
   (uncheck Runner).
7. The pre-existing `Info.plist` in `ios/WorkoutLiveActivity/` is the one
   you want; if Xcode generated its own, replace its path in the target's
   *Build Settings → Packaging → Info.plist File* with
   `WorkoutLiveActivity/Info.plist`.
8. **App Group capability** (required by the `live_activities` plugin):
   - Select the *Runner* target → **Signing & Capabilities** → **+ Capability**
     → **App Groups** → add `group.com.berke.literallySimplestGymTracker`.
   - Select the *WorkoutLiveActivity* target → same capability with the
     same group ID.
   - This ID must match `liveActivityAppGroup` in
     `lib/features/workout/application/live_activity_controller.dart`.
9. Set **Deployment Target** of the WorkoutLiveActivity target to **iOS
   16.2** (Build Settings → Deployment).
10. Build & run on a real device (Live Activities don't render reliably on
    iOS 16 simulators; iOS 17+ simulators work).

## Smoke test

- Start a workout in the app.
- Lock the device.
- The lock screen should show the activity with the current exercise.
- Log a set; the activity should reflect the new last weight × reps within
  ~1 second.
- The Dynamic Island compact view should show a dumbbell icon and either
  the rest countdown (when resting) or `current/total` exercise progress.
- Finish the workout; the activity should disappear within a few seconds.

## Disabling

If you don't want to set this up right now, the Flutter code is
defensive — `LiveActivityController` silently no-ops when the extension
isn't available. The app will run normally; the Live Activity simply
won't appear. The toggle in **Settings → Lock screen → Live Activity**
also lets you turn it off without rebuilding.
