//
//  FluffyRopeProgressBar.swift
//  Fluffy Flash
//
//  Rope-styled horizontal progress with bundled `FluffyRopeProgressTexture.png`.
//  Use `value: nil` for indeterminate (full rope + shimmer).
//

import AppKit
import SwiftUI

enum FluffyRopeProgressAssets {
    /// PNG in app bundle (`Fluffy Flash/Resources/…`).
    static let textureResourceName = "FluffyRopeProgressTexture"
    /// Slightly larger than the original Lab 15pt fit.
    static let barThickness: CGFloat = 17

    static let bundledRopeImage: NSImage? = {
        if let url = Bundle.main.url(forResource: textureResourceName, withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return NSImage(named: NSImage.Name(textureResourceName))
    }()
}

/// Rope-styled horizontal progress (0…1), or indeterminate when `value == nil`.
struct FluffyRopeProgressBar: View {
    /// Determinate 0…1, or `nil` for indeterminate.
    var value: CGFloat?
    var label: String? = nil
    /// `true` for bottom strip / tight rows; `false` for cards (e.g. step pipeline).
    var compactVertical: Bool = true

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label, !label.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(label)
                        .font(WistFont.caption(10))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let value {
                        Text("\(Int((max(0, min(1, value)) * 100).rounded()))%")
                            .font(WistFont.caption(10).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let value {
                RopeProgressBar(
                    progress: max(0, min(1, value)),
                    thickness: FluffyRopeProgressAssets.barThickness,
                    ropeImage: FluffyRopeProgressAssets.bundledRopeImage,
                    compactVertical: compactVertical,
                    suppressesAccessibility: true
                )
            } else {
                FluffyRopeProgressIndeterminate(
                    compactVertical: compactVertical,
                    reduceMotion: accessibilityReduceMotion
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityTitle))
        .accessibilityValue(Text(accessibilityValueText))
    }

    private var accessibilityTitle: String {
        if let label, !label.isEmpty { return label }
        return String(localized: "Progress")
    }

    private var accessibilityValueText: String {
        if let value {
            return String(format: String(localized: "%lld percent"), Int64(Int((max(0, min(1, value)) * 100).rounded())))
        }
        return String(localized: "In progress")
    }
}

// MARK: - Indeterminate

private struct FluffyRopeProgressIndeterminate: View {
    var compactVertical: Bool
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            RopeProgressBar(
                progress: 1.0,
                thickness: FluffyRopeProgressAssets.barThickness,
                ropeImage: FluffyRopeProgressAssets.bundledRopeImage,
                compactVertical: compactVertical,
                suppressesAccessibility: true
            )

            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let phase = t.truncatingRemainder(dividingBy: 1.8) / 1.8
                    GeometryReader { geo in
                        let w = geo.size.width
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        .white.opacity(0.16),
                                        .white.opacity(0.30),
                                        .clear,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(28, w * 0.42))
                            .offset(x: -w * 0.22 + CGFloat(phase) * (w * 1.18))
                            .blendMode(.plusLighter)
                    }
                }
            }
        }
        .clipShape(Capsule(style: .continuous))
    }
}

#Preview {
    ZStack {
        WistShellWindowBackdrop().ignoresSafeArea()
        VStack(spacing: 20) {
            FluffyRopeProgressBar(value: 0.35, label: "Downloading", compactVertical: false)
                .padding(.horizontal, 32)
            FluffyRopeProgressBar(value: 1.0, label: nil, compactVertical: false)
                .padding(.horizontal, 32)
            FluffyRopeProgressBar(value: nil, label: "Working…", compactVertical: false)
                .padding(.horizontal, 32)
        }
    }
    .frame(width: 720, height: 260)
    .preferredColorScheme(.dark)
}
