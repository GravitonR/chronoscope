import SwiftUI
import ChronoScopeCore

#if os(macOS)
import AppKit

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif

@main
struct GravitonChronoScopeApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif
    @State private var store = ChronoScopeProfileStore()
    @State private var selectedTab: AppTab = .dashboard

    enum AppTab: Hashable {
        case dashboard
        case check
    }

    var body: some Scene {
        WindowGroup("Graviton ChronoScope") {
            RootContentView(store: store, selectedTab: $selectedTab)
                .preferredColorScheme(.dark)
                #if os(macOS)
                .frame(minWidth: 860, minHeight: 680)
                #endif
        }

        #if os(macOS)
        MenuBarExtra {
            MenuBarContentView(store: store) {
                selectedTab = .check
                NSApp.activate(ignoringOtherApps: true)
            }
        } label: {
            let tier = store.schedule.currentTier
            Label("\(tier.shortLabel) \(store.schedule.currentPrecisionIndex)", systemImage: menuBarSymbol(for: tier))
        }
        .menuBarExtraStyle(.window)
        #endif
    }

    private func menuBarSymbol(for tier: PrecisionTier) -> String {
        switch tier {
        case .peak: return "sparkles"
        case .moderate: return "waveform.path.ecg"
        case .lowReliability: return "clock.arrow.circlepath"
        case .rest: return "moon.stars"
        }
    }
}

struct RootContentView: View {
    @Bindable var store: ChronoScopeProfileStore
    @Binding var selectedTab: GravitonChronoScopeApp.AppTab

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                DashboardView(store: store, onStartCheck: { selectedTab = .check })
                    .tabItem {
                        Label("Precision Schedule", systemImage: "waveform.path.ecg")
                    }
                    .tag(GravitonChronoScopeApp.AppTab.dashboard)

                CheckSessionView(store: store, onCompleted: { selectedTab = .dashboard })
                    .tabItem {
                        Label("60s AirPods Check", systemImage: "airpodspro")
                    }
                    .tag(GravitonChronoScopeApp.AppTab.check)
            }
            .tint(ObservatoryPalette.gold)
        }
        .background(ObservatoryPalette.bg)
    }
}

#if os(macOS)
struct MenuBarContentView: View {
    @Bindable var store: ChronoScopeProfileStore
    let onOpenCheck: () -> Void

    var body: some View {
        let s = store.schedule
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GRAVITON CHRONOSCOPE")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ObservatoryPalette.muted)
                    Text(s.currentTier.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ObservatoryPalette.color(for: s.currentTier))
                }
                Spacer()
                Text("\(s.currentPrecisionIndex)/100")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(ObservatoryPalette.ink)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PREDICTED CV")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(ObservatoryPalette.muted)
                    Text(String(format: "%.4f", s.currentCv))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT PEAK")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(ObservatoryPalette.muted)
                    Text(s.nextPeakWindow ?? "Tomorrow")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ObservatoryPalette.emerald)
                }
            }
            .padding(10)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            if let rec = s.currentTier.recommendedTasks.first {
                Text("Best now: \(rec)")
                    .font(.system(size: 11))
                    .foregroundStyle(ObservatoryPalette.softInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Run 60s AirPods Calibration…", action: onOpenCheck)
                .buttonStyle(.borderedProminent)
                .tint(ObservatoryPalette.gold)
                .frame(maxWidth: .infinity)

            HStack {
                Button("Open .ics in Calendar") {
                    if let url = try? store.exportIcsFile(days: 7) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)

                Button("Refresh") {
                    store.reloadFromDisk()
                }
                .buttonStyle(.bordered)
            }

            Text("MCP sync: ~/.graviton/chronoscope-profile.json")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(ObservatoryPalette.muted)
        }
        .padding(14)
        .frame(width: 290)
        .background(ObservatoryPalette.bg)
    }
}
#endif

enum ObservatoryPalette {
    static let bg = Color(red: 0.020, green: 0.027, blue: 0.047)
    static let card = Color(red: 0.051, green: 0.071, blue: 0.114)
    static let ink = Color(red: 0.949, green: 0.937, blue: 0.914)
    static let softInk = Color(red: 0.78, green: 0.82, blue: 0.88)
    static let muted = Color(red: 0.48, green: 0.52, blue: 0.60)
    static let gold = Color(red: 0.886, green: 0.722, blue: 0.420)
    static let cyan = Color(red: 0.404, green: 0.831, blue: 0.910)
    static let emerald = Color(red: 0.322, green: 0.839, blue: 0.600)
    static let amber = Color(red: 0.941, green: 0.639, blue: 0.369)

    static func color(for tier: PrecisionTier) -> Color {
        switch tier {
        case .peak: return emerald
        case .moderate: return cyan
        case .lowReliability: return amber
        case .rest: return muted
        }
    }
}
