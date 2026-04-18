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

/// Smooth 0…1 progress track with accent gradient fill (Raycast-like).
struct MistProProgressBar: View {
    var value: Double
    var label: String?
    var height: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: CGFloat {
        CGFloat(min(1, max(0, value)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label, !label.isEmpty {
                Text(label)
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
                    .contentTransition(.interpolate)
                    .animation(.easeInOut(duration: WistMotion.quick), value: label)
            }
            GeometryReader { geo in
                let w = max(0, geo.size.width * clamped)
                ZStack(alignment: .leading) {
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
                                    Color.accentColor,
                                    Color.accentColor.opacity(0.65),
                                    Color.cyan.opacity(0.45),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: w)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 4, y: 0)
                        .animation(reduceMotion ? nil : WistMotion.spring, value: value)
                }
            }
            .frame(height: height)
            .accessibilityLabel(label ?? String(localized: "Progress"))
            .accessibilityValue(String(format: String(localized: "%lld percent"), Int64(Int(clamped * 100))))
        }
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
        Group {
            if let v = value {
                MistProProgressBar(value: v, label: statusLine)
            } else {
                MistProProgressIndeterminate(label: statusLine)
            }
        }
    }
}
