import SwiftUI

struct MemoryView: View {

    // Received from ContentView — MetricsViewModel owned at ContentView level (D-07).
    var metrics: MetricsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text("Memory")
                .font(.title2)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            // App memory card (D-05, MEM-01) — resident_size in MB
            MetricCardView(
                label: "App Memory",
                value: metrics.appMemoryMB > 0
                    ? "\(metrics.appMemoryMB) MB"
                    : "—"
            )

            // System memory — free GB (D-05, MEM-02)
            MetricCardView(
                label: "Memory Free",
                value: metrics.sysMemoryFreeGB > 0
                    ? String(format: "%.1f GB", metrics.sysMemoryFreeGB)
                    : "—"
            )

            // System memory — used GB (D-05, MEM-02)
            MetricCardView(
                label: "Memory Used",
                value: metrics.sysMemoryUsedGB > 0
                    ? String(format: "%.1f GB", metrics.sysMemoryUsedGB)
                    : "—"
            )

            Spacer()
        }
    }
}
