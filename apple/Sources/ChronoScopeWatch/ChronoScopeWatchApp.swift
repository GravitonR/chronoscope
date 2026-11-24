#if os(watchOS)
import SwiftUI
import WatchKit
import ChronoScopeCore

@main
struct ChronoScopeWatchApp: App {
    @State private var store = ChronoScopeProfileStore()

    var body: some Scene {
        WindowGroup {
            WatchChronoView(store: store)
        }
    }
}

/// Native Apple Watch companion:
/// 1. Live Cognitive Precision Ring (Peak / Steady / Routine + next peak window)
/// 2. Eyes-free 5-Trial Haptic 1.50 s Timing Reliability Check using WKHapticType cues
/// 3. Direct HealthKit sleep midpoint + HRV sync right on the wrist
struct WatchChronoView: View {
    @Bindable var store: ChronoScopeProfileStore
    @State private var phase: WatchCheckPhase = .idle
    @State private var trial = 0
    @State private var durationsMs: [Double] = []
    @State private var holdStart: Date?
    @State private var lastCv: Double?

    private let totalTrials = 5
    private let healthBridge = HealthKitCircadianBridge()

    enum WatchCheckPhase { case idle, cue, ready, holding, done }

    var body: some View {
        TabView {
            // Page 1: Live Cognitive State Ring
            let s = store.schedule
            VStack(spacing: 8) {
                Text("GRAVITON")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.yellow)

                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.25), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: CGFloat(s.currentPrecisionIndex) / 100.0)
                        .stroke(tierColor(s.currentTier), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text("\(s.currentPrecisionIndex)")
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                        Text(s.currentTier.shortLabel)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(tierColor(s.currentTier))
                    }
                }
                .frame(width: 92, height: 92)

                if let next = s.nextPeakWindow {
                    Text("Peak: \(next)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)

            // Page 2: Haptic 1.50 s Duration Reproduction Check
            VStack(spacing: 8) {
                Text("HAPTIC CHECK \(trial)/\(totalTrials)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.cyan)

                RoundedRectangle(cornerRadius: 12)
                    .fill(phase == .holding ? Color.green.opacity(0.32) : (phase == .cue ? Color.cyan.opacity(0.28) : Color.yellow.opacity(0.16)))
                    .overlay(
                        VStack(spacing: 3) {
                            Text(watchPrompt)
                                .font(.system(size: 13, weight: .semibold))
                                .multilineTextAlignment(.center)
                            if let cv = lastCv {
                                Text(String(format: "CV %.4f", cv))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(6)
                    )
                    .frame(height: 82)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if phase == .ready {
                                    phase = .holding
                                    holdStart = Date()
                                    WKInterfaceDevice.current().play(.click)
                                }
                            }
                            .onEnded { _ in
                                if phase == .holding, let t0 = holdStart {
                                    let ms = Date().timeIntervalSince(t0) * 1000.0
                                    if ms >= 250 {
                                        durationsMs.append(ms)
                                        phase = .cue
                                        Task {
                                            try? await Task.sleep(for: .milliseconds(450))
                                            runCue()
                                        }
                                    } else {
                                        phase = .ready
                                    }
                                }
                            }
                    )

                Button(phase == .idle || phase == .done ? "Start Haptic 1.5s" : "Sync Sleep") {
                    if phase == .idle || phase == .done {
                        trial = 0
                        durationsMs = []
                        lastCv = nil
                        runCue()
                    } else {
                        Task {
                            try? await healthBridge.requestAuthorization()
                            if let ctx = await healthBridge.syncCircadianContext(days: 7) {
                                store.applyHealthKitContext(ctx)
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
            }
            .padding(.horizontal, 4)
        }
        .tabViewStyle(.verticalPage)
    }

    private var watchPrompt: String {
        switch phase {
        case .idle: return "Tap Start below"
        case .cue: return "Feel 1.50 s cue…"
        case .ready: return "Press & HOLD 1.50 s"
        case .holding: return "Release at 1.50 s"
        case .done: return "Saved to Profile ✓"
        }
    }

    private func runCue() {
        if trial >= totalTrials {
            phase = .done
            if let st = CognitiveEngine.computeCvStats(durationsMs: durationsMs) {
                lastCv = st.cv
                store.recordSession(cvTiming: st.cv, jndMs: nil, bias: st.bias, source: "apple-watch-haptic")
                WKInterfaceDevice.current().play(.success)
            }
            return
        }
        trial += 1
        phase = .cue
        WKInterfaceDevice.current().play(.start)
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            WKInterfaceDevice.current().play(.stop)
            try? await Task.sleep(for: .milliseconds(140))
            if phase == .cue { phase = .ready }
        }
    }

    private func tierColor(_ tier: PrecisionTier) -> Color {
        switch tier {
        case .peak: return .green
        case .moderate: return .cyan
        case .lowReliability: return .orange
        case .rest: return .gray
        }
    }
}
#endif
