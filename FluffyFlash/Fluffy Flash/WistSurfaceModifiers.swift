//
//  WistSurfaceModifiers.swift
//  Wist
//
//  Glass panels, subtle neumorphism, ambient mesh background, glow search field.
//

import SwiftUI
import CoreGraphics

// MARK: - Full window backdrop (behind floating glass panels)

/// Full-window backdrop behind floating glass panels.
/// Tuned for the “fluffy” look: deep navy base, ultra-subtle noise, ambient glows.
struct WistShellWindowBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geo in
            let r = max(geo.size.width, geo.size.height)
            ZStack {
                // Base: deep navy (not pure black) + very soft vertical gradient.
                LinearGradient(
                    colors: [
                        Color(hex: 0x141833),
                        Color(hex: 0x0B0F1A),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if reduceTransparency {
                    WistTheme.premiumPageAtmosphere(colorScheme: .dark)
                        .opacity(0.95)
                } else {
                    // Noise / fabric: generated once, tiled, extremely subtle (1–3%).
                    FluffyNoiseOverlay(intensity: 0.022)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(false)
                        .blendMode(.overlay)

                    // Ambient glows: subtle “inside light” behind content.
                    RadialGradient(
                        colors: [
                            Color(red: 123/255, green: 92/255, blue: 1).opacity(0.16),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.30, y: 0.20),
                        startRadius: 20,
                        endRadius: r * 0.55
                    )
                    .allowsHitTesting(false)
                    .blendMode(.screen)

                    RadialGradient(
                        colors: [
                            WistTheme.auroraCyan.opacity(0.08),
                            Color.clear,
                        ],
                        center: UnitPoint(x: 0.78, y: 0.32),
                        startRadius: 12,
                        endRadius: r * 0.50
                    )
                    .allowsHitTesting(false)
                    .blendMode(.screen)

                    // Center lift (very soft) + corner vignette.
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.clear,
                        ],
                        center: .center,
                        startRadius: 40,
                        endRadius: r * 0.45
                    )
                    .allowsHitTesting(false)
                    .blendMode(.screen)

                    RadialGradient(
                        colors: [
                            Color.clear,
                            Color.black.opacity(0.36),
                            Color.black.opacity(0.58),
                        ],
                        center: .center,
                        startRadius: r * 0.38,
                        endRadius: r * 0.95
                    )
                    .allowsHitTesting(false)
                    .blendMode(.multiply)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

// MARK: - Noise (generated once; tiled)

private struct FluffyNoiseOverlay: View {
    let intensity: CGFloat

    var body: some View {
        if let cgImage = FluffyNoiseImage.shared.cgImage {
            Image(decorative: cgImage, scale: 1)
                .interpolation(.none)
                .resizable(resizingMode: .tile)
                .opacity(intensity)
        } else {
            Color.clear
        }
    }
}

private final class FluffyNoiseImage {
    static let shared = FluffyNoiseImage()
    let cgImage: CGImage?

    private init() {
        self.cgImage = Self.makeNoiseCGImage(size: 128)
    }

    private static func makeNoiseCGImage(size: Int) -> CGImage? {
        let width = size
        let height = size
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let byteCount = bytesPerRow * height

        var data = [UInt8](repeating: 0, count: byteCount)
        data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for i in stride(from: 0, to: byteCount, by: 4) {
                let v = UInt8.random(in: 0...255)
                base[i + 0] = v
                base[i + 1] = v
                base[i + 2] = v
                base[i + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Floating shell panels (nav + main) — blur + tint + rim

struct WistShellGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 22

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(panelBaseFill)
                    if !reduceTransparency {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        WistTheme.neonPurple.opacity(0.07),
                                        Color.white.opacity(0.04),
                                        WistTheme.auroraCyan.opacity(0.06),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.plusLighter)
                            .opacity(0.75)
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                WistTheme.glassBorder.opacity(0.55),
                                WistTheme.auroraCyan.opacity(0.28),
                                WistTheme.neonPurple.opacity(0.22),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.42), radius: 28, x: 0, y: 14)
            .shadow(color: WistTheme.neonPurple.opacity(0.12), radius: 22, x: 0, y: 0)
    }

    private var panelBaseFill: some ShapeStyle {
        if reduceTransparency {
            AnyShapeStyle(WistTheme.canvasElevated.opacity(0.94))
        } else {
            AnyShapeStyle(Material.ultraThinMaterial)
        }
    }
}

extension View {
    /// Glass “card” for shell nav and main column — blur shows `WistShellWindowBackdrop` through the panel.
    func wistShellGlassCard(cornerRadius: CGFloat = 22) -> some View {
        modifier(WistShellGlassCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Ambient mesh (slow drift; respects Reduce Motion / Transparency)

/// Slow-moving purple / orange / cyan blobs behind a dark wash — cards stay readable.
struct AmbientMeshBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static let tick: TimeInterval = 0.12

    var body: some View {
        Group {
            if colorScheme != .dark {
                WistTheme.pageBackground
            } else if reduceTransparency {
                WistTheme.premiumPageAtmosphere(colorScheme: .dark)
            } else if reduceMotion {
                staticMesh
            } else {
                TimelineView(.periodic(from: Date(), by: Self.tick)) { ctx in
                    meshLayer(date: ctx.date)
                }
            }
        }
    }

    private var staticMesh: some View {
        meshLayer(date: Date(timeIntervalSinceReferenceDate: 0))
    }

    private func meshLayer(date: Date) -> some View {
        let t = date.timeIntervalSinceReferenceDate
        /// ~18s full cycle
        let phase = (sin(t / 18 * .pi * 2) + 1) / 2
        let phase2 = (sin(t / 14 * .pi * 2 + 1.1) + 1) / 2

        return GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                WistTheme.canvas
                WistTheme.premiumPageAtmosphere(colorScheme: .dark)
                    .opacity(0.55)

                // Blob A — purple
                RadialGradient(
                    colors: [WistTheme.neonPurple.opacity(0.38), Color.clear],
                    center: UnitPoint(
                        x: 0.15 + phase * 0.25,
                        y: 0.2 + phase2 * 0.15
                    ),
                    startRadius: 20,
                    endRadius: max(w, h) * 0.55
                )
                // Blob B — orange
                RadialGradient(
                    colors: [WistTheme.neonOrange.opacity(0.22), Color.clear],
                    center: UnitPoint(
                        x: 0.85 - phase * 0.2,
                        y: 0.35 + phase * 0.1
                    ),
                    startRadius: 30,
                    endRadius: max(w, h) * 0.5
                )
                // Blob C — cyan
                RadialGradient(
                    colors: [WistTheme.auroraCyan.opacity(0.18), Color.clear],
                    center: UnitPoint(
                        x: 0.45 + phase2 * 0.2,
                        y: 0.75 - phase * 0.12
                    ),
                    startRadius: 24,
                    endRadius: max(w, h) * 0.45
                )

                /// Dark veil so foreground glass pops
                LinearGradient(
                    colors: [
                        WistTheme.canvas.opacity(0.5),
                        WistTheme.canvas.opacity(0.72),
                        WistTheme.canvas.opacity(0.88),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Glass panel

struct WistGlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = WistTheme.radiusCard
    var strokeOpacity: Double = 0.12

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(panelFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(WistTheme.glassBorder.opacity(strokeOpacity + 0.06), lineWidth: 1)
            }
    }

    private var panelFill: some ShapeStyle {
        if reduceTransparency {
            AnyShapeStyle(WistTheme.canvasElevated.opacity(0.94))
        } else {
            AnyShapeStyle(Material.ultraThinMaterial)
        }
    }
}

extension View {
    func wistGlassPanel(cornerRadius: CGFloat = WistTheme.radiusCard, strokeOpacity: Double = 0.12) -> some View {
        modifier(WistGlassPanelModifier(cornerRadius: cornerRadius, strokeOpacity: strokeOpacity))
    }
}

// MARK: - Neumorphic (very subtle)

struct WistNeumorphicRaisedModifier: ViewModifier {
    var isPressed: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .shadow(color: Color.black.opacity(isPressed ? 0.12 : 0.28), radius: isPressed ? 2 : 8, x: 0, y: isPressed ? 1 : 4)
            .shadow(color: Color.white.opacity(0.06), radius: 1, x: 0, y: -1)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78), value: isPressed)
    }
}

struct WistNeumorphicInsetModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: Color.black.opacity(0.45), radius: 2, x: 0, y: 2)
            .shadow(color: Color.white.opacity(0.04), radius: 0, x: 0, y: -1)
    }
}

extension View {
    func wistNeumorphicRaised(isPressed: Bool = false) -> some View {
        modifier(WistNeumorphicRaisedModifier(isPressed: isPressed))
    }

    func wistNeumorphicInset() -> some View {
        modifier(WistNeumorphicInsetModifier())
    }
}

// MARK: - Glowing search field

struct WistGlowSearchField: View {
    @Binding var text: String
    var prompt: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(WistFont.body(13))
                .focused($focused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WistTheme.canvasElevated.opacity(0.65))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: borderColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: focused ? 1.5 : 1
                        )
                }
                .shadow(color: glowColor, radius: focused ? 14 : 6, x: 0, y: 0)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: focused)
    }

    private var borderColors: [Color] {
        if focused {
            [WistTheme.auroraCyan.opacity(0.85), WistTheme.neonPurple.opacity(0.65)]
        } else {
            [WistTheme.glassBorder, WistTheme.hairline]
        }
    }

    private var glowColor: Color {
        focused
            ? WistTheme.neonPurple.opacity(0.35)
            : Color.clear
    }
}

// MARK: - CTA gradient button (Write / Run all)

struct WistCTAGradientButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WistTheme.ctaFillGradient)
                    .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.45)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            .wistNeumorphicRaised(isPressed: configuration.isPressed)
            .animation(.spring(response: 0.32, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

// MARK: - Gradient ring (downloads / status)

struct WistGradientProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 10
    var size: CGFloat = 72

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: CGFloat {
        CGFloat(min(1, max(0, progress)))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    WistTheme.progressAngular,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: clamped)
        }
        .frame(width: size, height: size)
        .shadow(color: WistTheme.neonOrange.opacity(0.22), radius: 8, y: 0)
        .accessibilityLabel(String(localized: "Download progress"))
        .accessibilityValue(String(format: String(localized: "%lld percent"), Int64(Double(progress) * 100)))
    }
}
