import Foundation

#if canImport(HealthKit)
import HealthKit

/// Reads Apple Watch sleep architecture, overnight HRV (SDNN), and sleeping wrist temperature
/// from HealthKit to automatically derive `sleep_midpoint` and recent schedule shift (`1 - R_phi` proxy).
///
/// Epistemic boundary: HealthKit biometrics provide circadian phase and autonomic context;
/// they do not replace behavioral timing measurements (`JND` / `CV_timing`) or clinical diagnosis.
public final class HealthKitCircadianBridge: @unchecked Sendable {
    private let store = HKHealthStore()

    public init() {}

    public var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    public func requestAuthorization() async throws {
        guard isAvailable else { return }
        var readTypes: Set<HKObjectType> = []
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            readTypes.insert(sleep)
        }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            readTypes.insert(hrv)
        }
        if #available(iOS 16.0, watchOS 9.0, macOS 13.0, *) {
            if let temp = HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
                readTypes.insert(temp)
            }
        }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Queries the last `days` nights of Apple Watch sleep samples and computes:
    /// - circular mean sleep midpoint (`computedSleepMidpoint`)
    /// - schedule irregularity / drift (`computedShiftHours`)
    /// - mean sleep duration + latest overnight HRV
    public func syncCircadianContext(days: Int = 7) async -> HealthKitCircadianContext? {
        guard isAvailable,
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: end) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        let sleepSamples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }

        // Filter asleep intervals (exclude .inBed and .awake)
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue
        ]
        let asleep = sleepSamples.filter { asleepValues.contains($0.value) }
        guard !asleep.isEmpty else { return nil }

        // Group intervals into nightly bouts (gaps > 3 hours start a new night)
        var nights: [(start: Date, end: Date, totalSec: TimeInterval)] = []
        for s in asleep {
            if let last = nights.last, s.startDate.timeIntervalSince(last.end) < 3 * 3600 {
                nights[nights.count - 1].end = max(last.end, s.endDate)
                nights[nights.count - 1].totalSec += s.endDate.timeIntervalSince(s.startDate)
            } else {
                nights.append((s.startDate, s.endDate, s.endDate.timeIntervalSince(s.startDate)))
            }
        }

        // Ignore short naps < 3 hours
        let mainNights = nights.filter { $0.totalSec >= 3 * 3600 }
        guard !mainNights.isEmpty else { return nil }

        let cal = Calendar.current
        let midpoints: [Double] = mainNights.map { night in
            let midDate = night.start.addingTimeInterval(night.end.timeIntervalSince(night.start) / 2.0)
            let c = cal.dateComponents([.hour, .minute], from: midDate)
            return Double(c.hour ?? 3) + Double(c.minute ?? 30) / 60.0
        }

        // Circular mean for sleep midpoint
        let sinSum = midpoints.reduce(0.0) { $0 + sin($1 / 24.0 * 2.0 * .pi) }
        let cosSum = midpoints.reduce(0.0) { $0 + cos($1 / 24.0 * 2.0 * .pi) }
        let meanAngle = atan2(sinSum, cosSum)
        let meanMidpoint = CognitiveEngine.mod24(meanAngle / (2.0 * .pi) * 24.0)

        // Circular standard deviation / drift in hours as behavioral proxy for schedule shift
        let R = hypot(sinSum, cosSum) / Double(midpoints.count)
        let shiftHours = CognitiveEngine.clamp(sqrt(max(0.0, -2.0 * log(max(0.05, R)))) * (24.0 / (2.0 * .pi)), 0.0, 6.0)
        let avgDurHours = (mainNights.map(\.totalSec).reduce(0, +) / Double(mainNights.count)) / 3600.0

        let latestHRV = await fetchLatestQuantity(identifier: .heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), since: start)

        return HealthKitCircadianContext(
            nightsAnalyzed: mainNights.count,
            computedSleepMidpoint: (meanMidpoint * 2.0).rounded() / 2.0,
            computedShiftHours: (shiftHours * 2.0).rounded() / 2.0,
            averageSleepDurationHours: (avgDurHours * 10.0).rounded() / 10.0,
            overnightHRVms: latestHRV.map { ($0 * 10.0).rounded() / 10.0 }
        )
    }

    private func fetchLatestQuantity(identifier: HKQuantityTypeIdentifier, unit: HKUnit, since: Date) async -> Double? {
        guard let qType = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictStartDate)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(
                sampleType: qType,
                predicate: pred,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, _ in
                let val = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: val)
            }
            store.execute(q)
        }
    }
}
#endif
