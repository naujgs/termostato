//
//  ThermalBadgeView.swift
//  Termostato
//

import SwiftUI

struct ThermalBadgeView: View {
    let state: ThermalLevel
    var secondary: String? = nil
    var time: String = "—"

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TMRadius.card + 4, style: .continuous)
                .fill(state.color)
                .animation(TMMotion.stateChange, value: state)

            if state.hasGlow {
                RadialGradient(
                    colors: [Color.white.opacity(0.20), .clear],
                    center: UnitPoint(x: 0.5, y: 1.3),
                    startRadius: 0,
                    endRadius: 320
                )
                .allowsHitTesting(false)
                .clipShape(RoundedRectangle(cornerRadius: TMRadius.card + 4, style: .continuous))
            }

            // Top row — LIVE pip + wall clock
            VStack {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.white)
                            .frame(width: 6, height: 6)
                        Text(LocalizedStringKey("label.live"))
                    }
                    Spacer()
                    Text(time)
                        .monospacedDigit()
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.78))
                .padding(.horizontal, TMSpacing.s5)
                .padding(.top, TMSpacing.s5)
                Spacer()
            }

            // Center — state label + optional secondary
            VStack(spacing: TMSpacing.s3) {
                Text(state.label)
                    .font(.tmBadgeLabel)
                    .tracking(-1.6)
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
                    .animation(TMMotion.stateChange, value: state)

                if let secondary {
                    Text(secondary)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .monospacedDigit()
                }
            }
        }
        .aspectRatio(1.0 / 0.88, contentMode: .fit)
    }
}

#Preview("Nominal") {
    ZStack { Color.tmBg.ignoresSafeArea()
        ThermalBadgeView(state: .nominal, time: "21:57").padding(20)
    }
}

#Preview("Critical") {
    ZStack { Color.tmBg.ignoresSafeArea()
        ThermalBadgeView(state: .critical, secondary: "Whoa! Getting spicy.", time: "22:14").padding(20)
    }
}
