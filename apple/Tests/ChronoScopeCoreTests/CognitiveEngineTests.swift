import XCTest
@testable import ChronoScopeCore

final class CognitiveEngineTests: XCTestCase {
    func testScaleInvarianceMirrorsLeanCT01() throws {
        let base = [1420.0, 1510.0, 1485.0, 1560.0, 1490.0]
        let scaled = base.map { $0 * 1.37 }
        let s1 = try XCTUnwrap(CognitiveEngine.computeCvStats(durationsMs: base))
        let s2 = try XCTUnwrap(CognitiveEngine.computeCvStats(durationsMs: scaled))
        XCTAssertEqual(s1.cv, s2.cv, accuracy: 1e-12)
        XCTAssertEqual(s2.bias, s1.bias * 1.37, accuracy: 1e-12)
    }

    func testTierOrderingSoundnessMirrorsLeanCT04() {
        let profile = ChronoScopeProfile()
        let sched = CognitiveEngine.computeSchedule(profile: profile, overrideHourLocal: 10.5)
        XCTAssertEqual(sched.currentTier, .peak)
        let peaks = sched.slots.filter { $0.tier == .peak }
        let mods = sched.slots.filter { $0.tier == .moderate }
        let lows = sched.slots.filter { $0.tier == .lowReliability }
        XCTAssertFalse(peaks.isEmpty)
        XCTAssertFalse(lows.isEmpty)
        if let maxP = peaks.map(\.logCv).max(), let minM = mods.map(\.logCv).min() {
            XCTAssertLessThan(maxP, minM)
        }
        if let maxM = mods.map(\.logCv).max(), let minL = lows.map(\.logCv).min() {
            XCTAssertLessThan(maxM, minL)
        }
    }

    func testIcsExportRFC5545Compliance() {
        let profile = ChronoScopeProfile()
        let sched = CognitiveEngine.computeSchedule(profile: profile, overrideHourLocal: 10.5)
        let ics = CognitiveEngine.generateIcs(schedule: sched, days: 3, includeMorningCheck: true)
        XCTAssertTrue(ics.hasPrefix("BEGIN:VCALENDAR\r\n"))
        XCTAssertTrue(ics.hasSuffix("END:VCALENDAR\r\n"))
        XCTAssertTrue(ics.contains("[Graviton Peak]"))
        XCTAssertTrue(ics.contains("[Graviton Routine]"))
        let lines = ics.components(separatedBy: "\r\n")
        XCTAssertTrue(lines.allSatisfy { $0.count <= 75 })
    }
}
