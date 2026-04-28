//
//  MistProProgress.swift
//  Wist
//
//  Raycast-style PRO progress: determinate gradient fill + indeterminate shimmer.
//

import SwiftUI

// MARK: - Motion (shared with chrome animations)

enum WistMotion {
    /// Default UI transitions (appear, step change).
    static let normal: Double = 0.32
    static let quick: Double = 0.22
    static let spring = Animation.spring(response: 0.38, dampingFraction: 0.82)
}

// MARK: - Determinate

/// Determinate 0…1 rope progress (same look as `FluffyRopeProgressBar`). `height` maps to compact vs padded vertical layout.
struct MistProProgressBar: View {
    var value: Double
    var label: String?
    var height: CGFloat = 6

    var body: some View {
        FluffyRopeProgressBar(
            value: CGFloat(value),
            label: label,
            compactVertical: height <= 10
        )
    }
}

// MARK: - Indeterminate

/// Shimmer along the track; falls back to a pulsing bar when Reduce Motion is on.
struct MistProProgressIndeterminate: View {
    var height: CGFloat = 6
    var label: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label, !label.isEmpty {
                Text(label)
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
            }
            if reduceMotion {
                ProgressView()
                    .controlSize(.regular)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 60, paused: false)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let phase = t.truncatingRemainder(dividingBy: 1.8) / 1.8
                    GeometryReader { geo in
                        let w = geo.size.width
                        ZStack {
                            Capsule()
                                .fill(Color.white.opacity(0.06))
                                .overlay {
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                                }
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.clear,
                                            Color.accentColor.opacity(0.15),
                                            Color.accentColor.opacity(0.85),
                                            Color.cyan.opacity(0.5),
                                            Color.clear,
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: w * 0.42)
                                .offset(x: -w * 0.2 + CGFloat(phase) * (w * 1.15))
                                .blur(radius: 0.5)
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: height)
                }
            }
        }
        .accessibilityLabel(label ?? String(localized: "In progress"))
    }
}

// MARK: - Unified wrapper (optional convenience)

/// Uses determinate bar when `value` is non-nil, otherwise indeterminate shimmer.
struct MistProProgress: View {
    var value: Double?
    var statusLine: String?

    var body: some View {
        FluffyRopeProgressBar(
            value: value.map { CGFloat($0) },
            label: statusLine,
            compactVertical: true
        )
    }
}
