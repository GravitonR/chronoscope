import Foundation

// MARK: - Data Models (Schema-compatible with graviton-cognitive-state/v1 & MCP server)

public enum PrecisionTier: String, Codable, Sendable, CaseIterable {
    case peak
    case moderate
    case lowReliability = "low_reliability"
    case rest

    public var label: String {
        switch self {
        case .peak: return "Peak Precision"
        case .moderate: return "Steady / Moderate"
        case .lowReliability: return "Low Reliability · Routine"
        case .rest: return "Off-Hours / Recovery"
        }
    }

    public var shortLabel: String {
        switch self {
        case .peak: return "PEAK"
        case .moderate: return "STEADY"
        case .lowReliability: return "ROUTINE"
        case .rest: return "REST"
        }
    }

    public var recommendedTasks: [String] {
        switch self {
        case .peak:
            return [
                "Deep analytical work, proofs, architecture, and complex coding",
                "High-stakes writing, research synthesis, and strategic decisions"
            ]
        case .moderate:
            return [
                "Collaborative sessions, code reviews, and structured implementation",
                "Meetings, feedback loops, and medium-complexity execution"
            ]
        case .lowReliability:
            return [
                "Routine administration, email triage, scheduling, and logistics",
                "Light reading, organizing notes, or a short recovery walk"
            ]
        case .rest:
            return ["Wind-down, circadian light hygiene, and restorative sleep"]
        }
    }

    public var deferTasks: [String] {
        switch self {
        case .peak:
            return ["Inbox triage, routine admin, and passive status meetings"]
        case .moderate:
            return ["Most fragile first-principles work if a Peak block is upcoming"]
        case .lowReliability:
            return ["High-precision quantitative work, irreversible decisions, or dense debugging"]
        case .rest:
            return ["Cognitive performance work and bright-screen late sessions"]
        }
    }
}

public struct ProfileSettings: Codable, Sendable, Equatable {
    public var sleepMidpoint: Double
    public var shiftHours: Double
    public var alertness: Int
    public var workStart: Double
    public var workEnd: Double
    public var includeMorningCheck: Bool

    enum CodingKeys: String, CodingKey {
        case sleepMidpoint = "sleep_midpoint"
        case shiftHours = "shift_hours"
        case alertness
        case workStart = "work_start"
        case workEnd = "work_end"
        case includeMorningCheck = "include_morning_check"
    }

    public init(
        sleepMidpoint: Double = 3.5,
        shiftHours: Double = 0.5,
        alertness: Int = 7,
        workStart: Double = 8.0,
        workEnd: Double = 20.0,
        includeMorningCheck: Bool = true
    ) {
        self.sleepMidpoint = sleepMidpoint
        self.shiftHours = shiftHours
        self.alertness = alertness
        self.workStart = workStart
        self.workEnd = workEnd
        self.includeMorningCheck = includeMorningCheck
    }
}

public struct HealthKitCircadianContext: Codable, Sendable, Equatable {
    public var nightsAnalyzed: Int
    public var computedSleepMidpoint: Double
    public var computedShiftHours: Double
    public var averageSleepDurationHours: Double
    public var overnightHRVms: Double?
    public var wristTempDeltaC: Double?
    public var syncedAtISO: String

    enum CodingKeys: String, CodingKey {
        case nightsAnalyzed = "nights_analyzed"
        case computedSleepMidpoint = "computed_sleep_midpoint"
        case computedShiftHours = "computed_shift_hours"
        case averageSleepDurationHours = "average_sleep_duration_hours"
        case overnightHRVms = "overnight_hrv_ms"
        case wristTempDeltaC = "wrist_temp_delta_c"
        case syncedAtISO = "synced_at_iso"
    }

    public init(
        nightsAnalyzed: Int,
        computedSleepMidpoint: Double,
        computedShiftHours: Double,
        averageSleepDurationHours: Double,
        overnightHRVms: Double? = nil,
        wristTempDeltaC: Double? = nil,
        syncedAtISO: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.nightsAnalyzed = nightsAnalyzed
        self.computedSleepMidpoint = computedSleepMidpoint
        self.computedShiftHours = computedShiftHours
        self.averageSleepDurationHours = averageSleepDurationHours
        self.overnightHRVms = overnightHRVms
        self.wristTempDeltaC = wristTempDeltaC
        self.syncedAtISO = syncedAtISO
    }
}

public struct TimingSession: Codable, Sendable, Identifiable, Equatable {
    public var id: String { "\(iso)-\(cvTiming)" }
    public var iso: String
    public var hourLocal: Double
    public var sleepMidpoint: Double
    public var phaseDeg: Double
    public var sleepPressureS: Double
    public var alertness: Int
    public var shiftHours: Double
    public var cvTiming: Double
    public var jndMs: Double?
    public var bias: Double
    public var source: String
    public var synthetic: Bool

    enum CodingKeys: String, CodingKey {
        case iso
        case hourLocal = "hour_local"
        case sleepMidpoint = "sleep_midpoint"
        case phaseDeg = "phase_deg"
        case sleepPressureS = "sleep_pressure_s"
        case alertness
        case shiftHours = "shift_hours"
        case cvTiming = "cv_timing"
        case jndMs = "jnd_ms"
        case bias
        case source
        case synthetic
    }

    public var phaseRad: Double { phaseDeg * .pi / 180.0 }
    public var misalignmentProxy: Double { min(1.0, max(0.0, shiftHours / 6.0)) }

    public init(
        iso: String = ISO8601DateFormatter().string(from: Date()),
        hourLocal: Double,
        sleepMidpoint: Double,
        sleepPressureS: Double,
        alertness: Int,
        shiftHours: Double,
        cvTiming: Double,
        jndMs: Double?,
        bias: Double,
        source: String = "apple-companion",
        synthetic: Bool = false
    ) {
        self.iso = iso
        self.hourLocal = hourLocal
        self.sleepMidpoint = sleepMidpoint
        self.phaseDeg = CognitiveEngine.mod24(hourLocal - sleepMidpoint) * 15.0
        self.sleepPressureS = sleepPressureS
        self.alertness = alertness
        self.shiftHours = shiftHours
        self.cvTiming = cvTiming
        self.jndMs = jndMs
        self.bias = bias
        self.source = source
        self.synthetic = synthetic
    }
}

public struct ChronoScopeProfile: Codable, Sendable, Equatable {
    public var schema: String
    public var updatedAt: String
    public var settings: ProfileSettings
    public var healthkitContext: HealthKitCircadianContext?
    public var sessions: [TimingSession]

    enum CodingKeys: String, CodingKey {
        case schema
        case updatedAt = "updated_at"
        case settings
        case healthkitContext = "healthkit_context"
        case sessions
    }

    public init(
        settings: ProfileSettings = ProfileSettings(),
        healthkitContext: HealthKitCircadianContext? = nil,
        sessions: [TimingSession] = []
    ) {
        self.schema = "graviton-chronoscope-profile/v1"
        self.updatedAt = ISO8601DateFormatter().string(from: Date())
        self.settings = settings
        self.healthkitContext = healthkitContext
        self.sessions = sessions
    }
}

public struct Equation01Fit: Sendable, Equatable {
    public let alpha: Double
    public let betaC: Double
    public let betaS: Double
    public let amp: Double
    public let gamma: Double
    public let eta: Double
    public let kappa: Double
}

public struct CurveSlot: Sendable, Identifiable, Equatable {
    public var id: Int { index }
    public let index: Int
    public let hour: Double
    public let label: String
    public let logCv: Double
    public let cv: Double
    public let inWorkday: Bool
    public let isSleep: Bool
    public let tier: PrecisionTier
    public let precisionIndex: Int
}

public struct ScheduleBlock: Sendable, Identifiable, Equatable {
    public var id: String { "\(tier.rawValue)-\(startHour)-\(endHour)" }
    public let tier: PrecisionTier
    public let startHour: Double
    public let endHour: Double
    public let start: String
    public let end: String
    public let predictedCvMean: Double
    public let precisionIndex: Int
}

public struct CognitiveScheduleResult: Sendable {
    public let mode: String
    public let modeLabel: String
    public let hourLocal: Double
    public let localTime: String
    public let currentTier: PrecisionTier
    public let currentCv: Double
    public let currentPrecisionIndex: Int
    public let currentPhaseDeg: Int
    public let latestJndMs: Double?
    public let tauPeak: Double
    public let tauLow: Double
    public let nextPeakInMinutes: Int?
    public let activePeakRemainingMinutes: Int?
    public let nextPeakWindow: String?
    public let slots: [CurveSlot]
    public let blocks: [ScheduleBlock]
    public let fit: Equation01Fit?
    public let sleepMidpoint: Double
    public let workStart: Double
    public let workEnd: Double
}

// MARK: - Core Mathematical Engine (Mirrors cognitive-engine.js & Lean 4 CT-01..CT-04)

public enum CognitiveEngine {
    public static let targetDurationMs: Double = 1500.0
    public static let epistemicBoundary =
        "Behavioral timing model estimate derived from circadian phase, sleep pressure, and optional psychophysics calibration. Not a medical device, clinical sleep assessment, or direct neural measurement."

    public static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        max(lo, min(hi, v))
    }

    public static func mod24(_ h: Double) -> Double {
        let r = h.truncatingRemainder(dividingBy: 24.0)
        return r < 0 ? r + 24.0 : r
    }

    public static func formatHour(_ h: Double) -> String {
        let norm = mod24(h)
        var hh = Int(floor(norm))
        var mm = Int(round((norm - Double(hh)) * 60.0))
        if mm == 60 {
            hh = (hh + 1) % 24
            mm = 0
        }
        return String(format: "%02d:%02d", hh, mm)
    }

    public static func formatDurationMinutes(_ mins: Int) -> String {
        let m = max(0, mins)
        let h = m / 60
        let rem = m % 60
        if h == 0 { return "\(rem)m" }
        if rem == 0 { return "\(h)h" }
        return "\(h)h \(rem)m"
    }

    public static func getWakeHour(_ sleepMidpoint: Double) -> Double {
        mod24(sleepMidpoint + 3.75)
    }

    public static func getSleepStartHour(_ sleepMidpoint: Double) -> Double {
        mod24(sleepMidpoint - 3.75)
    }

    public static func isInWindow(_ hour: Double, start: Double, end: Double) -> Bool {
        let h = mod24(hour)
        let s = mod24(start)
        let e = mod24(end)
        if s == e { return true }
        if s < e { return h >= s && h < e }
        return h >= s || h < e
    }

    public static func hoursAwakeAt(_ hour: Double, sleepMidpoint: Double) -> Double {
        let sinceWake = mod24(hour - getWakeHour(sleepMidpoint))
        return sinceWake <= 16.5 ? sinceWake : 0.0
    }

    /// Compute exact mean, SD, scale-invariant CV_timing (Lean 4 CT-01), and bias ratio.
    public static func computeCvStats(durationsMs: [Double]) -> (mean: Double, sd: Double, cv: Double, bias: Double)? {
        guard !durationsMs.isEmpty else { return nil }
        let n = Double(durationsMs.count)
        let mean = durationsMs.reduce(0, +) / n
        guard mean > 0 else { return nil }
        let variance = durationsMs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
        let sd = sqrt(variance)
        return (mean, sd, sd / mean, mean / targetDurationMs)
    }

    /// Formally verified 3-tier classifier (mirrors Lean 4 theorem CT-04).
    public static func classifyTier(tauPeak: Double, tauLow: Double, score: Double) -> PrecisionTier {
        if score <= tauPeak { return .peak }
        if score <= tauLow { return .moderate }
        return .lowReliability
    }

    private static func solveLinear(_ A: [[Double]], _ b: [Double]) -> [Double] {
        let n = b.count
        var M = (0..<n).map { A[$0] + [b[$0]] }
        for i in 0..<n {
            var piv = i
            for r in (i + 1)..<n where abs(M[r][i]) > abs(M[piv][i]) {
                piv = r
            }
            M.swapAt(i, piv)
            let diag = abs(M[i][i]) > 1e-12 ? M[i][i] : 1e-9
            for j in i...n { M[i][j] /= diag }
            for r in 0..<n where r != i {
                let f = M[r][i]
                for j in i...n { M[r][j] -= f * M[i][j] }
            }
        }
        return M.map { $0[n] }
    }

    public static func fitEquation01(sessions: [TimingSession]) -> Equation01Fit {
        let p = 6
        var XtX = Array(repeating: Array(repeating: 0.0, count: p), count: p)
        var Xty = Array(repeating: 0.0, count: p)
        for s in sessions {
            let x = [1.0, cos(s.phaseRad), sin(s.phaseRad), s.sleepPressureS / 12.0, Double(s.alertness) / 10.0, s.misalignmentProxy]
            let y = log(max(1e-4, s.cvTiming))
            for i in 0..<p {
                Xty[i] += x[i] * y
                for j in 0..<p { XtX[i][j] += x[i] * x[j] }
            }
        }
        for i in 1..<p { XtX[i][i] += 0.08 }
        let w = solveLinear(XtX, Xty)
        return Equation01Fit(
            alpha: w[0],
            betaC: w[1],
            betaS: w[2],
            amp: hypot(w[1], w[2]),
            gamma: w[3],
            eta: w[4],
            kappa: w[5]
        )
    }

    public static func priorLogCvRaw(hour: Double, sleepMidpoint: Double, shiftHours: Double, alertness: Int) -> Double {
        let phi = mod24(hour - sleepMidpoint) * 15.0 * .pi / 180.0
        let awake = hoursAwakeAt(hour, sleepMidpoint: sleepMidpoint)
        let misalignment = clamp(shiftHours / 6.0, 0.0, 1.0)

        let circ1 = 0.22 * cos(phi - 0.10) - 0.14 * sin(phi - 0.10)
        let inertia = awake < 2.5 ? 0.10 * exp(-awake / 0.65) : 0.0
        let dipCenter = 168.0 * .pi / 180.0
        let postLunchDip = 0.21 * exp(-pow(sin((phi - dipCenter) / 2.0), 2.0) / 0.032)
        let sleepTerm = 0.28 * pow(awake / 16.0, 1.35)
        let alertTerm = -0.028 * (Double(alertness - 7) / 3.0)
        let misalignTerm = 0.34 * misalignment
        return -2.847 + circ1 + inertia + postLunchDip + sleepTerm + alertTerm + misalignTerm
    }

    public static func computeSchedule(
        profile: ChronoScopeProfile,
        now: Date = Date(),
        overrideHourLocal: Double? = nil
    ) -> CognitiveScheduleResult {
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let hourLocal = overrideHourLocal.map(mod24) ?? (Double(comps.hour ?? 10) + Double(comps.minute ?? 0) / 60.0)
        let settings = profile.settings
        let sessions = profile.sessions

        var mode = "chronotype_prior"
        var modeLabel = "Chronotype Prior (uncalibrated)"
        var fit: Equation01Fit? = nil
        var calibration: TimingSession? = nil

        if sessions.count >= 4 {
            fit = fitEquation01(sessions: sessions)
            let hasDemo = sessions.contains { $0.synthetic }
            mode = hasDemo ? "synthetic_demo_fit" : "empirical_fit"
            modeLabel = hasDemo
                ? "Demo Equation 01 Fit (\(sessions.count) sessions)"
                : "Empirical Equation 01 Fit (\(sessions.count) sessions)"
        } else if let latest = sessions.last {
            calibration = latest
            mode = "morning_check_prior"
            modeLabel = "Calibrated Prior (\(sessions.count) check\(sessions.count > 1 ? "s" : ""))"
        }

        func evalLogCv(_ hour: Double) -> Double {
            if let f = fit {
                let phi = mod24(hour - settings.sleepMidpoint) * 15.0 * .pi / 180.0
                let awake = hoursAwakeAt(hour, sleepMidpoint: settings.sleepMidpoint)
                let mis = clamp(settings.shiftHours / 6.0, 0.0, 1.0)
                let v = f.alpha + f.betaC * cos(phi) + f.betaS * sin(phi) +
                    f.gamma * (awake / 12.0) + f.eta * (Double(settings.alertness) / 10.0) + f.kappa * mis
                return clamp(v, log(0.02), log(0.35))
            }
            var v = priorLogCvRaw(
                hour: hour,
                sleepMidpoint: settings.sleepMidpoint,
                shiftHours: settings.shiftHours,
                alertness: settings.alertness
            )
            if let c = calibration {
                let expected = priorLogCvRaw(
                    hour: c.hourLocal,
                    sleepMidpoint: settings.sleepMidpoint,
                    shiftHours: c.shiftHours,
                    alertness: c.alertness
                )
                let obs = log(clamp(c.cvTiming, 0.02, 0.35))
                v += clamp(obs - expected, -0.75, 0.75)
            }
            return clamp(v, log(0.02), log(0.35))
        }

        let wake = getWakeHour(settings.sleepMidpoint)
        let sleepStart = getSleepStartHour(settings.sleepMidpoint)

        let raw = (0..<48).map { i -> (Int, Double, Double, Bool, Bool) in
            let hr = Double(i) * 0.5
            let logCv = evalLogCv(hr)
            let inWork = isInWindow(hr, start: settings.workStart, end: settings.workEnd)
            let isSleep = isInWindow(hr, start: sleepStart, end: wake)
            return (i, hr, logCv, inWork, isSleep)
        }

        let active = raw.filter { $0.3 && !$0.4 }
        let pool = active.count >= 4 ? active : raw
        let sorted = pool.map { $0.2 }.sorted()
        let idxPeak = max(0, Int(floor(Double(sorted.count) * 0.30)) - 1)
        let idxLow = min(sorted.count - 1, Int(floor(Double(sorted.count) * 0.72)))
        let tauPeak = sorted[idxPeak]
        let tauLow = max(sorted[idxLow], tauPeak + 1e-6)

        let minLog = raw.map { $0.2 }.min() ?? -3.2
        let maxLog = raw.map { $0.2 }.max() ?? -2.0
        let span = max(0.05, maxLog - minLog)

        let slots: [CurveSlot] = raw.map { (i, hr, logCv, inWork, isSleep) in
            let tier: PrecisionTier = (!inWork || isSleep) ? .rest : classifyTier(tauPeak: tauPeak, tauLow: tauLow, score: logCv)
            let idx = Int(round(clamp((1.0 - (logCv - minLog) / span) * 100.0, 5.0, 99.0)))
            return CurveSlot(
                index: i,
                hour: hr,
                label: formatHour(hr),
                logCv: logCv,
                cv: exp(logCv),
                inWorkday: inWork,
                isSleep: isSleep,
                tier: tier,
                precisionIndex: idx
            )
        }

        // Merge contiguous workday blocks
        var blocks: [ScheduleBlock] = []
        var curTier: PrecisionTier? = nil
        var curStart: Double = 0
        var curSlots: [CurveSlot] = []

        func flushBlock() {
            guard let t = curTier, !curSlots.isEmpty else { return }
            let endH = curSlots.last!.hour + 0.5
            let avgCv = curSlots.map(\.cv).reduce(0, +) / Double(curSlots.count)
            let avgIdx = Int(round(Double(curSlots.map(\.precisionIndex).reduce(0, +)) / Double(curSlots.count)))
            blocks.append(ScheduleBlock(
                tier: t,
                startHour: curStart,
                endHour: endH,
                start: formatHour(curStart),
                end: formatHour(endH),
                predictedCvMean: avgCv,
                precisionIndex: avgIdx
            ))
            curTier = nil
            curSlots = []
        }

        for sl in slots {
            if sl.tier == .rest {
                flushBlock()
                continue
            }
            if curTier != sl.tier {
                flushBlock()
                curTier = sl.tier
                curStart = sl.hour
                curSlots = [sl]
            } else {
                curSlots.append(sl)
            }
        }
        flushBlock()

        let curLogCv = evalLogCv(hourLocal)
        let curCv = exp(curLogCv)
        let curInWork = isInWindow(hourLocal, start: settings.workStart, end: settings.workEnd)
        let curSleep = isInWindow(hourLocal, start: sleepStart, end: wake)
        let curTierState: PrecisionTier = (!curInWork || curSleep) ? .rest : classifyTier(tauPeak: tauPeak, tauLow: tauLow, score: curLogCv)
        let curIdx = Int(round(clamp((1.0 - (curLogCv - minLog) / span) * 100.0, 5.0, 99.0)))
        let curPhaseDeg = Int(round(mod24(hourLocal - settings.sleepMidpoint) * 15.0))

        let peakBlocks = blocks.filter { $0.tier == .peak }
        var nextPeakMins: Int? = nil
        var activeRemMins: Int? = nil
        var nextPeakWin: String? = nil

        if let activePeak = peakBlocks.first(where: { hourLocal >= $0.startHour && hourLocal < $0.endHour }) {
            activeRemMins = max(1, Int(round((activePeak.endHour - hourLocal) * 60.0)))
            nextPeakMins = 0
            nextPeakWin = "\(activePeak.start)–\(activePeak.end)"
        } else if !peakBlocks.isEmpty {
            var bestDelta = Double.infinity
            for b in peakBlocks {
                var d = b.startHour - hourLocal
                if d <= 0 { d += 24.0 }
                if d < bestDelta {
                    bestDelta = d
                    nextPeakWin = "\(b.start)–\(b.end)"
                }
            }
            nextPeakMins = Int(round(bestDelta * 60.0))
        }

        return CognitiveScheduleResult(
            mode: mode,
            modeLabel: modeLabel,
            hourLocal: hourLocal,
            localTime: formatHour(hourLocal),
            currentTier: curTierState,
            currentCv: curCv,
            currentPrecisionIndex: curIdx,
            currentPhaseDeg: curPhaseDeg,
            latestJndMs: sessions.last?.jndMs,
            tauPeak: tauPeak,
            tauLow: tauLow,
            nextPeakInMinutes: nextPeakMins,
            activePeakRemainingMinutes: activeRemMins,
            nextPeakWindow: nextPeakWin,
            slots: slots,
            blocks: blocks,
            fit: fit,
            sleepMidpoint: settings.sleepMidpoint,
            workStart: settings.workStart,
            workEnd: settings.workEnd
        )
    }

    // MARK: - RFC 5545 .ics Calendar Exporter

    private static func escapeIcs(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func foldIcsLine(_ line: String) -> String {
        guard line.count > 74 else { return line }
        var out: [String] = []
        var idx = line.startIndex
        var first = true
        while idx < line.endIndex {
            let step = first ? 74 : 73
            let next = line.index(idx, offsetBy: step, limitedBy: line.endIndex) ?? line.endIndex
            let chunk = String(line[idx..<next])
            out.append(first ? chunk : " " + chunk)
            idx = next
            first = false
        }
        return out.joined(separator: "\r\n")
    }

    public static func generateIcs(
        schedule: CognitiveScheduleResult,
        days: Int = 7,
        includeMorningCheck: Bool = true,
        now: Date = Date()
    ) -> String {
        let cal = Calendar.current
        let utcFmt = DateFormatter()
        utcFmt.timeZone = TimeZone(secondsFromGMT: 0)
        utcFmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let stamp = utcFmt.string(from: now)

        func localStamp(y: Int, m: Int, d: Int, hourFloat: Double) -> String {
            let h = Int(floor(hourFloat))
            let min = Int(round((hourFloat - Double(h)) * 60.0))
            return String(format: "%04d%02d%02dT%02d%02d00", y, m, d, h, min)
        }

        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Graviton Research Foundation//ChronoScope Companion//EN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
            "X-WR-CALNAME:Graviton Cognitive Precision Schedule",
            "X-WR-CALDESC:\(escapeIcs("Personal circadian timing schedule (\(schedule.modeLabel)). \(epistemicBoundary)"))"
        ]

        let wake = getWakeHour(schedule.sleepMidpoint)
        let checkHour = clamp(round((wake + 0.5) * 2.0) / 2.0, 5.0, 11.5)
        let startDay = cal.startOfDay(for: now)

        for offset in 0..<max(1, min(28, days)) {
            guard let dayDate = cal.date(byAdding: .day, value: offset, to: startDay) else { continue }
            let dc = cal.dateComponents([.year, .month, .day], from: dayDate)
            let y = dc.year ?? 2026, m = dc.month ?? 1, d = dc.day ?? 1
            let tag = String(format: "%04d%02d%02d", y, m, d)

            if includeMorningCheck {
                lines.append(contentsOf: [
                    "BEGIN:VEVENT",
                    "UID:graviton-check-\(tag)@gravitonresearch.org",
                    "DTSTAMP:\(stamp)",
                    "DTSTART:\(localStamp(y: y, m: m, d: d, hourFloat: checkHour))",
                    "DTEND:\(localStamp(y: y, m: m, d: d, hourFloat: checkHour + 0.25))",
                    "SUMMARY:\(escapeIcs("[Graviton Check] 60s ChronoScope Calibration (AirPods Ready)"))",
                    "DESCRIPTION:\(escapeIcs("Run a 60-second AirPods or Watch timing check to recalibrate today's precision curve."))",
                    "TRANSP:TRANSPARENT",
                    "END:VEVENT"
                ])
            }

            for (idx, b) in schedule.blocks.enumerated() where b.tier == .peak || b.tier == .lowReliability {
                let isPeak = b.tier == .peak
                let summary = isPeak
                    ? String(format: "[Graviton Peak] High-Precision Deep Work (CV ~%.3f)", b.predictedCvMean)
                    : String(format: "[Graviton Routine] Low-Reliability / Admin Window (CV ~%.3f)", b.predictedCvMean)
                let desc = isPeak
                    ? "Protected Peak Precision Window (\(b.start)–\(b.end), Precision \(b.precisionIndex)/100). Model: \(schedule.modeLabel). \(epistemicBoundary)"
                    : "Lower timing-reliability window (\(b.start)–\(b.end), Precision \(b.precisionIndex)/100). Route admin/email here. \(epistemicBoundary)"

                lines.append(contentsOf: [
                    "BEGIN:VEVENT",
                    "UID:graviton-\(b.tier.rawValue)-\(tag)-\(idx)@gravitonresearch.org",
                    "DTSTAMP:\(stamp)",
                    "DTSTART:\(localStamp(y: y, m: m, d: d, hourFloat: b.startHour))",
                    "DTEND:\(localStamp(y: y, m: m, d: d, hourFloat: b.endHour))",
                    "SUMMARY:\(escapeIcs(summary))",
                    "DESCRIPTION:\(escapeIcs(desc))",
                    "TRANSP:\(isPeak ? "OPAQUE" : "TRANSPARENT")"
                ])
                if isPeak {
                    lines.append(contentsOf: [
                        "BEGIN:VALARM",
                        "ACTION:DISPLAY",
                        "TRIGGER:-PT10M",
                        "DESCRIPTION:\(escapeIcs(summary))",
                        "END:VALARM"
                    ])
                }
                lines.append("END:VEVENT")
            }
        }

        lines.append("END:VCALENDAR")
        return lines.map(foldIcsLine).joined(separator: "\r\n") + "\r\n"
    }
}
