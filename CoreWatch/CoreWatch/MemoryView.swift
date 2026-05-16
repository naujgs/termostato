import SwiftUI

struct MemoryView: View {

    var metrics: MetricsViewModel

    private let columns = [
        GridItem(.flexible(), spacing: TMSpacing.s3),
        GridItem(.flexible(), spacing: TMSpacing.s3)
    ]

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
                .frame(maxHeight: 100)

                LazyVGrid(columns: columns, spacing: TMSpacing.s3) {
                    MemoryStatCell(
                        label: "metric.memory_free",
                        value: metrics.sysMemoryFreeGB,
                        tooltip: "tooltip.memory_free"
                    )
                    MemoryStatCell(
                        label: "metric.memory_active",
                        value: metrics.sysMemoryActiveGB,
                        tooltip: "tooltip.memory_active"
                    )
                    MemoryStatCell(
                        label: "metric.memory_inactive",
                        value: metrics.sysMemoryInactiveGB,
                        tooltip: "tooltip.memory_inactive"
                    )
                    MemoryStatCell(
                        label: "metric.memory_wired",
                        value: metrics.sysMemoryWiredGB,
                        tooltip: "tooltip.memory_wired"
                    )
                }
                .padding(.horizontal, TMSpacing.s5)

                Spacer()
            }
        }
    }
}

private struct MemoryStatCell: View {
    let label: LocalizedStringKey
    let value: Double
    var tooltip: LocalizedStringKey? = nil

    @State private var showTooltip = false

    var body: some View {
        RoundedRectangle(cornerRadius: TMRadius.panel, style: .continuous)
            .fill(Color.tmSurface1)
            .overlay(alignment: .topTrailing) {
                if tooltip != nil {
                    Button { showTooltip = true } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color.tmFg3)
                    }
                    .padding(TMSpacing.s3)
                    .popover(isPresented: $showTooltip) {
                        if let tooltip {
                            Text(tooltip)
                                .font(.tmFootnote)
                                .padding()
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                }
            }
            .overlay {
                VStack(spacing: TMSpacing.s1) {
                    Text(label)
                        .font(.tmLabelMono)
                        .tracking(0.6)
                        .foregroundStyle(Color.tmFg3)
                    Text(value > 0 ? String(format: "%.2f GB", value) : "—")
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.tmFg1)
                        .monospacedDigit()
                }
            }
            .frame(minHeight: 130)
    }
}
