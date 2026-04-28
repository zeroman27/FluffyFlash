//
//  FluffyDesignSystem.swift
//  Fluffy Flash
//
//  Soft tactile tokens + “pillow” surfaces (outer shadow + subtle inner highlight).
//

import SwiftUI

enum FluffyColor {
    static let background = Color(fluffyHex: 0x0B0F1A)
    static let surface = Color(fluffyHex: 0x12182A)
    static let elevated = Color(fluffyHex: 0x1A2040)
    static let purple = Color(fluffyHex: 0x7B5CFF)
    static let purpleGlow = Color(fluffyHex: 0x9D84FF)
    static let orange = Color(fluffyHex: 0xFF8A3D)
    static let orangeHi = Color(fluffyHex: 0xFFB36B)
    static let textPrimary = Color(fluffyHex: 0xFFFFFF)
    static let textSecondary = Color(fluffyHex: 0xA0A7C0)
    static let textMuted = Color(fluffyHex: 0x6B7280)
}

extension Color {
    init(fluffyHex: UInt32, alpha: Double = 1) {
        let r = Double((fluffyHex >> 16) & 0xFF) / 255
        let g = Double((fluffyHex >> 8) & 0xFF) / 255
        let b = Double(fluffyHex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// Soft outer shadow + very subtle inner top highlight (CSS-like inset).
struct FluffyPillowSurface: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    FluffyColor.surface.opacity(0.95),
                                    FluffyColor.elevated.opacity(0.92),
                                    FluffyColor.surface.opacity(0.98),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    // micro “fabric” grain — extremely subtle
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .blendMode(.overlay)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.06), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .blendMode(.plusLighter)
                    .padding(1)
            }
            .shadow(color: Color.black.opacity(0.40), radius: 30, x: 0, y: 10)
    }
}

extension View {
    func fluffyPillow(cornerRadius: CGFloat = 18) -> some View {
        modifier(FluffyPillowSurface(cornerRadius: cornerRadius))
    }
}

struct FluffyOrangeProgressBar: View {
    var value: Double?

    var body: some View {
        FluffyRopeProgressBar(
            value: value.map { CGFloat($0) },
            label: nil,
            compactVertical: false
        )
    }
}
