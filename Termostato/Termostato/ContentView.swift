import SwiftUI

struct ContentView: View {

    // D-07: ContentView owns both ViewModels as @State.
    // ThermalView, CPUView, MemoryView receive them as parameters — they do not re-own.
    @State private var vm = TemperatureViewModel()
    @State private var metrics = MetricsViewModel()
    @State private var selectedTab: Int = 0

    // D-06: SwiftUI scenePhase drives lifecycle for both ViewModels.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // D-01: TabView container with three tabs: Thermal, CPU, Memory.
        // D-03: Explicit selectedTab binding so SC5 (tab selection persists within session) is testable.
        TabView(selection: $selectedTab) {
            ThermalView(viewModel: vm)
                .tabItem {
                    Label("Thermal", systemImage: "thermometer.medium")
                }
                .tag(0)
            CPUView(metrics: metrics)
                .tabItem {
                    Label("CPU", systemImage: "cpu")
                }
                .tag(1)
            MemoryView(metrics: metrics)
                .tabItem {
                    Label("Memory", systemImage: "memorychip")
                }
                .tag(2)
        }
        // D-10: Both ViewModels start/stop together on scene transitions.
        // Guard on oldPhase so polling is only restarted on a genuine background→active
        // return, not on every inactive→active transition (e.g. Notification Centre dismiss).
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .active:
                // Only restart polling when returning from background, not from inactive.
                if oldPhase == .background {
                    vm.startPolling()
                    metrics.startPolling()
                }
            case .background:
                vm.stopPolling()
                metrics.stopPolling()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onAppear {
            vm.startPolling()
            metrics.startPolling()
        }
        // D-07: DO NOT add .preferredColorScheme(.dark) — system appearance only.
    }
}

#Preview {
    ContentView()
}
