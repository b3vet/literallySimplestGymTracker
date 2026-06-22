//
//  WorkoutSessionManager.swift
//  LSWatch Watch App
//
//  HealthKit live-workout wrapper for the on-watch logging session.
//
//  Wraps an `HKWorkoutSession` + `HKLiveWorkoutBuilder` for a
//  `.traditionalStrengthTraining` / `.indoor` workout so the watch shows the
//  green "workout in progress" status, keeps the app alive in the background,
//  and (when authorized) records the workout + active-energy/heart-rate samples
//  to Health on `end(save: true)`.
//
//  DEFENSIVE BY DESIGN: every HealthKit touchpoint is guarded by
//  `HKHealthStore.isHealthDataAvailable()` and wrapped in `try?`. If the
//  HealthKit entitlement is missing, authorization is denied, or the API throws,
//  this manager silently no-ops — the workout-logging UI keeps working without
//  HealthKit. Nothing here is allowed to crash the app.
//

import Foundation
import HealthKit
import Observation

@Observable
final class WorkoutSessionManager: NSObject {
  /// Latest heart-rate sample in beats per minute, or nil if none/unavailable.
  private(set) var heartRate: Double?

  /// Cumulative active energy burned in kilocalories for the live session.
  private(set) var activeEnergy: Double?

  /// True between a successful `start()` and the next `end(...)`.
  private(set) var isRunning: Bool = false

  // MARK: - Private

  private let healthStore = HKHealthStore()
  private var workoutSession: HKWorkoutSession?
  private var builder: HKLiveWorkoutBuilder?

  private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)
  private let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
  private let workoutType = HKObjectType.workoutType()

  /// HealthKit HARD-REQUIRES the usage-description strings in Info.plist:
  /// calling `requestAuthorization` without them terminates the app immediately
  /// (a precondition failure — NOT a catchable Swift error). Until the watch
  /// Info.plist is wired (LSWatchConfig/Info.plist), we skip HealthKit entirely
  /// so the companion runs crash-free. This is the true graceful-degrade gate.
  private static var healthKitUsageDescribed: Bool {
    let b = Bundle.main
    return b.object(forInfoDictionaryKey: "NSHealthShareUsageDescription") != nil
        && b.object(forInfoDictionaryKey: "NSHealthUpdateUsageDescription") != nil
  }

  // MARK: - Authorization

  /// Request the share/read permissions we need. No-ops when HealthKit is
  /// unavailable; never throws to the caller.
  func requestAuthorization(_ completion: ((Bool) -> Void)? = nil) {
    guard HKHealthStore.isHealthDataAvailable(), Self.healthKitUsageDescribed else {
      completion?(false)
      return
    }

    var share: Set<HKSampleType> = [workoutType]
    if let activeEnergyType { share.insert(activeEnergyType) }

    var read: Set<HKObjectType> = []
    if let heartRateType { read.insert(heartRateType) }
    if let activeEnergyType { read.insert(activeEnergyType) }

    healthStore.requestAuthorization(toShare: share, read: read) { success, _ in
      completion?(success)
    }
  }

  // MARK: - Lifecycle

  /// Begin a live strength-training workout. Idempotent: a no-op if already
  /// running. Requests authorization first, then spins up the session/builder.
  /// Any failure degrades gracefully to "no HealthKit" without crashing.
  func start() {
    guard HKHealthStore.isHealthDataAvailable(), Self.healthKitUsageDescribed else { return }
    guard !isRunning, workoutSession == nil else { return }

    // Make sure we have permission before constructing the session; harmless if
    // already granted/denied — we still attempt and simply no-op on throw.
    requestAuthorization { [weak self] _ in
      self?.beginSession()
    }
  }

  private func beginSession() {
    guard HKHealthStore.isHealthDataAvailable() else { return }
    guard workoutSession == nil else { return }

    let config = HKWorkoutConfiguration()
    config.activityType = .traditionalStrengthTraining
    config.locationType = .indoor

    do {
      let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
      let builder = session.associatedWorkoutBuilder()
      builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)

      session.delegate = self
      builder.delegate = self

      self.workoutSession = session
      self.builder = builder

      let startDate = Date()
      session.startActivity(with: startDate)
      builder.beginCollection(withStart: startDate) { [weak self] _, _ in
        // Collection started (or failed silently); mark running regardless so
        // lifecycle stays balanced and a later end(...) tears down cleanly.
        DispatchQueue.main.async { self?.isRunning = true }
      }
      // Optimistically reflect running state for the UI even before the async
      // collection callback lands.
      DispatchQueue.main.async { self.isRunning = true }
    } catch {
      // Entitlement missing / construction failed — degrade to no HealthKit.
      workoutSession = nil
      builder = nil
      isRunning = false
    }
  }

  /// End the live workout. `save: true` finalises and writes the workout to
  /// Health; `save: false` discards it. Safe to call when nothing is running.
  func end(save: Bool) {
    let session = workoutSession
    let builder = self.builder

    // Tear down our references immediately so state stays consistent even if
    // the async callbacks below never fire (e.g. unauthorized).
    workoutSession = nil
    self.builder = nil
    isRunning = false
    heartRate = nil
    activeEnergy = nil

    guard let session, let builder else { return }

    session.end()

    let endDate = Date()
    builder.endCollection(withEnd: endDate) { _, _ in
      if save {
        builder.finishWorkout { _, _ in /* saved or silently failed */ }
      } else {
        builder.discardWorkout()
      }
    }
  }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
  func workoutSession(
    _ workoutSession: HKWorkoutSession,
    didChangeTo toState: HKWorkoutSessionState,
    from fromState: HKWorkoutSessionState,
    date: Date
  ) {
    // No-op: lifecycle is driven explicitly by start()/end(). We still conform
    // so the session has a delegate and won't warn.
  }

  func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
    // Degrade gracefully — drop the session, keep the app usable.
    DispatchQueue.main.async {
      self.workoutSession = nil
      self.builder = nil
      self.isRunning = false
    }
  }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
  func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
    // Events (pause/resume/etc.) — not surfaced in v1.
  }

  func workoutBuilder(
    _ workoutBuilder: HKLiveWorkoutBuilder,
    didCollectDataOf collectedTypes: Set<HKSampleType>
  ) {
    for type in collectedTypes {
      guard let quantityType = type as? HKQuantityType,
            let statistics = workoutBuilder.statistics(for: quantityType) else { continue }

      if quantityType == heartRateType {
        let bpmUnit = HKUnit.count().unitDivided(by: .minute())
        let value = statistics.mostRecentQuantity()?.doubleValue(for: bpmUnit)
        DispatchQueue.main.async { self.heartRate = value }
      } else if quantityType == activeEnergyType {
        let kcal = statistics.sumQuantity()?.doubleValue(for: .kilocalorie())
        DispatchQueue.main.async { self.activeEnergy = kcal }
      }
    }
  }
}
