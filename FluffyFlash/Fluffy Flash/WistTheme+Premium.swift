//
//  WistTheme+Premium.swift
//  Wist
//
//  Premium dark canvas, neon accents, CTA and mesh gradients (strict dark UI).
//

import SwiftUI

extension WistTheme {
    /// Deep charcoal base — not pitch black (#13131A).
    static var canvas: Color {
        Color(red: 19 / 255, green: 19 / 255, blue: 26 / 255)
    }

    /// Slightly lifted surface on canvas.
    static var canvasElevated: Color {
        Color(red: 28 / 255, green: 28 / 255, blue: 36 / 255)
    }

    /// Neon accent — orange (pair with purple + cyan).
    static var neonOrange: Color {
        Color(red: 1.0, green: 0.48, blue: 0.12)
    }

    /// Bright purple for glows and mesh.
    static var neonPurple: Color {
        Color(red: 0.65, green: 0.35, blue: 1.0)
    }

    /// Primary CTA fill: orange → purple (tactile buttons).
    static var ctaFillGradient: LinearGradient {
        LinearGradient(
            colors: [neonOrange, neonPurple.opacity(0.92), mistVioletTint.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Progress / highlights: purple → orange (reads well on dark tracks).
    static var progressFillGradient: LinearGradient {
        LinearGradient(
            colors: [neonPurple.opacity(0.95), neonOrange, auroraCyan.opacity(0.75)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// Ring stroke for determinate progress.
    static var progressAngular: AngularGradient {
        AngularGradient(
            colors: [neonPurple, neonOrange, auroraCyan, neonPurple],
            center: .center
        )
    }

    /// Richer atmosphere for detail canvas (static; animated layer is `AmbientMeshBackground`).
    static func premiumPageAtmosphere(colorScheme: ColorScheme) -> LinearGradient {
        switch colorScheme {
        case .dark:
            LinearGradient(
                colors: [
                    neonPurple.opacity(0.22),
                    canvas,
                    mistVioletTint.opacity(0.28),
                    rayDarkBottom,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            pageAtmosphereGradient(colorScheme: colorScheme)
        }
    }
}
