import SwiftUI

struct ContentView: View {

    // D-03: TemperatureViewModel is the real ViewModel — Phase 2 adds chart and history here.
    @State private var viewModel = TemperatureViewModel()

    // D-06: SwiftUI @Environment scenePhase — no UIKit lifecycle hooks.
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Phase 1 placeholder — Phase 2 replaces this with the full dashboard.
        VStack(spacing: 16) {
            Text("Termostato")
                .font(.largeTitle)
            Text("thermalState: \(thermalStateLabel)")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Check Xcode console for IOKit probe result")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        // D-06 + D-07: cancel-and-recreate on every scenePhase transition.
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                viewModel.startPolling()
            case .background:
                viewModel.stopPolling()
            case .inactive:
                break  // Transitional state — do nothing.
            @unknown default:
                break
            }
        }
        .onAppear {
            // Start polling immediately on first appear (scenePhase may already be .active
            // before onChange fires for the first time).
            viewModel.startPolling()
        }
    }

    private var thermalStateLabel: String {
        switch viewModel.thermalState {
        case .nominal:  return "Nominal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

#Preview {
    ContentView()
}
