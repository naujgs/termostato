//
//  DesignTokens.swift
//  Termostato
//
//  Single source of truth for color and typography tokens.
//  Mirrors `colors_and_type.css` 1:1.
//

import SwiftUI

// MARK: - Color tokens

extension Color {

    // ── Thermal scale ──────────────────────────────────────────────────────
    static let tmThermalNominal  = Color(red: 0.204, green: 0.780, blue: 0.349) // #34C759
    static let tmThermalFair     = Color(red: 1.000, green: 0.800, blue: 0.000) // #FFCC00
    static let tmThermalSerious  = Color(red: 1.000, green: 0.584, blue: 0.000) // #FF9500
    static let tmThermalCritical = Color(red: 1.000, green: 0.231, blue: 0.188) // #FF3B30

    // ── Surface ───────────────────────────────────────────────────────────
    static let tmBg        = Color.black
    static let tmSurface1  = Color(red: 0.059, green: 0.059, blue: 0.067)         // #0F0F11
    static let tmSurface2  = Color(red: 0.102, green: 0.102, blue: 0.114)         // #1A1A1D

    // ── Foreground / text ─────────────────────────────────────────────────
    static let tmFg1       = Color.white
    static let tmFg2       = Color.white.opacity(0.72)
    static let tmFg3       = Color.white.opacity(0.48)
    static let tmFg4       = Color.white.opacity(0.28)

    // ── Hairlines ─────────────────────────────────────────────────────────
    static let tmHair       = Color.white.opacity(0.08)
    static let tmHairStrong = Color.white.opacity(0.14)
}

// MARK: - Typography roles

extension Font {
    static let tmWordmark     = Font.system(size: 28, weight: .semibold, design: .default)
    static let tmBadgeLabel   = Font.system(size: 80, weight: .bold, design: .default)
    static let tmLabelMono    = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let tmBody         = Font.system(size: 17, weight: .regular, design: .default)
    static let tmSubhead      = Font.system(size: 15, weight: .medium, design: .default)
    static let tmFootnote     = Font.system(size: 13, weight: .regular, design: .default)
    static let tmMonoCallout  = Font.system(size: 14, weight: .medium, design: .monospaced)
}

// MARK: - Spacing & radii

enum TMSpacing {
    static let s1: CGFloat  = 4
    static let s2: CGFloat  = 8
    static let s3: CGFloat  = 12
    static let s4: CGFloat  = 16
    static let s5: CGFloat  = 20
    static let s6: CGFloat  = 24
    static let s8: CGFloat  = 32
    static let s12: CGFloat = 48
    static let s16: CGFloat = 64
}

enum TMRadius {
    static let card: CGFloat    = 24
    static let panel: CGFloat   = 16
    static let control: CGFloat = 12
    static let chip: CGFloat    = 8
}

// MARK: - Motion

enum TMMotion {
    static let stateChange: Animation = .timingCurve(0.22, 0.61, 0.36, 1, duration: 0.4)
    static let toastEntry: Animation  = .interpolatingSpring(stiffness: 280, damping: 22)
}
