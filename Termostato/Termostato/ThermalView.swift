//
//  ThermalView.swift
//  Termostato
//

import SwiftUI
import Charts
import UIKit

struct ThermalView: View {

    var viewModel: TemperatureViewModel

    @State private var showDebugSheet = false
    @Environment(\.openURL) private var openURL

    private var currentTime: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    private var currentLevel: ThermalLevel {
        ThermalLevel(viewModel.thermalState)
    }

    /// Bridge from TemperatureViewModel's ThermalReading ring buffer to the chart's Sample type.
    private var samples: [Sample] {
        viewModel.history.enumerated().map { i, r in
            Sample(id: i, timestamp: r.timestamp, level: ThermalLevel(r.state))
        }
    }

    var body: some View {
        ZStack {
            Color.tmBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {

                // Header: wordmark + point count
                HStack(alignment: .firstTextBaseline) {
                    Text("Termostato")
                        .font(.system(size: 26, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundStyle(Color.tmFg1)
                        .onLongPressGesture { showDebugSheet = true }
                        .sensoryFeedback(.impact, trigger: showDebugSheet)
                    Spacer()
                    Text("\(viewModel.history.count) \(String(localized: "label.pts", table: "Localizable"))")
                        .font(.tmLabelMono)
                        .tracking(0.6)
                        .monospacedDigit()
                        .foregroundStyle(Color.tmFg3)
                }
                .padding(.horizontal, TMSpacing.s5)
                .padding(.top, TMSpacing.s2)
                .padding(.bottom, TMSpacing.s4)

                // Hero badge
                ThermalBadgeView(state: currentLevel, secondary: nil, time: currentTime)
                    .padding(.horizontal, TMSpacing.s5)

                // Permission-denied banner
                if !viewModel.notificationsAuthorized {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bell.slash")
                            Text(LocalizedStringKey("banner.notifications_disabled"))
                                .font(.tmFootnote)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                        }
                        .foregroundStyle(Color.tmFg3)
                        .padding(.horizontal, TMSpacing.s5)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }

                // Chart section
                if viewModel.history.isEmpty {
                    VStack(spacing: TMSpacing.s2) {
                        Text(LocalizedStringKey("chart.warming_up"))
                            .font(.headline)
                            .foregroundStyle(Color.tmFg2)
                        Text(LocalizedStringKey("chart.empty_hint"))
                            .font(.caption)
                            .foregroundStyle(Color.tmFg3)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .padding(.horizontal, TMSpacing.s5)
                    .padding(.top, TMSpacing.s6)
                } else {
                    // Chart header
                    HStack(alignment: .firstTextBaseline) {
                        Text(LocalizedStringKey("chart.header"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.tmFg2)
                        Spacer()
                        Text(LocalizedStringKey("chart.resolution"))
                            .font(.tmMonoCallout)
                            .monospacedDigit()
                            .foregroundStyle(Color.tmFg4)
                    }
                    .padding(.horizontal, TMSpacing.s5)
                    .padding(.top, TMSpacing.s6)
                    .padding(.bottom, TMSpacing.s2)

                    // Chart — expands to fill remaining screen height
                    SessionChartView(samples: samples)
                        .padding(.horizontal, TMSpacing.s5)
                        .frame(minHeight: 120, maxHeight: .infinity)

                    // Legend
                    HStack(spacing: TMSpacing.s4) {
                        ForEach(ThermalLevel.allCases) { lvl in
                            HStack(spacing: 6) {
                                Circle().fill(lvl.color).frame(width: 7, height: 7)
                                Text(lvl.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.tmFg2)
                            }
                        }
                    }
                    .padding(.horizontal, TMSpacing.s5)
                    .padding(.top, TMSpacing.s3)
                    .padding(.bottom, TMSpacing.s4)
                }
            }
        }
        .sheet(isPresented: $showDebugSheet) {
            MachProbeDebugView()
        }
    }
}
