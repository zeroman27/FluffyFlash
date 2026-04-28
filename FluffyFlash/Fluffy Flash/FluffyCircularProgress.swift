//
//  FluffyCircularProgress.swift
//  Fluffy Flash
//
//  Thick fluffy circular progress used across Running/Done states.
//

import SwiftUI

struct FluffyCircularProgress: View {
    var value: Double?
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            if let value {
                Circle()
                    .trim(from: 0, to: min(1, max(0, value)))
                    .stroke(
                        LinearGradient(
                            colors: [FluffyColor.orange, FluffyColor.orangeHi],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: FluffyColor.orangeHi.opacity(0.35), radius: 12, y: 4)
                    .animation(.easeInOut(duration: 0.28), value: value)
            } else {
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [FluffyColor.orange.opacity(0.35), FluffyColor.orangeHi.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [10, 12])
                    )
                    .rotationEffect(.degrees(-90))
                    .opacity(0.85)
            }
            Circle()
                .fill(Color.white.opacity(0.03))
                .blur(radius: 0.2)
        }
    }
}

