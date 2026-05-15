//
//  SessionChartView.swift
//  Termostato
//

import SwiftUI
import Charts

struct Sample: Identifiable, Sendable {
    let id: Int
    let timestamp: Date
    let level: ThermalLevel

    var levelIndex: Int {
        switch level {
        case .nominal:  return 0
        case .fair:     return 1
        case .serious:  return 2
        case .critical: return 3
        }
    }
}

struct SessionChartView: View {
    let samples: [Sample]

    private var peakLevel: ThermalLevel {
        samples.map(\.level).max(by: { lhs, rhs in
            ThermalLevel.allCases.firstIndex(of: lhs)! < ThermalLevel.allCases.firstIndex(of: rhs)!
        }) ?? .nominal
    }

    var body: some View {
        Chart(samples) { s in
            LineMark(
                x: .value("t", s.id),
                y: .value("level", s.levelIndex)
            )
            .interpolationMethod(.stepEnd)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .foregroundStyle(peakLevel.chartTint)
        }
        .chartYScale(domain: 0...3)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 1, 2, 3]) { value in
                AxisGridLine().foregroundStyle(Color.tmHair)
                AxisValueLabel {
                    if let i = value.as(Int.self) {
                        Text(ThermalLevel.allCases[i].label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.tmFg3)
                    }
                }
            }
        }
        .chartXAxis(.hidden)
        .chartPlotStyle { content in
            content.padding(.trailing, 60)
        }
    }
}
