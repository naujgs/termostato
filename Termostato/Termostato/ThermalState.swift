//
//  ThermalState.swift
//  Termostato
//

import Foundation
import SwiftUI

/// The four states Termostato displays. Mirrors ProcessInfo.ThermalState.
/// Do NOT localize label strings — they are proper nouns matching ProcessInfo terminology.
enum ThermalLevel: String, CaseIterable, Identifiable, Sendable {
    case nominal, fair, serious, critical
    var id: String { rawValue }

    var label: String {
        switch self {
        case .nominal:  return "Nominal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        }
    }

    var color: Color {
        switch self {
        case .nominal:  return .tmThermalNominal
        case .fair:     return .tmThermalFair
        case .serious:  return .tmThermalSerious
        case .critical: return .tmThermalCritical
        }
    }

    var chartTint: Color {
        switch self {
        case .nominal:  return Color(red: 0.365, green: 0.839, blue: 0.490)
        case .fair:     return Color(red: 1.000, green: 0.839, blue: 0.200)
        case .serious:  return Color(red: 1.000, green: 0.659, blue: 0.200)
        case .critical: return Color(red: 1.000, green: 0.384, blue: 0.349)
        }
    }

    var hasGlow: Bool { self == .critical }

    init(_ os: ProcessInfo.ThermalState) {
        switch os {
        case .nominal:  self = .nominal
        case .fair:     self = .fair
        case .serious:  self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }
}
