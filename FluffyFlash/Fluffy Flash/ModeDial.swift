//
//  ModeDial.swift
//  Wist
//

import SwiftUI

/// Sidebar mode switcher: a small "dial" that rotates between Windows and macOS.
struct ModeDial: View {
    @Binding var mode: AppMode
    var size: CGFloat = 84
    var variant: Variant = .variantA

    enum Variant: String, CaseIterable, Identifiable {
        case variantA
        case variantB
        case variantC

        var id: String { rawValue }
    }

    @Namespace private var knobNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.72)

        ZStack {
            dialBackground

            if variant == .variantC {
                dialLabels
            }

            knob
                .rotationEffect(.degrees(knobRotationDegrees))
                .animation(animation, value: mode)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .scaleEffect(isPressed ? 0.985 : (isHovered ? 1.02 : 1.0))
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.75), value: isHovered)
        .animation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.75), value: isPressed)
        .onHover { isHovered = $0 }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { _ in isPressed = true }
                .onEnded { value in
                    isPressed = false
                    // Horizontal intent: left = Windows, right = macOS.
                    if value.translation.width > 6 {
                        withAnimation(animation) { mode = .macos }
                    } else if value.translation.width < -6 {
                        withAnimation(animation) { mode = .windows }
                    } else {
                        withAnimation(animation) { toggle() }
                    }
                }
        )
        .onTapGesture {
            withAnimation(animation) { toggle() }
        }
        .accessibilityLabel(Text("Mode"))
        .accessibilityValue(Text(mode.title))
        .accessibilityHint(Text("Switch between Windows and macOS"))
    }

    private var knobRotationDegrees: Double {
        switch mode {
        case .windows: return -42
        case .macos: return 42
        }
    }

    private func toggle() {
        mode = (mode == .windows) ? .macos : .windows
    }

    private var dialBackground: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovered ? 0.18 : 0.12),
                                    Color.white.opacity(0.06),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)

            if variant == .variantB {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.12),
                                Color.clear,
                            ],
                            center: .topLeading,
                            startRadius: 6,
                            endRadius: size * 0.7
                        )
                    )
                    .blendMode(.plusLighter)
            }
        }
    }

    private var dialLabels: some View {
        VStack(spacing: 4) {
            labelChip(text: "macOS", isActive: mode == .macos)
            Spacer()
            labelChip(text: "Windows", isActive: mode == .windows)
        }
        .padding(.vertical, 10)
    }

    private func labelChip(text: String, isActive: Bool) -> some View {
        Text(text)
            .font(WistFont.caption(9).weight(.semibold))
            .foregroundStyle(isActive ? Color.white : Color.white.opacity(0.55))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isActive ? Color.white.opacity(0.10) : Color.clear)
            )
            .overlay(
                Capsule().strokeBorder(Color.white.opacity(isActive ? 0.14 : 0), lineWidth: 0.8)
            )
    }

    private var knob: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.06),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 8, y: 4)

            Image(systemName: mode == .macos ? "apple.logo" : "window.and.arrow.up.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.92))
        }
        .frame(width: size * 0.44, height: size * 0.44)
        .offset(x: size * 0.23)
        .matchedGeometryEffect(id: "knob", in: knobNS)
    }
}

#Preview {
    VStack(spacing: 24) {
        ModeDial(mode: .constant(.windows), size: 84, variant: .variantA)
        ModeDial(mode: .constant(.windows), size: 84, variant: .variantB)
        ModeDial(mode: .constant(.windows), size: 84, variant: .variantC)
    }
    .padding(24)
    .frame(width: 280, height: 420)
    .preferredColorScheme(.dark)
}

