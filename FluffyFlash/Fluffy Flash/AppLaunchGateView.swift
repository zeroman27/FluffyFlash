//
//  AppLaunchGateView.swift
//  Fluffy Flash
//
//  Full-screen launch video; after playback ends (or on error / reduce motion),
//  the main shell appears.
//

import AppKit
import AVFoundation
import SwiftUI

struct AppLaunchGateView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// Skip splash when this process has already left the gate once, or after closing the window without quitting.
    @State private var launchFinished = AppLaunchSession.hasPassedLaunchGateThisProcess

    private var videoURL: URL? {
        Bundle.main.url(forResource: "AppLaunchVideo", withExtension: "mp4", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: "AppLaunchVideo", withExtension: "mp4")
    }

    var body: some View {
        Group {
            if launchFinished {
                RootView()
            } else if accessibilityReduceMotion || videoURL == nil {
                Color.black
                    .ignoresSafeArea()
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            AppLaunchSession.markPassedLaunchGate()
                            launchFinished = true
                        }
                    }
            } else if let url = videoURL {
                LaunchVideoScreen(url: url) {
                    AppLaunchSession.markPassedLaunchGate()
                    withAnimation(.easeOut(duration: 0.22)) {
                        launchFinished = true
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppLaunchWindowChrome(isLaunchPhase: !launchFinished))
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            guard let window = note.object as? NSWindow else { return }
            if window.sheetParent != nil { return }
            AppLaunchSession.markPassedLaunchGate()
        }
    }
}

// MARK: - Video

private struct LaunchVideoScreen: View {
    let url: URL
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LaunchVideoPlayerView(url: url, onComplete: onComplete)
                .ignoresSafeArea()
        }
    }
}

private struct LaunchVideoPlayerView: NSViewRepresentable {
    let url: URL
    let onComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeNSView(context: Context) -> LaunchVideoContainerView {
        let view = LaunchVideoContainerView()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.volume = 0
        view.playerLayer.player = player

        context.coordinator.attach(player: player, item: item)
        player.play()
        return view
    }

    func updateNSView(_ nsView: LaunchVideoContainerView, context: Context) {}

    static func dismantleNSView(_ nsView: LaunchVideoContainerView, coordinator: Coordinator) {
        coordinator.detach()
        nsView.playerLayer.player?.pause()
        nsView.playerLayer.player = nil
    }

    final class Coordinator: NSObject {
        private let onComplete: () -> Void
        private var endObserver: NSObjectProtocol?
        private var failObserver: NSObjectProtocol?
        private var didFinish = false

        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }

        func attach(player: AVPlayer, item: AVPlayerItem) {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.finishOnce()
            }

            failObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.finishOnce()
            }
        }

        func detach() {
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
            if let failObserver {
                NotificationCenter.default.removeObserver(failObserver)
            }
            endObserver = nil
            failObserver = nil
        }

        private func finishOnce() {
            guard !didFinish else { return }
            didFinish = true
            onComplete()
        }
    }
}

private final class LaunchVideoContainerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

#Preview {
    AppLaunchGateView()
        .frame(width: 900, height: 600)
}
