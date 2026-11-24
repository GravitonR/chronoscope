# Graviton ChronoScope — Apple Companion + AI / MCP Scheduling Integration

Turns Graviton Research Foundation's **Circadian Gating of Temporal Integration** timing instrument into:
1. A native **macOS / iOS / Apple Watch companion** (Swift 6 + SwiftUI + `AVAudioEngine` AirPods keep-alive + HealthKit sleep/HRV bridge), and
2. A zero-dependency **Model Context Protocol (MCP) server** (`chronoscope-mcp`) so AI assistants and calendar schedulers can read your live biological precision curve in real time.

Both share the same local profile file on macOS: `~/.graviton/chronoscope-profile.json` — so finishing a **60-second AirPods morning check** in the macOS app immediately updates your Menu Bar badge, Apple Calendar `.ics` schedule, AND every connected AI assistant via MCP.

---

## 1. Run the Native macOS Companion App (Works Now)

Put on your **AirPods** (or use speakers) and run:

```bash
cd /Users/ih/.gemini/antigravity/scratch/chronoscope-companion/apple
swift run ChronoScopeMac
```

What you get immediately:
- **Live macOS Menu Bar indicator** (`PEAK 97`, `STEADY 81`, `ROUTINE 66`)
- **60-Second AirPods Check** using native `AVAudioEngine` 48 kHz PCM synthesis + `-72 dB` Bluetooth keep-alive carrier (zero DAC fade-in clipping)
- **One-click Export to Apple Calendar (`.ics`)**
- **Instant local sync** to `~/.graviton/chronoscope-profile.json`

Run the Swift unit tests (verifying Lean 4 `CT-01` scale invariance, `CT-04` tier ordering, and RFC 5545 `.ics` export):

```bash
cd /Users/ih/.gemini/antigravity/scratch/chronoscope-companion/apple
swift test
```

---

## 2. Connect the MCP Server to Your AI Assistants

Test the MCP server end-to-end:

```bash
cd /Users/ih/.gemini/antigravity/scratch/chronoscope-companion/mcp-server
npm test
```

Add this block to your MCP client configuration (**Claude Desktop**, **Cursor**, **Antigravity**, or **Windsurf**):

```json
{
  "mcpServers": {
    "graviton-chronoscope": {
      "command": "node",
      "args": [
        "/Users/ih/.gemini/antigravity/scratch/chronoscope-companion/mcp-server/server.js"
      ]
    }
  }
}
```

### Exposed MCP Tools
- `get_cognitive_state` — Live tier (`peak | moderate | low_reliability`), predicted `CV_timing`, Precision Index (`0–100`), latest AirPods JND (ms), next peak countdown, and recommended/deferred task guidance.
- `get_precision_schedule` — Full 24-hour Peak / Moderate / Routine windows + subscribable `.ics` URL.
- `evaluate_task_slot` — Score & rank candidate calendar slots for `deep_work`, `decision`, `meetings`, or `routine`.
- `schedule_tasks_to_curve` — Auto-place a task list (with `high | medium | low` cognitive load) onto your curve around existing busy blocks.
- `export_ics_schedule` — Write a 1–28 day RFC 5545 `.ics` schedule to disk.
- `log_calibration_check` — Save a calibration check straight into `~/.graviton/chronoscope-profile.json`.

### Exposed MCP Resources & Prompts
- Resource `chronoscope://state/current` (`application/json`)
- Resource `chronoscope://schedule/today.ics` (`text/calendar`)
- Prompt `plan_my_day_by_precision`

---

## 3. Deploy to iPhone & Apple Watch (iOS 17+ / watchOS 10+)

All iOS & watchOS source code is included and shared with `ChronoScopeCore`:
- `apple/Sources/ChronoScopeCore/HealthKitBridge.swift` — Reads 7-night Apple Watch `sleepAnalysis`, overnight HRV (`SDNN`), and sleeping wrist temperature to automatically derive `sleep_midpoint` and recent schedule shift (`1 - R_φ` proxy).
- `apple/Sources/ChronoScopeApp/` — Runs cleanly on both macOS and iOS.
- `apple/Sources/ChronoScopeWatch/ChronoScopeWatchApp.swift` — Native watchOS companion with a live precision ring and an eyes-free **5-trial haptic `1.50 s` timing check** (`WKHapticType`).

To deploy onto your physical iPhone & Apple Watch:
1. Open Xcode → **File → New → Project → App (Multiplatform / iOS + Watch App)**, or open `apple/Package.swift` directly in Xcode (`open apple/Package.swift`).
2. Add the **ChronoScopeCore** local Swift package to your iOS and watchOS App targets and enable the **HealthKit** capability (`NSHealthShareUsageDescription`).
3. Select your iPhone / Apple Watch and press **⌘R**.

---

## Epistemic Boundary
ChronoScope measures behavioral auditory temporal discrimination (`JND`) and prospective duration reproduction (`CV_timing`). Schedule tiers are behavioral circadian-timing estimates—**not** medical advice, clinical sleep scoring, or direct neural measurement.
