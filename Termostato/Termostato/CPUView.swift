import SwiftUI

struct CPUView: View {

    // Received from ContentView — MetricsViewModel owned at ContentView level (D-07).
    var metrics: MetricsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text("CPU")
                .font(.title2)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            // App CPU card (D-04, CPU-01)
            MetricCardView(
                label: "App CPU",
                value: metrics.appCPUPercent > 0
                    ? String(format: "%.1f%%", metrics.appCPUPercent)
                    : "—"
            )

            // System CPU card (D-04, CPU-02)
            MetricCardView(
                label: "System CPU",
                value: metrics.sysCPUPercent > 0
                    ? String(format: "%.1f%%", metrics.sysCPUPercent)
                    : "—"
            )

            Spacer()
        }
    }
}

// MARK: - MetricCardView
// Reusable card component. Matches thermal badge aesthetic (D-04, D-05):
// RoundedRectangle cornerRadius 20, systemGray6 fill, label above value.
// Shared by CPUView and MemoryView (same Swift module — no duplicate symbol).
struct MetricCardView: View {
    let label: String
    let value: String

    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color(.systemGray6))
            .overlay {
                VStack(spacing: 4) {
                    Text(label)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 100)
    }
}
