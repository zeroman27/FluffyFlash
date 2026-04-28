//
//  AppLaunchWindowChrome.swift
//  Fluffy Flash
//
//  During the launch video, use borderless chrome so content fills the window
//  (no title bar / traffic lights). Restores the previous window state for the
//  main UI (then `TransparentTitleBarConfigurator` applies again).
//

import AppKit
import SwiftUI

private enum AppLaunchWindowChromeConstants {
    /// Rounded client area during the launch video (matches soft Fluffy UI).
    static let contentCornerRadius: CGFloat = 22
    /// Fixed window content size during launch video (matches `WistApp` defaultSize).
    static let splashContentWidth: CGFloat = 980
    static let splashContentHeight: CGFloat = 640
}

struct AppLaunchWindowChrome: NSViewRepresentable {
    var isLaunchPhase: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLaunchPhase: isLaunchPhase)
    }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.isHidden = true
        context.coordinator.isLaunchPhase = isLaunchPhase
        context.coordinator.scheduleApply(using: v)
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isLaunchPhase = isLaunchPhase
        context.coordinator.scheduleApply(using: nsView)
    }

    final class Coordinator {
        private struct Snapshot {
            var frame: NSRect
            var styleMask: NSWindow.StyleMask
            var titleVisibility: NSWindow.TitleVisibility
            var titlebarAppearsTransparent: Bool
            var closeHidden: Bool
            var miniHidden: Bool
            var zoomHidden: Bool
            var toolbarVisible: Bool?
            var title: String
            var isOpaque: Bool
            var backgroundColor: NSColor?
            var contentWantsLayer: Bool
            var contentCornerRadius: CGFloat
            var contentMasksToBounds: Bool
        }

        private weak var anchor: NSView?
        private var snapshot: Snapshot?
        private var lastAppliedLaunchPhase: Bool?

        var isLaunchPhase: Bool

        init(isLaunchPhase: Bool) {
            self.isLaunchPhase = isLaunchPhase
        }

        func scheduleApply(using view: NSView) {
            anchor = view
            DispatchQueue.main.async { [weak self] in
                self?.applyIfPossible()
            }
        }

        private func applyIfPossible() {
            guard let view = anchor, let window = view.window else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.applyIfPossible()
                }
                return
            }

            if snapshot == nil {
                let cv = window.contentView
                snapshot = Snapshot(
                    frame: window.frame,
                    styleMask: window.styleMask,
                    titleVisibility: window.titleVisibility,
                    titlebarAppearsTransparent: window.titlebarAppearsTransparent,
                    closeHidden: window.standardWindowButton(.closeButton)?.isHidden ?? false,
                    miniHidden: window.standardWindowButton(.miniaturizeButton)?.isHidden ?? false,
                    zoomHidden: window.standardWindowButton(.zoomButton)?.isHidden ?? false,
                    toolbarVisible: window.toolbar?.isVisible,
                    title: window.title,
                    isOpaque: window.isOpaque,
                    backgroundColor: window.backgroundColor,
                    contentWantsLayer: cv?.wantsLayer ?? false,
                    contentCornerRadius: cv?.layer?.cornerRadius ?? 0,
                    contentMasksToBounds: cv?.layer?.masksToBounds ?? false
                )
            }

            if lastAppliedLaunchPhase == isLaunchPhase { return }
            lastAppliedLaunchPhase = isLaunchPhase

            if isLaunchPhase {
                applyLaunchChrome(to: window)
            } else if let snap = snapshot {
                restore(from: snap, window: window)
            }
        }

        private func applyLaunchChrome(to window: NSWindow) {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.title = ""
            window.toolbar?.isVisible = false

            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true

            window.styleMask = [.borderless, .fullSizeContentView]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true

            if let cv = window.contentView {
                cv.wantsLayer = true
                cv.layer?.cornerRadius = AppLaunchWindowChromeConstants.contentCornerRadius
                cv.layer?.masksToBounds = true
            }

            window.setContentSize(
                NSSize(
                    width: AppLaunchWindowChromeConstants.splashContentWidth,
                    height: AppLaunchWindowChromeConstants.splashContentHeight
                )
            )
            window.center()

            window.invalidateShadow()
            window.contentView?.needsLayout = true
            window.contentView?.layoutSubtreeIfNeeded()
        }

        private func restore(from snap: Snapshot, window: NSWindow) {
            window.styleMask = snap.styleMask
            window.titleVisibility = snap.titleVisibility
            window.titlebarAppearsTransparent = snap.titlebarAppearsTransparent
            window.title = snap.title

            window.standardWindowButton(.closeButton)?.isHidden = snap.closeHidden
            window.standardWindowButton(.miniaturizeButton)?.isHidden = snap.miniHidden
            window.standardWindowButton(.zoomButton)?.isHidden = snap.zoomHidden

            if let vis = snap.toolbarVisible, let toolbar = window.toolbar {
                toolbar.isVisible = vis
            }

            window.isOpaque = snap.isOpaque
            window.backgroundColor = snap.backgroundColor

            if let cv = window.contentView {
                cv.wantsLayer = snap.contentWantsLayer
                if let layer = cv.layer {
                    layer.cornerRadius = snap.contentCornerRadius
                    layer.masksToBounds = snap.contentMasksToBounds
                }
            }

            window.setFrame(snap.frame, display: true)

            window.invalidateShadow()
            window.contentView?.needsLayout = true
            window.contentView?.layoutSubtreeIfNeeded()
        }
    }
}
