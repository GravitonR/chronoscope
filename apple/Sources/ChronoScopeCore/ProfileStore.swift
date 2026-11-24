import Foundation
import Observation

/// Observable store synchronizing the user's circadian profile & calibration sessions
/// directly with `~/.graviton/chronoscope-profile.json` on macOS (instant shared state
/// with the Graviton ChronoScope MCP Server!) and Application Support on iOS/watchOS.
@MainActor
@Observable
public final class ChronoScopeProfileStore {
    public var profile: ChronoScopeProfile
    public var schedule: CognitiveScheduleResult
    public var lastExportMessage: String?

    public let storageURL: URL

    public init(storageURL: URL? = nil) {
        let resolvedURL: URL
        if let custom = storageURL {
            resolvedURL = custom
        } else {
            #if os(macOS)
            resolvedURL = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".graviton", isDirectory: true)
                .appendingPathComponent("chronoscope-profile.json")
            #else
            let appSup = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            resolvedURL = appSup
                .appendingPathComponent("GravitonChronoScope", isDirectory: true)
                .appendingPathComponent("chronoscope-profile.json")
            #endif
        }
        self.storageURL = resolvedURL

        let loaded = Self.readFromDisk(url: resolvedURL) ?? ChronoScopeProfile()
        self.profile = loaded
        self.schedule = CognitiveEngine.computeSchedule(profile: loaded)
    }

    private static func readFromDisk(url: URL) -> ChronoScopeProfile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ChronoScopeProfile.self, from: data)
    }

    public func reloadFromDisk() {
        if let loaded = Self.readFromDisk(url: storageURL) {
            profile = loaded
        }
        recompute()
    }

    public func save() {
        profile.updatedAt = ISO8601DateFormatter().string(from: Date())
        do {
            let dir = storageURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(profile)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            lastExportMessage = "Save error: \(error.localizedDescription)"
        }
        recompute()
    }

    public func recompute(now: Date = Date()) {
        schedule = CognitiveEngine.computeSchedule(profile: profile, now: now)
    }

    public func recordSession(cvTiming: Double, jndMs: Double?, bias: Double, source: String) {
        let now = Date()
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: now)
        let hourLocal = Double(c.hour ?? 10) + Double(c.minute ?? 0) / 60.0
        let awake = CognitiveEngine.hoursAwakeAt(hourLocal, sleepMidpoint: profile.settings.sleepMidpoint)

        let session = TimingSession(
            hourLocal: (hourLocal * 100.0).rounded() / 100.0,
            sleepMidpoint: profile.settings.sleepMidpoint,
            sleepPressureS: max(0.5, (awake * 10.0).rounded() / 10.0),
            alertness: profile.settings.alertness,
            shiftHours: profile.settings.shiftHours,
            cvTiming: (cvTiming * 100000.0).rounded() / 100000.0,
            jndMs: jndMs.map { ($0 * 10.0).rounded() / 10.0 },
            bias: (bias * 1000.0).rounded() / 1000.0,
            source: source,
            synthetic: false
        )
        profile.sessions.append(session)
        save()
    }

    public func applyHealthKitContext(_ ctx: HealthKitCircadianContext) {
        profile.healthkitContext = ctx
        profile.settings.sleepMidpoint = ctx.computedSleepMidpoint
        profile.settings.shiftHours = ctx.computedShiftHours
        save()
    }

    public func clearSessions() {
        profile.sessions.removeAll()
        save()
    }

    public func liveApiURL(format: String = "json") -> URL {
        var comps = URLComponents(string: "https://gravitonresearch.org/api/cognitive-state/")!
        let s = profile.settings
        let tzOffsetMinutes = -(TimeZone.current.secondsFromGMT() / 60)
        var items: [URLQueryItem] = [
            .init(name: "mid", value: String(format: "%.1f", s.sleepMidpoint)),
            .init(name: "shift", value: String(format: "%.1f", s.shiftHours)),
            .init(name: "alert", value: String(s.alertness)),
            .init(name: "work_start", value: String(format: "%.0f", s.workStart)),
            .init(name: "work_end", value: String(format: "%.0f", s.workEnd)),
            .init(name: "tz_offset", value: String(tzOffsetMinutes))
        ]
        if let f = schedule.fit {
            items.append(contentsOf: [
                .init(name: "alpha", value: String(format: "%.4f", f.alpha)),
                .init(name: "bc", value: String(format: "%.4f", f.betaC)),
                .init(name: "bs", value: String(format: "%.4f", f.betaS)),
                .init(name: "gamma", value: String(format: "%.4f", f.gamma)),
                .init(name: "eta", value: String(format: "%.4f", f.eta)),
                .init(name: "kappa", value: String(format: "%.4f", f.kappa))
            ])
        } else if let last = profile.sessions.last {
            items.append(.init(name: "cal_cv", value: String(format: "%.4f", last.cvTiming)))
            items.append(.init(name: "cal_hour", value: String(format: "%.2f", last.hourLocal)))
            if let j = last.jndMs {
                items.append(.init(name: "cal_jnd", value: String(format: "%.1f", j)))
            }
        }
        if format == "ics" {
            items.append(.init(name: "format", value: "ics"))
            items.append(.init(name: "days", value: "7"))
        }
        comps.queryItems = items
        return comps.url!
    }

    @discardableResult
    public func exportIcsFile(days: Int = 7) throws -> URL {
        let ics = CognitiveEngine.generateIcs(
            schedule: schedule,
            days: days,
            includeMorningCheck: profile.settings.includeMorningCheck
        )
        let dir = FileManager.default.temporaryDirectory
        let file = dir.appendingPathComponent("graviton-cognitive-precision-schedule.ics")
        try ics.write(to: file, atomically: true, encoding: .utf8)
        lastExportMessage = "Exported \(days)-day schedule to \(file.lastPathComponent)"
        return file
    }
}
