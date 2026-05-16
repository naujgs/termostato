import SwiftUI

struct MemoryView: View {

    var metrics: MetricsViewModel

    var body: some View {
        ZStack {
            Color.tmBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: TMSpacing.s4) {
                Text(LocalizedStringKey("tab.memory"))
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.tmFg1)
                    .padding(.horizontal, TMSpacing.s5)
                    .padding(.top, TMSpacing.s4)

                MetricCardView(
                    label: "metric.app_memory",
                    value: metrics.appMemoryMB > 0
                        ? "\(metrics.appMemoryMB) MB"
                        : "—",
                    tooltip: "tooltip.app_memory"
                )

                MetricCardView(
                    label: "metric.memory_free",
                    value: metrics.sysMemoryFreeGB > 0
                        ? String(format: "%.1f GB", metrics.sysMemoryFreeGB)
                        : "—",
                    tooltip: "tooltip.memory_free"
                )

                MetricCardView(
                    label: "metric.memory_used",
                    value: metrics.sysMemoryUsedGB > 0
                        ? String(format: "%.1f GB", metrics.sysMemoryUsedGB)
                        : "—",
                    tooltip: "tooltip.memory_used"
                )

                Spacer()
            }
        }
    }
}
