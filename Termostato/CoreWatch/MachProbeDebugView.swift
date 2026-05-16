import SwiftUI

// MARK: - MachProbeDebugView

/// Debug sheet for Mach API probe validation (Phase 6, throwaway UI per D-04).
/// Triggered by long-pressing the app title in ContentView.
/// Shows per-API verdicts (Accessible / Degraded / Blocked / Pending) with color-coded badges.
struct MachProbeDebugView: View {

    @State private var probe = SystemMetricsProbe()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    // MARK: - Progress Section (visible only while probing)
                    if probe.isProbing {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: Double(probe.samplesCompleted), total: 3.0)
                                .accessibilityLabel("Probe progress: sample \(probe.samplesCompleted) of 3")
                            Text("Sample \(probe.samplesCompleted) of 3")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }

                    // MARK: - Verdict List (4 rows, one per API)
                    VStack(spacing: 8) {
                        ForEach(SystemMetricsProbe.allAPIs, id: \.self) { apiName in
                            VerdictRowView(
                                apiName: apiName,
                                samples: probe.results[apiName] ?? [],
                                finalVerdict: probe.finalVerdicts[apiName]
                            )
                        }
                    }
                    .padding(.horizontal, 16)

                    // MARK: - Run Probe Button
                    Button {
                        probe.runProbeSequence()
                    } label: {
                        if probe.isProbing {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .tint(.white)
                                Text("Probing...")
                            }
                        } else {
                            Text("Run Probe")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(probe.isProbing)
                    .padding(.top, 32)
                    .padding(.bottom, 32)
                }
                .padding(.top, 24)
            }
            .navigationTitle("Mach API Probe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onDisappear {
                probe.cancelProbe()
            }
        }
    }
}

// MARK: - VerdictRowView

/// One row card for a single API probe result.
private struct VerdictRowView: View {

    let apiName: String
    let samples: [MachProbeResult]
    let finalVerdict: APIVerdict?

    private var displayedVerdict: APIVerdict {
        finalVerdict ?? .pending
    }

    private var latestSample: MachProbeResult? {
        samples.last
    }

    private var kernReturnText: String {
        guard let sample = latestSample else { return "---" }
        let label = sample.kernReturn == KERN_SUCCESS ? "KERN_SUCCESS" : "error"
        return "kern_return_t: \(sample.kernReturn) (\(label))"
    }

    private var rawDataText: String {
        latestSample?.rawData ?? "---"
    }

    private var timestampText: String {
        guard let sample = latestSample else { return "---" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: sample.timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: API name (left) + verdict badge (right)
            HStack(alignment: .top) {
                Text(apiName)
                    .font(.headline)
                Spacer()
                VerdictBadgeView(verdict: displayedVerdict, apiName: apiName)
            }

            // kern_return_t line
            Text(kernReturnText)
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))

            // Raw data line
            Text(rawDataText)
                .font(.caption)
                .foregroundStyle(Color(.secondaryLabel))

            // Timestamp (bottom-right)
            HStack {
                Spacer()
                Text(timestampText)
                    .font(.caption)
                    .foregroundStyle(Color(.secondaryLabel))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - VerdictBadgeView

/// Pill-shaped colored badge for API verdict status.
private struct VerdictBadgeView: View {

    let verdict: APIVerdict
    let apiName: String

    private var badgeFill: Color {
        switch verdict {
        case .accessible: return .green
        case .degraded:   return .yellow
        case .blocked:    return .red
        case .pending:    return Color(.tertiarySystemFill)
        }
    }

    private var textColor: Color {
        switch verdict {
        case .accessible, .degraded, .pending: return .primary
        case .blocked:                          return .white
        }
    }

    var body: some View {
        Text(verdict.rawValue)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(badgeFill)
            )
            .accessibilityLabel("\(apiName): \(verdict.rawValue)")
    }
}

#Preview {
    MachProbeDebugView()
}
