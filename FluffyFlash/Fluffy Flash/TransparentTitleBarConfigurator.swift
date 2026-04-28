//
//  TransparentTitleBarConfigurator.swift
//  Wist
//
//  Hides the visible title bar chrome while keeping traffic lights and the standard drag region.
//

import AppKit
import SwiftUI

/// Attaches to the window and configures a transparent title bar + full-size content (content draws under the title bar area).
struct TransparentTitleBarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.isHidden = true
        context.coordinator.scheduleConfigure(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.scheduleConfigure(for: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var viewRef: NSView?

        func scheduleConfigure(for view: NSView) {
            viewRef = view
            DispatchQueue.main.async { [weak self] in
                self?.configureIfPossible()
            }
        }

        private func configureIfPossible() {
            guard let view = viewRef, let window = view.window else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.configureIfPossible()
                }
                return
            }
            apply(to: window)
        }

        private func apply(to window: NSWindow) {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.title = ""
            if let toolbar = window.toolbar {
                toolbar.isVisible = false
            }
        }
    }
}
