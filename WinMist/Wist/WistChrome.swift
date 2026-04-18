//
//  WistChrome.swift
//  Wist
//
//  Dark purple chrome + glass panels: materials over violet gradients, thin rim highlights.
//

import AppKit
import SwiftUI

// MARK: - Tokens

enum WistTheme {
    /// Inner panels — Raycast uses ~12–14pt continuous corners.
    static let radiusCard: CGFloat = 14
    static let radiusChip: CGFloat = 8
    static let gutter: CGFloat = 20
    static let pagePadding: CGFloat = 24

    /// Dark purple-grey chrome (shared tone across window).
    static var rayDarkTop: Color {
        Color(red: 0.14, green: 0.10, blue: 0.20)
    }

    static var rayDarkBottom: Color {
        Color(red: 0.06, green: 0.04, blue: 0.11)
    }

    /// Flat fallback behind gradients.
    static var sidebarBackground: Color {
        Color(red: 0.06, green: 0.04, blue: 0.10)
    }

    /// Sidebar: deep violet gradient (reads “glass” when layered with material).
    static var sidebarGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.14, green: 0.07, blue: 0.22),
                Color(red: 0.06, green: 0.04, blue: 0.12),
                Color(red: 0.04, green: 0.03, blue: 0.08),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Subtle wash on cards / hero over the purple backdrop.
    static var mistVioletTint: Color {
        Color(red: 0.22, green: 0.12, blue: 0.38)
    }

    /// Raised wells / tiles inside content.
    static var surfaceElevated: Color {
        Color(red: 0.18, green: 0.14, blue: 0.24)
    }

    static var pageBackground: Color {
        Color(nsColor: .underPageBackgroundColor)
    }

    static var surface: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var hairline: Color {
        Color.white.opacity(0.06)
    }

    static var glassBorder: Color {
        Color.white.opacity(0.09)
    }

    static var shadowSoft: Color {
        Color.black.opacity(0.45)
    }

    static var shadowTight: Color {
        Color.black.opacity(0.28)
    }

    static func cardFaceGradient(colorScheme: ColorScheme) -> LinearGradient {
        switch colorScheme {
        case .dark:
            LinearGradient(
                colors: [
                    Color.white.opacity(0.055),
                    Color.white.opacity(0.02),
                    Color.black.opacity(0.18),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        default:
            LinearGradient(
                colors: [
                    Color.white.opacity(0.95),
                    surface.opacity(0.98),
                    Color(nsColor: .controlBackgroundColor).opacity(0.92),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// Purple-violet atmosphere behind detail content (shows through glass panels).
    static func pageAtmosphereGradient(colorScheme: ColorScheme) -> LinearGradient {
        switch colorScheme {
        case .dark:
            LinearGradient(
                colors: [
                    mistVioletTint.opacity(0.35),
                    rayDarkTop,
                    Color(red: 0.05, green: 0.035, blue: 0.09),
                    rayDarkBottom,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.06),
                    pageBackground,
                    Color(nsColor: .windowBackgroundColor).opacity(0.85),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - Depth helpers

private struct MistCardElevation: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .shadow(color: WistTheme.shadowSoft, radius: reduceMotion ? 6 : 14, x: 0, y: reduceMotion ? 3 : 6)
            .shadow(color: WistTheme.shadowTight, radius: reduceMotion ? 1 : 3, x: 0, y: reduceMotion ? 1 : 1)
    }
}

extension View {
    func mistCardElevation() -> some View {
        modifier(MistCardElevation())
    }
}

// MARK: - Interaction (hover / focus — UI/UX Pro Max: feedback on interactive surfaces)

/// Subtle hover lift for macOS glass rows (respects Reduce Motion).
struct MistHoverRowHighlight: ViewModifier {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .brightness(isActive ? 0.055 : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: isActive)
    }
}

extension View {
    func mistHoverRowHighlight(_ active: Bool) -> some View {
        modifier(MistHoverRowHighlight(isActive: active))
    }
}

/// Hero strip — Raycast-style bar (flat fills + gradients; no Material — avoids heavy glass updates on macOS).
struct MistHeroBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if reduceMotion {
                WistTheme.surfaceElevated.opacity(0.65)
            } else {
                Rectangle()
                    .fill(WistTheme.surfaceElevated.opacity(colorScheme == .dark ? 0.42 : 0.88))
                LinearGradient(
                    colors: stripColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(colorScheme == .dark ? 0.55 : 0.72)
                RadialGradient(
                    colors: [
                        WistTheme.mistVioletTint.opacity(colorScheme == .dark ? 0.18 : 0.1),
                        Color.clear,
                    ],
                    center: .topTrailing,
                    startRadius: 24,
                    endRadius: 200
                )
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(WistTheme.hairline)
                .frame(height: 1)
        }
    }

    private var stripColors: [Color] {
        switch colorScheme {
        case .dark:
            return [
                WistTheme.surfaceElevated.opacity(0.35),
                WistTheme.rayDarkTop.opacity(0.45),
                WistTheme.rayDarkBottom.opacity(0.25),
            ]
        default:
            return [
                Color.accentColor.opacity(0.08),
                Color.white.opacity(0.65),
                WistTheme.pageBackground.opacity(0.9),
            ]
        }
    }
}

// MARK: - Typography (Swiss-style: default SF, clear hierarchy)

enum WistFont {
    /// Large page title
    static func display(_ size: CGFloat = 26) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func title(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func headline(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }

    static func body(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func caption(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    /// Uppercase section eyebrow
    static func eyebrow(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
}

// MARK: - Page chrome

/// Detail column header — compact icon tile (Raycast settings / list density).
struct MistPageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbolName: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WistTheme.surfaceElevated.opacity(colorScheme == .dark ? 0.96 : 1))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.12))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(WistTheme.glassBorder, lineWidth: 1)
                Image(systemName: symbolName)
                    .font(.system(size: 20, weight: .medium, design: .default))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 48, height: 48)
            .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 3)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased())
                    .font(WistFont.eyebrow(10))
                    .tracking(0.55)
                    .foregroundStyle(.tertiary)
                Text(title)
                    .font(WistFont.display(22))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(WistFont.body(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Legacy initializer bridge — maps to MistPageHeader with a generic eyebrow.
struct FeatureHeroHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        MistPageHeader(
            eyebrow: String(localized: "Section"),
            title: title,
            subtitle: subtitle,
            symbolName: systemImage
        )
    }
}

// MARK: - Bento / layered cards

struct MistSectionCard<Content: View>: View {
    let title: String
    let systemImage: String?
    let content: Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.secondary, Color.secondary.opacity(0.65)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 16, alignment: .center)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(WistFont.headline(12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 12)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: WistTheme.radiusCard, style: .continuous)
                    .fill(WistTheme.surfaceElevated.opacity(colorScheme == .dark ? 0.58 : 0.94))
                RoundedRectangle(cornerRadius: WistTheme.radiusCard, style: .continuous)
                    .fill(WistTheme.mistVioletTint.opacity(colorScheme == .dark ? 0.14 : 0.08))
                if !reduceMotion {
                    RoundedRectangle(cornerRadius: WistTheme.radiusCard, style: .continuous)
                        .fill(WistTheme.cardFaceGradient(colorScheme: colorScheme))
                        .opacity(0.38)
                } else {
                    RoundedRectangle(cornerRadius: WistTheme.radiusCard, style: .continuous)
                        .fill(WistTheme.surface.opacity(0.45))
                }
            }
            .mistCardElevation()
        }
        .overlay {
            RoundedRectangle(cornerRadius: WistTheme.radiusCard, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.14 : 0.45),
                            WistTheme.glassBorder.opacity(0.7),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Open section (long lists)

/// Use for **long, scrolling lists** instead of `MistSectionCard`.
/// `MistSectionCard` paints one material `RoundedRectangle` behind **all** content; with hundreds of
/// rows that rectangle can reach ~10⁵ pt tall and triggers `PaintShapeLayer` bogus sizes + layout jank.
/// This view only renders the section **title**; keep per-row chrome on the rows themselves.
struct MistOpenSection<Content: View>: View {
    let title: String
    let systemImage: String?
    let content: Content

    init(title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold, design: .default))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.secondary, Color.secondary.opacity(0.65)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 16, alignment: .center)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(WistFont.headline(12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 12)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// Wraps detail column: soft atmospheric gradient behind content.
struct MistDetailCanvas<Content: View>: View {
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            if reduceMotion {
                colorScheme == .dark ? WistTheme.rayDarkBottom : WistTheme.pageBackground
            } else {
                ZStack {
                    if colorScheme == .dark {
                        WistTheme.rayDarkBottom
                    }
                    WistTheme.pageAtmosphereGradient(colorScheme: colorScheme)
                    RadialGradient(
                        colors: [WistTheme.mistVioletTint.opacity(0.22), Color.clear],
                        center: .bottomLeading,
                        startRadius: 40,
                        endRadius: 340
                    )
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Workflow pipeline (connected steps)

enum MistPipelineStepState: Equatable {
    case complete
    case current
    case upcoming
}

struct MistPipeline: View {
    let steps: [(title: String, state: MistPipelineStepState)]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                stepColumn(index: index, step: step)
                if index < steps.count - 1 {
                    connectorBetween(
                        left: step.state,
                        right: steps[index + 1].state
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func stepColumn(index: Int, step: (title: String, state: MistPipelineStepState)) -> some View {
        VStack(spacing: 8) {
            ZStack {
                switch step.state {
                case .complete:
                    Circle()
                        .fill(Color.accentColor)
                        .shadow(color: Color.accentColor.opacity(0.22), radius: 3, y: 1)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold, design: .default))
                        .foregroundStyle(Color.white)
                case .current:
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .default))
                        .foregroundStyle(Color.accentColor)
                case .upcoming:
                    Circle()
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold, design: .default))
                        .foregroundStyle(Color.secondary.opacity(0.55))
                }
            }
            .frame(width: 28, height: 28)

            Text(step.title)
                .font(WistFont.caption(10))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .opacity(step.state == .upcoming ? 0.65 : 1)
                .frame(minWidth: 88, maxWidth: 140)
        }
    }

    private func connectorBetween(left: MistPipelineStepState, right _: MistPipelineStepState) -> some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(
                left == .complete
                    ? AnyShapeStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.55), Color.accentColor.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    : AnyShapeStyle(WistTheme.hairline)
            )
            .frame(height: 3)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.top, 12)
            .accessibilityHidden(true)
    }
}

/// Simpler API: numbered steps 1…n with derived states from `activeIndex` (0-based).
struct MistPipelineNumbered: View {
    let titles: [String]
    /// Index of the step user is on (0 = first). Completed = all before.
    let activeIndex: Int

    var body: some View {
        MistPipeline(steps: numberedSteps)
            .animation(.easeInOut(duration: WistMotion.normal), value: activeIndex)
    }

    private var numberedSteps: [(String, MistPipelineStepState)] {
        titles.enumerated().map { i, title in
            let state: MistPipelineStepState
            if i < activeIndex { state = .complete }
            else if i == activeIndex { state = .current }
            else { state = .upcoming }
            return (title, state)
        }
    }
}

// MARK: - Legacy chips (compact fallback)

struct MistStepChip: View {
    let step: Int
    let text: String
    var isActive: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text("\(step)")
                .font(WistFont.caption(10))
                .foregroundStyle(isActive ? Color.white : .secondary)
                .frame(minWidth: 18, minHeight: 18)
                .background {
                    Circle()
                        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.18))
                }
            Text(text)
                .font(WistFont.caption(11))
                .foregroundStyle(isActive ? .primary : .secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(isActive ? 0.12 : 0.06))
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty & warning

struct MistEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.accentColor.opacity(colorScheme == .dark ? 0.1 : 0.08),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 44
                        )
                    )
                    .frame(width: 88, height: 88)
                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .light, design: .default))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.secondary, Color.secondary.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .accessibilityHidden(true)
            Text(title)
                .font(WistFont.title(15))
                .foregroundStyle(.primary)
            Text(message)
                .font(WistFont.body(12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }
}

struct MistWarningCallout: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold, design: .default))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(WistFont.headline(13))
                Text(message)
                    .font(WistFont.body(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.14),
                            Color.orange.opacity(0.05),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.orange.opacity(0.12), radius: 10, x: 0, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.35), Color.orange.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .accessibilityElement(children: .combine)
    }
}
