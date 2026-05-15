import SwiftUI
import Charts
import UIKit

struct ContentView: View {

    // D-03: TemperatureViewModel is the real ViewModel.
    @State private var viewModel = TemperatureViewModel()

    // D-06: SwiftUI @Environment scenePhase — no UIKit lifecycle hooks.
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    // Phase 6 debug sheet — triggered by long-pressing the app title (D-05)
    @State private var showDebugSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // App title — long press to open Mach API debug sheet (D-05)
            Text("Termostato")
                .font(.title2)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .onLongPressGesture {
                    showDebugSheet = true
                }
                .sensoryFeedback(.impact, trigger: showDebugSheet)

            // MARK: - Thermal State Badge (D-01)
            RoundedRectangle(cornerRadius: 20)
                .fill(badgeColor)
                .overlay {
                    Text(thermalStateLabel)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(badgeTextColor)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 100)

            // MARK: - Permission-denied banner (D-11, D-12, D-13)
            // Shown when notification permission is denied. Persists until permission is granted.
            // Re-check happens in startPolling() each time the app foregrounds (D-13).
            if !viewModel.notificationsAuthorized {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bell.slash")
                        Text("Notifications disabled — tap to open Settings")
                            .font(.footnote)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
            }

            // xl gap between badge and chart (32pt per UI-SPEC spacing scale)
            Spacer().frame(height: 32)

            // MARK: - Session History Step-Chart (D-02, D-03, D-04)
            if viewModel.history.isEmpty {
                // Empty state (Pattern 5 — safety net for sub-second cold launch)
                VStack(spacing: 8) {
                    Text("Warming up...")
                        .font(.headline)
                    Text("Thermal data will appear here once the first reading arrives.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .padding(.horizontal, 16)
            } else {
                Chart(viewModel.history) { reading in
                    LineMark(
                        x: .value("Time", reading.timestamp),
                        y: .value("Level", reading.yValue),
                        series: .value("History", "all")  // keeps line connected across state changes (Pitfall 2)
                    )
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(by: .value("State", reading.stateName))
                }
                .chartForegroundStyleScale([
                    "Nominal":  Color.green,
                    "Fair":     Color.yellow,
                    "Serious":  Color.orange,
                    "Critical": Color.red
                ])
                .chartYScale(domain: 0...3)
                .chartYAxis {
                    AxisMarks(values: [0, 1, 2, 3]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            switch value.as(Int.self) {
                            case 0: Text("Nominal").font(.caption)
                            case 1: Text("Fair").font(.caption)
                            case 2: Text("Serious").font(.caption)
                            case 3: Text("Critical").font(.caption)
                            default: EmptyView()
                            }
                        }
                    }
                }
                .chartXAxis(.hidden)
                .frame(minHeight: 200)
                .padding(.horizontal, 16)
                .animation(.easeInOut(duration: 0.3), value: viewModel.history.count)

                // Chart sub-label (UI-SPEC copywriting contract)
                Text("Session history (last 60 min)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            Spacer()
        }
        // D-07: DO NOT add .preferredColorScheme(.dark) — system appearance only
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                viewModel.startPolling()
            case .background:
                viewModel.stopPolling()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onAppear {
            viewModel.startPolling()
        }
        .sheet(isPresented: $showDebugSheet) {
            MachProbeDebugView()
        }
    }

    // MARK: - Badge helpers

    /// Badge fill color per thermal state (D-08).
    private var badgeColor: Color {
        switch viewModel.thermalState {
        case .nominal:   return .green
        case .fair:      return .yellow
        case .serious:   return .orange
        case .critical:  return .red
        @unknown default: return .green
        }
    }

    /// Badge text color: dark text on light fills, white on saturated fills (UI-SPEC Color section).
    private var badgeTextColor: Color {
        switch viewModel.thermalState {
        case .nominal, .fair:      return .primary
        case .serious, .critical:  return .white
        @unknown default:          return .primary
        }
    }

    /// Human-readable label for the badge (DISP-01 exact casing from UI-SPEC copywriting contract).
    private var thermalStateLabel: String {
        switch viewModel.thermalState {
        case .nominal:   return "Nominal"
        case .fair:      return "Fair"
        case .serious:   return "Serious"
        case .critical:  return "Critical"
        @unknown default: return "Unknown"
        }
    }
}

#Preview {
    ContentView()
}
