import SwiftUI
import ChronoScopeCore

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct DashboardView: View {
    @Bindable var store: ChronoScopeProfileStore
    let onStartCheck: () -> Void

    @State private var statusBanner: String?
    @State private var syncingHealth = false

    #if canImport(HealthKit)
    private let healthBridge = HealthKitCircadianBridge()
    #endif

    var body: some View {
        let s = store.schedule
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GRAVITON RESEARCH FOUNDATION · CHRONOSCOPE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ObservatoryPalette.gold)
                        Text("Cognitive Precision Schedule")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(ObservatoryPalette.ink)
                    }
                    Spacer()
                    Button(action: onStartCheck) {
                        Label("60s AirPods Check", systemImage: "airpodspro")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ObservatoryPalette.gold)
                    .foregroundStyle(.black)
                }

                // Live Cognitive State Card
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(s.currentTier.label.uppercased())
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(ObservatoryPalette.color(for: s.currentTier).opacity(0.18), in: Capsule())
                            .foregroundStyle(ObservatoryPalette.color(for: s.currentTier))

                        Text("LOCAL \(s.localTime) · PHASE φ = \(s.currentPhaseDeg)°")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ObservatoryPalette.muted)
                        Spacer()
                        Text(s.modeLabel.uppercased())
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(ObservatoryPalette.cyan)
                    }

                    HStack(spacing: 12) {
                        kpiBox("PREDICTED CV", String(format: "%.4f", s.currentCv))
                        kpiBox("PRECISION INDEX", "\(s.currentPrecisionIndex) / 100")
                        kpiBox("PEAK WINDOW", peakTimingSummary(s))
                        kpiBox("LATEST JND", s.latestJndMs.map { String(format: "%.1f ms", $0) } ?? "—")
                    }
                }
                .padding(18)
                .background(ObservatoryPalette.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(ObservatoryPalette.color(for: s.currentTier).opacity(0.45), lineWidth: 1)
                )

                // 24-Hour Precision Curve Canvas
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("24-HOUR PRECISION CURVE")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ObservatoryPalette.muted)
                        Spacer()
                        HStack(spacing: 12) {
                            legendDot("Peak", ObservatoryPalette.emerald)
                            legendDot("Steady", ObservatoryPalette.cyan)
                            legendDot("Routine", ObservatoryPalette.amber)
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ObservatoryPalette.muted)
                    }

                    PrecisionCurveChart(schedule: s, sessions: store.profile.sessions)
                        .frame(height: 190)
                }
                .padding(18)
                .background(ObservatoryPalette.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))

                // Windows + Controls
                HStack(alignment: .top, spacing: 16) {
                    // Today's classified blocks
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TODAY'S CLASSIFIED WINDOWS")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ObservatoryPalette.muted)

                        ForEach(s.blocks) { block in
                            HStack {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(ObservatoryPalette.color(for: block.tier))
                                    .frame(width: 4, height: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(block.start)–\(block.end)")
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(ObservatoryPalette.ink)
                                    Text(block.tier.label)
                                        .font(.system(size: 11))
                                        .foregroundStyle(ObservatoryPalette.muted)
                                }
                                Spacer()
                                Text(String(format: "CV %.3f · %d/100", block.predictedCvMean, block.precisionIndex))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(ObservatoryPalette.softInk)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(ObservatoryPalette.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))

                    // Circadian Controls, HealthKit & Exports
                    VStack(alignment: .leading, spacing: 12) {
                        Text("CIRCADIAN PARAMETERS & INTEGRATIONS")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ObservatoryPalette.muted)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Habitual Sleep Midpoint")
                                Spacer()
                                Text(CognitiveEngine.formatHour(store.profile.settings.sleepMidpoint))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(ObservatoryPalette.gold)
                            }
                            Slider(value: $store.profile.settings.sleepMidpoint, in: 0...8, step: 0.5) { _ in
                                store.save()
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Schedule Shift / Jet Lag (1 − R_φ)")
                                Spacer()
                                Text(String(format: "%.1f h", store.profile.settings.shiftHours))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(ObservatoryPalette.gold)
                            }
                            Slider(value: $store.profile.settings.shiftHours, in: 0...6, step: 0.5) { _ in
                                store.save()
                            }
                        }

                        Divider()

                        HStack(spacing: 10) {
                            Button {
                                do {
                                    let url = try store.exportIcsFile(days: 7)
                                    #if os(macOS)
                                    NSWorkspace.shared.open(url)
                                    #endif
                                    statusBanner = "Opened 7-day .ics schedule in Calendar."
                                } catch {
                                    statusBanner = "Export error: \(error.localizedDescription)"
                                }
                            } label: {
                                Label("Export .ics to Calendar", systemImage: "calendar.badge.plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ObservatoryPalette.emerald)
                            .foregroundStyle(.black)

                            Button {
                                copyToClipboard(store.liveApiURL(format: "json").absoluteString)
                                statusBanner = "Copied live /api/cognitive-state/ URL."
                            } label: {
                                Label("Copy Live API URL", systemImage: "link")
                            }
                            .buttonStyle(.bordered)
                        }

                        #if canImport(HealthKit)
                        if healthBridge.isAvailable {
                            Button {
                                Task {
                                    syncingHealth = true
                                    defer { syncingHealth = false }
                                    try? await healthBridge.requestAuthorization()
                                    if let ctx = await healthBridge.syncCircadianContext(days: 7) {
                                        store.applyHealthKitContext(ctx)
                                        statusBanner = "Synced \(ctx.nightsAnalyzed) nights from Apple Watch HealthKit."
                                    } else {
                                        statusBanner = "No recent Apple Watch sleep samples found in HealthKit."
                                    }
                                }
                            } label: {
                                Label(syncingHealth ? "Syncing HealthKit…" : "Sync Apple Watch Sleep & HRV", systemImage: "applewatch.radiowaves.left.and.right")
                            }
                            .buttonStyle(.bordered)
                            .disabled(syncingHealth)
                        }
                        #endif

                        if let msg = statusBanner {
                            Text(msg)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(ObservatoryPalette.emerald)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("MCP SHARED PROFILE")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(ObservatoryPalette.cyan)
                            Text(store.storageURL.path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(ObservatoryPalette.muted)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(ObservatoryPalette.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }

                // Epistemic Boundary footer
                Text("EPISTEMIC BOUNDARY: \(CognitiveEngine.epistemicBoundary)")
                    .font(.system(size: 11))
                    .foregroundStyle(ObservatoryPalette.amber.opacity(0.9))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ObservatoryPalette.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(22)
        }
        .background(ObservatoryPalette.bg)
    }

    private func kpiBox(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(ObservatoryPalette.muted)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(ObservatoryPalette.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }

    private func legendDot(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
    }

    private func peakTimingSummary(_ s: CognitiveScheduleResult) -> String {
        if let rem = s.activePeakRemainingMinutes {
            return "\(CognitiveEngine.formatDurationMinutes(rem)) left"
        }
        if let next = s.nextPeakInMinutes {
            return "in \(CognitiveEngine.formatDurationMinutes(next))"
        }
        return "—"
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}

struct PrecisionCurveChart: View {
    let schedule: CognitiveScheduleResult
    let sessions: [TimingSession]

    var body: some View {
        Canvas { ctx, size in
            let padL: CGFloat = 10, padR: CGFloat = 10, padT: CGFloat = 14, padB: CGFloat = 24
            let pw = size.width - padL - padR
            let ph = size.height - padT - padB
            let slotW = pw / 48.0

            func toX(_ hour: Double) -> CGFloat { padL + CGFloat(hour / 24.0) * pw }
            func toY(_ cv: Double) -> CGFloat {
                let norm = max(0.0, min(1.0, (cv - 0.03) / 0.14))
                return padT + CGFloat(norm) * ph
            }

            // Tier bands
            for sl in schedule.slots {
                let rect = CGRect(x: toX(sl.hour), y: padT, width: slotW + 0.5, height: ph)
                let fill: Color
                switch sl.tier {
                case .peak: fill = ObservatoryPalette.emerald.opacity(0.16)
                case .moderate: fill = ObservatoryPalette.cyan.opacity(0.07)
                case .lowReliability: fill = ObservatoryPalette.amber.opacity(0.14)
                case .rest: fill = Color.gray.opacity(0.08)
                }
                ctx.fill(Path(rect), with: .color(fill))
            }

            // Precision curve path
            var path = Path()
            for (i, sl) in schedule.slots.enumerated() {
                let pt = CGPoint(x: toX(sl.hour + 0.25), y: toY(sl.cv))
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            ctx.stroke(path, with: .color(ObservatoryPalette.cyan), lineWidth: 2.4)

            // Logged sessions
            for s in sessions {
                let p = CGPoint(x: toX(s.hourLocal), y: toY(s.cvTiming))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(ObservatoryPalette.ink))
            }

            // NOW vertical line
            let nx = toX(schedule.hourLocal)
            let ny = toY(schedule.currentCv)
            var nowLine = Path()
            nowLine.move(to: CGPoint(x: nx, y: padT))
            nowLine.addLine(to: CGPoint(x: nx, y: padT + ph))
            ctx.stroke(nowLine, with: .color(ObservatoryPalette.gold), lineWidth: 1.6)
            ctx.fill(Path(ellipseIn: CGRect(x: nx - 5.5, y: ny - 5.5, width: 11, height: 11)), with: .color(ObservatoryPalette.gold))

            // Hour labels
            for hr in stride(from: 0, through: 24, by: 4) {
                let label = Text(String(format: "%02d:00", hr % 24))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ObservatoryPalette.muted)
                ctx.draw(label, at: CGPoint(x: toX(Double(hr)), y: size.height - 9))
            }
        }
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}
