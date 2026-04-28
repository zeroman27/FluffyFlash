//
//  ModeSliderSwitch.swift
//  Fluffy Flash
//

import SwiftUI

/// Sidebar mode switcher: pill slider between Windows and macOS.
struct ModeSliderSwitch: View {
    @Binding var mode: AppMode

    var width: CGFloat = 144
    var height: CGFloat = 34

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false
    @State private var dragX: CGFloat? = nil
    @Namespace private var knobNS

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.82)
    }

    var body: some View {
        let knobHeight = height - 6
        let knobWidth = knobHeight * 1.55
        let trackWidth = width
        let maxX = (trackWidth - knobWidth) / 2
        let targetX: CGFloat = (mode == .macos) ? maxX : -maxX
        let x = dragX.map { clamp($0, -maxX, maxX) } ?? targetX

        ZStack {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.18),
                                    Color.white.opacity(0.08),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: Color.black.opacity(0.22), radius: 10, y: 4)

            // Knob
            ZStack {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                FluffyColor.orange.opacity(0.55),
                                FluffyColor.orangeHi.opacity(0.22),
                                Color.white.opacity(0.06),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.06))
                            .blendMode(.overlay)
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        FluffyColor.orangeHi.opacity(0.55),
                                        Color.white.opacity(0.10),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: FluffyColor.orangeHi.opacity(0.25), radius: 14, y: 2)
                    .shadow(color: Color.black.opacity(0.22), radius: 8, y: 4)

                let iconSize: CGFloat = (mode == .macos) ? 15 : 14
                Image(mode == .macos ? "ModeIconApple" : "ModeIconWindows")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(Color.white.opacity(0.95))
                    .shadow(color: Color.black.opacity(0.25), radius: 4, y: 1)
                    .accessibilityHidden(true)
            }
            .frame(width: knobWidth, height: knobHeight)
            .offset(x: x)
            .scaleEffect(isPressed ? 0.985 : 1)
            .animation(animation, value: mode)
            .animation(animation, value: isPressed)
        }
        .frame(width: width, height: height)
        .contentShape(Capsule(style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    isPressed = true
                    dragX = value.translation.width + targetX
                }
                .onEnded { _ in
                    isPressed = false
                    let finalX = x
                    dragX = nil
                    withAnimation(animation) {
                        mode = (finalX >= 0) ? .macos : .windows
                    }
                }
        )
        .onTapGesture {
            withAnimation(animation) { mode = (mode == .windows) ? .macos : .windows }
        }
        .accessibilityLabel(Text("Mode"))
        .accessibilityValue(Text(mode.title))
        .accessibilityHint(Text("Switch between Windows and macOS"))
    }

    private func clamp(_ v: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
        min(max(v, a), b)
    }
}

#Preview {
    VStack(spacing: 16) {
        ModeSliderSwitch(mode: .constant(.windows))
        ModeSliderSwitch(mode: .constant(.macos))
    }
    .padding(24)
    .preferredColorScheme(.dark)
}

