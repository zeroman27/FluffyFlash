import AppKit
import SwiftUI

/// Horizontal rope progress. Uses **fill** (not a thick `stroke`) so `ImagePaint` tiles
/// along the bar once per row of pixels — matching the Lab preview (no vertical doubling).
struct RopeProgressBar: View {
    var progress: CGFloat
    var thickness: CGFloat = 22
    var ropeImage: NSImage?
    /// Tighter vertical footprint (e.g. bottom download strip).
    var compactVertical: Bool = false
    /// When wrapped by `FluffyRopeProgressBar`, hide inner a11y to avoid duplicate announcements.
    var suppressesAccessibility: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .local)
            let h = max(6, min(thickness, rect.height))
            let p = max(0, min(1, progress))
            let fillWidth = rect.width * p

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: rect.width, height: h)

                if let ropeImage, p > 0 {
                    let tileScale = max(0.05, min(8, h / max(1, ropeImage.size.height)))
                    Capsule()
                        .fill(ImagePaint(image: Image(nsImage: ropeImage), scale: tileScale))
                        .frame(width: max(1, fillWidth), height: h)
                        .shadow(color: Color.black.opacity(0.35), radius: 6, y: 3)
                } else if p > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [FluffyColor.purpleGlow.opacity(0.9), FluffyColor.orange.opacity(0.9)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(1, fillWidth), height: h)
                }
            }
            .frame(width: rect.width, height: rect.height, alignment: .leading)
        }
        .frame(height: compactVertical ? max(28, thickness + 14) : max(44, thickness + 26))
        .accessibilityHidden(suppressesAccessibility)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Progress"))
        .accessibilityValue(Text("\(Int((progress * 100).rounded()))%"))
    }
}
