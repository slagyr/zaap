#if targetEnvironment(simulator)
import Foundation
import HealthKit
import os

/// Seeds synthetic health data into the simulator's HealthKit store for testing.
/// Only compiled and available in simulator builds.
@MainActor
final class HealthDataSeeder: ObservableObject {

    @Published var status: SeedStatus = .idle

    enum SeedStatus: Equatable {
        case idle
        case seeding
        case done(String)
        case failed(String)
    }

    private let healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "com.zaap.app", category: "HealthDataSeeder")

    // MARK: - Authorization

    private func requestWriteAuth() async throws {
        let types: Set<HKSampleType> = [
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.activeEnergyBurned),
            HKWorkoutType.workoutType(),
        ]
        try await healthStore.requestAuthorization(toShare: types, read: types)
    }

    // MARK: - Seed

    func seedAll() {
        Task {
            status = .seeding
            do {
                try await requestWriteAuth()
                let calendar = Calendar.current
                let now = Date()
                let today = calendar.startOfDay(for: now)

                try await seedSleep(calendar: calendar, today: today)
                try await seedHeartRate(calendar: calendar, today: today, now: now)
                try await seedActivity(calendar: calendar, today: today, now: now)
                try await seedWorkout(calendar: calendar, today: today)

                status = .done("Seeded sleep, heart rate, activity & workout ✓")
                logger.info("Health data seeding complete")
            } catch {
                status = .failed(error.localizedDescription)
                logger.error("Seeding failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Sleep

    private func seedSleep(calendar: Calendar, today: Date) async throws {
        // Last night: 10:30 PM → 6:30 AM
        let bedtime = calendar.date(byAdding: .day, value: -1, to: today)!
            .addingTimeInterval(22.5 * 3600)   // 10:30 PM yesterday
        let wakeTime = today.addingTimeInterval(6.5 * 3600)             // 6:30 AM today

        let sleepType = HKCategoryType(.sleepAnalysis)

        // Build sleep stage blocks
        var samples: [HKSample] = []

        func stage(_ value: HKCategoryValueSleepAnalysis, from: Date, to: Date) -> HKCategorySample {
            HKCategorySample(type: sleepType, value: value.rawValue, start: from, end: to)
        }

        var t = bedtime
        // In bed (10:30 - 11:00)
        samples.append(stage(.inBed, from: t, to: t + 1800)); t += 1800
        // Core (11:00 - 12:30)
        samples.append(stage(.asleepCore, from: t, to: t + 5400)); t += 5400
        // Deep (12:30 - 1:30)
        samples.append(stage(.asleepDeep, from: t, to: t + 3600)); t += 3600
        // REM (1:30 - 2:30)
        samples.append(stage(.asleepREM, from: t, to: t + 3600)); t += 3600
        // Core (2:30 - 3:30)
        samples.append(stage(.asleepCore, from: t, to: t + 3600)); t += 3600
        // Deep (3:30 - 4:15)
        samples.append(stage(.asleepDeep, from: t, to: t + 2700)); t += 2700
        // REM (4:15 - 5:15)
        samples.append(stage(.asleepREM, from: t, to: t + 3600)); t += 3600
        // Core (5:15 - 6:15)
        samples.append(stage(.asleepCore, from: t, to: t + 3600)); t += 3600
        // Awake (6:15 - 6:30)
        samples.append(stage(.awake, from: t, to: wakeTime))

        try await save(samples)
        logger.info("Seeded \(samples.count) sleep samples")
    }

    // MARK: - Heart Rate

    private func seedHeartRate(calendar: Calendar, today: Date, now: Date) async throws {
        let hrType = HKQuantityType(.heartRate)
        let restingType = HKQuantityType(.restingHeartRate)
        let unit = HKUnit(from: "count/min")

        // HR samples every 30 min from midnight to now
        let hrValues: [Double] = [55, 52, 51, 54, 58, 62, 70, 85, 90, 78, 72, 68,
                                   71, 75, 80, 74, 69, 73, 76, 80, 72, 68, 65, 60]
        var samples: [HKSample] = []
        for (i, bpm) in hrValues.enumerated() {
            let sampleStart = today.addingTimeInterval(Double(i) * 1800)
            guard sampleStart <= now else { break }
            let qty = HKQuantity(unit: unit, doubleValue: bpm)
            samples.append(HKQuantitySample(type: hrType, quantity: qty,
                                            start: sampleStart, end: sampleStart + 60))
        }

        // Resting HR
        let restingQty = HKQuantity(unit: unit, doubleValue: 56)
        samples.append(HKQuantitySample(type: restingType, quantity: restingQty,
                                        start: today, end: today + 60))

        try await save(samples)
        logger.info("Seeded \(samples.count) heart rate samples")
    }

    // MARK: - Activity

    private func seedActivity(calendar: Calendar, today: Date, now: Date) async throws {
        let stepType    = HKQuantityType(.stepCount)
        let distType    = HKQuantityType(.distanceWalkingRunning)
        let energyType  = HKQuantityType(.activeEnergyBurned)

        var samples: [HKSample] = []

        // Steps in ~hourly chunks
        let stepChunks: [(Double, Double)] = [  // (steps, hour offset)
            (200, 7), (450, 8), (300, 9), (180, 10), (400, 11),
            (320, 12), (250, 13), (190, 14), (300, 15), (220, 16)
        ]
        for (steps, hour) in stepChunks {
            let s = today.addingTimeInterval(hour * 3600)
            let e = s + 3600
            guard s <= now else { continue }
            samples.append(HKQuantitySample(type: stepType,
                                            quantity: HKQuantity(unit: .count(), doubleValue: steps),
                                            start: s, end: e))
            // ~0.75m per step
            samples.append(HKQuantitySample(type: distType,
                                            quantity: HKQuantity(unit: .meter(), doubleValue: steps * 0.75),
                                            start: s, end: e))
            // ~0.05 kcal per step
            samples.append(HKQuantitySample(type: energyType,
                                            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: steps * 0.05),
                                            start: s, end: e))
        }

        try await save(samples)
        logger.info("Seeded \(samples.count / 3) activity chunks")
    }

    // MARK: - Workout

    private func seedWorkout(calendar: Calendar, today: Date) async throws {
        // 45-minute outdoor run at 7:00 AM
        let start = today.addingTimeInterval(7 * 3600)
        let end   = start + 45 * 60

        let config = HKWorkoutConfiguration()
        config.activityType = .running
        config.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            builder.beginCollection(withStart: start) { _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }

        // Add calories + distance samples so statistics() works on the workout
        let caloriesSample = HKQuantitySample(
            type: HKQuantityType(.activeEnergyBurned),
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: 380),
            start: start, end: end)
        let distanceSample = HKQuantitySample(
            type: HKQuantityType(.distanceWalkingRunning),
            quantity: HKQuantity(unit: .meter(), doubleValue: 6200),
            start: start, end: end)
        let hrUnit = HKUnit(from: "count/min")
        let hrSamples = stride(from: 0, to: 45, by: 5).map { min -> HKSample in
            let t = start + Double(min) * 60
            return HKQuantitySample(
                type: HKQuantityType(.heartRate),
                quantity: HKQuantity(unit: hrUnit, doubleValue: Double.random(in: 145...175)),
                start: t, end: t + 60)
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            builder.add([caloriesSample, distanceSample] + hrSamples) { _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            builder.endCollection(withEnd: end) { _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            builder.finishWorkout { _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }

        logger.info("Seeded running workout")
    }

    // MARK: - Helpers

    private func save(_ samples: [HKSample]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            healthStore.save(samples) { _, error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }
}
#endif
