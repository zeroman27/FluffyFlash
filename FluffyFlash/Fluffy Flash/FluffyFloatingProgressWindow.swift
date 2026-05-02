//
//  FluffyFloatingProgressWindow.swift
//  Fluffy Flash
//
//  A small NSWindow at .floating level that can be popped out from the running
//  state. Shows aggregated progress + a Stop button so the user can keep an eye
//  on the write while doing other work.
//

import AppKit
import SwiftUI

@MainActor
final class FluffyFloatingProgressController: NSObject, NSWindowDelegate {

    static let shared = FluffyFloatingProgressController()

    private var window: NSWindow?

    func toggle(e2e: EndToEndMediaPipeline, usb: USBWriterViewModel) {
        if window == nil {
            show(e2e: e2e, usb: usb)
        } else {
            hide()
        }
    }

    var isOpen: Bool { window != nil }

    func show(e2e: EndToEndMediaPipeline, usb: USBWriterViewModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(
            rootView: FluffyFloatingProgressView(e2e: e2e, usb: usb) { [weak self] in
                self?.hide()
            }
            .frame(width: 320, height: 140)
        )
        let win = NSWindow(contentViewController: host)
        win.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.setContentSize(NSSize(width: 320, height: 140))
        win.makeKeyAndOrderFront(nil)
        window = win
    }

    func hide() {
        window?.delegate = nil
        window?.close()
        window = nil
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct FluffyFloatingProgressView: View {
    @ObservedObject var e2e: EndToEndMediaPipeline
    @ObservedObject var usb: USBWriterViewModel
    let onClose: () -> Void

    private static let speed: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f
    }()

    var body: some View {
        ZStack {
            WistShellWindowBackdrop()
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "externaldrive.fill.badge.timemachine")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(FluffyColor.purpleGlow)
                    Text(e2e.statusLine.isEmpty ? String(localized: "Fluffy Flash") : e2e.statusLine)
                        .font(WistFont.headlineRounded(13))
                        .lineLimit(2)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Hide floating window"))
                }

                FluffyOrangeProgressBar(value: aggregatedProgress)

                HStack {
                    if let mbps = peakSpeedText {
                        Text(mbps)
                            .font(WistFont.caption(11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        e2e.requestCancel()
                    } label: {
                        Label(String(localized: "Stop"), systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!e2e.canCancel)
                }
            }
            .padding(16)
        }
    }

    private var aggregatedProgress: Double? {
        let entries = usb.perDriveProgress.values
        guard !entries.isEmpty else { return nil }
        let sum = entries.map(\.overallProgress).reduce(0, +)
        return sum / Double(entries.count)
    }

    private var peakSpeedText: String? {
        let speeds = usb.perDriveProgress.values.map(\.stepBytesPerSecond).filter { $0 > 0 }
        guard let max = speeds.max() else { return nil }
        return "\(Self.speed.string(fromByteCount: Int64(max)))/s"
    }
}
