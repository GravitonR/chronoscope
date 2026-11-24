import SwiftUI
import ChronoScopeCore

struct CheckSessionView: View {
    @Bindable var store: ChronoScopeProfileStore
    let onCompleted: () -> Void

    @State private var audio = AudioPsychophysicsEngine()
    @State private var airPodsKeepAlive = true

    // Part A: 8-trial Two-Pulse JND staircase
    private let jndTotalTrials = 8
    @State private var jndRunning = false
    @State private var jndTrial = 0
    @State private var jndGapMs: Double = 55.0
    @State private var jndCurrentIsTwo = true
    @State private var jndStreakTwo = 0
    @State private var jndLastDir = 0
    @State private var jndReversals: [Double] = []
    @State private var jndTwoGaps: [Double] = []
    @State private var jndWaitingAnswer = false
    @State private var jndEstimatedMs: Double?

    // Part B: 5-trial 1.50s Prospective Duration Reproduction
    private let cvTotalTrials = 5
    @State private var cvPhase: CvPhase = .idle
    @State private var cvTrial = 0
    @State private var cvDurationsMs: [Double] = []
    @State private var cvHoldStart: Date?
    @State private var cvResult: (mean: Double, sd: Double, cv: Double, bias: Double)?

    enum CvPhase { case idle, cue, ready, holding, done }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("60-SECOND CALIBRATION · AIRPODS & NATIVE AVAUDIOENGINE")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ObservatoryPalette.gold)
                        Text("Morning Precision Check")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(ObservatoryPalette.ink)
                    }
                    Spacer()
                    Toggle("AirPods Keep-Alive (-72 dB)", isOn: $airPodsKeepAlive)
                        .toggleStyle(.switch)
                        .font(.system(size: 12, design: .monospaced))
                        .onChange(of: airPodsKeepAlive) { _, newVal in
                            audio.airPodsKeepAliveEnabled = newVal
                        }
                }

                // Step A: Two-Pulse Auditory JND
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("STEP A · TWO-PULSE AUDITORY RESOLUTION (JND)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ObservatoryPalette.cyan)
                        Spacer()
                        Text(jndEstimatedMs.map { String(format: "JND %.1f ms", $0) } ?? "TRIAL \(jndTrial)/\(jndTotalTrials)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ObservatoryPalette.emerald)
                    }

                    Text("Synthesizes 7 ms acoustic clicks directly into a single 48 kHz PCM buffer (20.8 μs sample spacing). Listen with AirPods or speakers and choose 1 or 2 pulses.")
                        .font(.system(size: 12))
                        .foregroundStyle(ObservatoryPalette.softInk)

                    HStack(spacing: 12) {
                        Button(jndRunning ? "Replay Pulse" : "Start 8-Trial Resolution Test") {
                            if jndRunning {
                                playCurrentJnd()
                            } else {
                                startJnd()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ObservatoryPalette.cyan)
                        .foregroundStyle(.black)

                        Button("1 Single Pulse") { answerJnd(saidTwo: false) }
                            .buttonStyle(.bordered)
                            .disabled(!jndWaitingAnswer)

                        Button("2 Distinct Pulses") { answerJnd(saidTwo: true) }
                            .buttonStyle(.bordered)
                            .disabled(!jndWaitingAnswer)
                    }
                }
                .padding(18)
                .background(ObservatoryPalette.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.09), lineWidth: 1))

                // Step B: 1.50s Prospective Duration Reproduction
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("STEP B · PROSPECTIVE TIMING RELIABILITY (CV_timing)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ObservatoryPalette.gold)
                        Spacer()
                        Text(cvResult.map { String(format: "CV %.4f", $0.cv) } ?? "TRIAL \(cvTrial)/\(cvTotalTrials)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(ObservatoryPalette.emerald)
                    }

                    Text("Hear the exact 1.50 s tone, then press and hold the ChronoPad below for what feels like 1.50 s. Saving updates your live schedule and MCP server profile immediately.")
                        .font(.system(size: 12))
                        .foregroundStyle(ObservatoryPalette.softInk)

                    // Interactive Hold Pad
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(padFillColor)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(padBorderColor, lineWidth: 1.5))
                        VStack(spacing: 6) {
                            Text(padTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(ObservatoryPalette.ink)
                            Text("Target T = 1.500 s · \(cvDurationsMs.count)/\(cvTotalTrials) recorded")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(ObservatoryPalette.softInk)
                        }
                    }
                    .frame(height: 118)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if cvPhase == .ready {
                                    cvPhase = .holding
                                    cvHoldStart = Date()
                                }
                            }
                            .onEnded { _ in
                                if cvPhase == .holding, let t0 = cvHoldStart {
                                    finishHold(elapsedMs: Date().timeIntervalSince(t0) * 1000.0)
                                }
                            }
                    )

                    HStack(spacing: 12) {
                        Button(cvPhase == .idle || cvPhase == .done ? "Start 5-Trial Reproduction" : "Running…") {
                            startCv()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ObservatoryPalette.gold)
                        .foregroundStyle(.black)
                        .disabled(cvPhase == .cue || cvPhase == .ready || cvPhase == .holding)

                        Button("Save & Sync to Schedule + MCP") {
                            if let res = cvResult {
                                store.recordSession(
                                    cvTiming: res.cv,
                                    jndMs: jndEstimatedMs,
                                    bias: res.bias,
                                    source: "apple-airpods-check"
                                )
                                onCompleted()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ObservatoryPalette.emerald)
                        .foregroundStyle(.black)
                        .disabled(cvResult == nil)
                    }
                }
                .padding(18)
                .background(ObservatoryPalette.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.09), lineWidth: 1))
            }
            .padding(22)
        }
        .background(ObservatoryPalette.bg)
        .onDisappear { audio.stopSessionAudio() }
    }

    private var padTitle: String {
        switch cvPhase {
        case .idle: return "Press Start below to begin"
        case .cue: return "Listen to 1.50 s reference tone…"
        case .ready: return "Press & HOLD here for 1.50 s"
        case .holding: return "Timing… release at 1.50 s"
        case .done:
            if let r = cvResult {
                return String(format: "Done · CV = %.4f (Bias %.3f×)", r.cv, r.bias)
            }
            return "Completed"
        }
    }

    private var padFillColor: Color {
        switch cvPhase {
        case .cue: return ObservatoryPalette.cyan.opacity(0.18)
        case .holding: return ObservatoryPalette.emerald.opacity(0.24)
        default: return ObservatoryPalette.gold.opacity(0.08)
        }
    }

    private var padBorderColor: Color {
        switch cvPhase {
        case .cue: return ObservatoryPalette.cyan
        case .holding: return ObservatoryPalette.emerald
        default: return ObservatoryPalette.gold.opacity(0.45)
        }
    }

    private func startJnd() {
        audio.airPodsKeepAliveEnabled = airPodsKeepAlive
        jndRunning = true
        jndTrial = 0
        jndGapMs = 55.0
        jndStreakTwo = 0
        jndLastDir = 0
        jndReversals = []
        jndTwoGaps = []
        jndEstimatedMs = nil
        nextJndTrial()
    }

    private func nextJndTrial() {
        if jndTrial >= jndTotalTrials {
            jndRunning = false
            jndWaitingAnswer = false
            audio.stopSessionAudio()
            let tail = jndReversals.count >= 2 ? Array(jndReversals.suffix(4)) : Array(jndTwoGaps.suffix(4))
            let mean = tail.isEmpty ? jndGapMs : tail.reduce(0, +) / Double(tail.count)
            jndEstimatedMs = (mean * 10.0).rounded() / 10.0
            return
        }
        jndTrial += 1
        jndCurrentIsTwo = jndTrial == 1 ? true : Double.random(in: 0...1) > 0.25
        playCurrentJnd()
    }

    private func playCurrentJnd() {
        jndWaitingAnswer = false
        audio.playTwoPulseStimulus(isTwoPulses: jndCurrentIsTwo, gapMs: jndGapMs)
        let waitMs = 240 + Int(jndCurrentIsTwo ? jndGapMs : 0)
        Task {
            try? await Task.sleep(for: .milliseconds(waitMs))
            jndWaitingAnswer = true
        }
    }

    private func answerJnd(saidTwo: Bool) {
        guard jndWaitingAnswer else { return }
        jndWaitingAnswer = false
        let correct = saidTwo == jndCurrentIsTwo
        if jndCurrentIsTwo {
            jndTwoGaps.append(jndGapMs)
            let step = jndGapMs > 30 ? 10.0 : (jndGapMs > 14 ? 4.0 : 2.0)
            if correct {
                jndStreakTwo += 1
                if jndStreakTwo >= 2 {
                    if jndLastDir == 1 { jndReversals.append(jndGapMs) }
                    jndLastDir = -1
                    jndGapMs = max(4.0, jndGapMs - step)
                    jndStreakTwo = 0
                }
            } else {
                if jndLastDir == -1 { jndReversals.append(jndGapMs) }
                jndLastDir = 1
                jndGapMs = min(110.0, jndGapMs + step)
                jndStreakTwo = 0
            }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            nextJndTrial()
        }
    }

    private func startCv() {
        audio.airPodsKeepAliveEnabled = airPodsKeepAlive
        cvTrial = 0
        cvDurationsMs = []
        cvResult = nil
        runCvCue()
    }

    private func runCvCue() {
        if cvTrial >= cvTotalTrials {
            cvPhase = .done
            audio.stopSessionAudio()
            cvResult = CognitiveEngine.computeCvStats(durationsMs: cvDurationsMs)
            return
        }
        cvTrial += 1
        cvPhase = .cue
        audio.playReferenceTone(durationMs: CognitiveEngine.targetDurationMs)
        Task {
            try? await Task.sleep(for: .milliseconds(1620))
            if cvPhase == .cue { cvPhase = .ready }
        }
    }

    private func finishHold(elapsedMs: Double) {
        guard elapsedMs >= 250 else {
            cvPhase = .ready
            return
        }
        cvDurationsMs.append(elapsedMs)
        cvPhase = .cue
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            runCvCue()
        }
    }
}
