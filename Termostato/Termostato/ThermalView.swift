import SwiftUI
import Charts
import UIKit

struct ThermalView: View {

    // Received from ContentView — @Observable class passed by value reference (Pitfall 4 mitigation).
    // ContentView owns TemperatureViewModel as @State; ThermalView reads it without re-owning.
    var viewModel: TemperatureViewModel

    // Debug sheet state lives here per D-02 — trigger is the long-press on "Termostato" title.
    @State private var showDebugSheet = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // App title — long press to open Mach API debug sheet (D-02, D-05)
            Text("Termostato")
                .font(.title2)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
                .onLongPressGesture {
                    showDebugSheet = true
                }
                .sensoryFeedback(.impact, trigger: showDebugSheet)

            // MARK: - Thermal State Badge
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

            // MARK: - Permission-denied banner
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

            Spacer().frame(height: 32)

            // MARK: - Session History Step-Chart
            if viewModel.history.isEmpty {
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
                        series: .value("History", "all")
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

                Text("Session history (last 60 min)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            Spacer()
        }
        .sheet(isPresented: $showDebugSheet) {
            MachProbeDebugView()
        }
    }

    // MARK: - Badge helpers (verbatim from ContentView)

    private var badgeColor: Color {
        switch viewModel.thermalState {
        case .nominal:   return .green
        case .fair:      return .yellow
        case .serious:   return .orange
        case .critical:  return .red
        @unknown default: return .green
        }
    }

    private var badgeTextColor: Color {
        switch viewModel.thermalState {
        case .nominal, .fair:      return .primary
        case .serious, .critical:  return .white
        @unknown default:          return .primary
        }
    }

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
