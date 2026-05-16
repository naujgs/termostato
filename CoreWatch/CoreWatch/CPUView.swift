import SwiftUI

struct CPUView: View {

    var metrics: MetricsViewModel

    var body: some View {
        ZStack {
            Color.tmBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: TMSpacing.s4) {
                Text(LocalizedStringKey("tab.cpu"))
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(Color.tmFg1)
                    .padding(.horizontal, TMSpacing.s5)
                    .padding(.top, TMSpacing.s4)

                MetricCardView(
                    label: "metric.app_cpu",
                    value: metrics.appCPUPercent > 0
                        ? String(format: "%.1f%%", metrics.appCPUPercent)
                        : "—",
                    tooltip: "tooltip.app_cpu"
                )

                MetricCardView(
                    label: "metric.sys_cpu",
                    value: metrics.sysCPUPercent > 0
                        ? String(format: "%.1f%%", metrics.sysCPUPercent)
                        : "—",
                    tooltip: "tooltip.sys_cpu"
                )

                Spacer()
            }
        }
    }
}

// MARK: - MetricCardView
// Shared by CPUView and MemoryView. Uses design tokens.
struct MetricCardView: View {
    let label: LocalizedStringKey
    let value: String
    var tooltip: LocalizedStringKey? = nil

    @State private var showTooltip = false

    var body: some View {
        RoundedRectangle(cornerRadius: TMRadius.panel, style: .continuous)
            .fill(Color.tmSurface1)
            .overlay(alignment: .topTrailing) {
                if tooltip != nil {
                    Button {
                        showTooltip = true
                    } label: {
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
                    Text(value)
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.tmFg1)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, TMSpacing.s5)
            .frame(minHeight: 100)
    }
}
