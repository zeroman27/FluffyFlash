//
//  MacOSStepProgressView.swift
//  Fluffy Flash
//
//  2-step running UI: Download installer → Write USB.
//

import AppKit
import SwiftUI

struct MacOSStepProgressView: View {
    enum Step: Int, CaseIterable, Identifiable {
        case download
        case writeUSB

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .download: return String(localized: "Downloading")
            case .writeUSB: return String(localized: "Writing to USB")
            }
        }

        var subtitle: String {
            switch self {
            case .download: return String(localized: "Downloading the macOS installer into cache")
            case .writeUSB: return String(localized: "Formatting and writing the selected drives")
            }
        }

        var iconAssetName: String {
            switch self {
            case .download: return "FluffyIconDownloads"
            case .writeUSB: return "FluffyUSBDriveOriginal"
            }
        }
    }

    let e2e: MacOSEndToEndPipeline
    let usbWriter: MacOSUSBWriter
    let drives: [RemovableDriveInfo]

    @Binding var isPresentingLog: Bool
    let onCopyError: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(visibleSteps) { step in
                stepCard(step)
            }
        }
    }

    /// Determines which step cards are on screen at any given moment.
    /// During `.downloading` the user only sees the Download card so they cannot mistake
    /// the second card's idle state (and stray mist log lines) for a running write.
    private var visibleSteps: [Step] {
        switch e2e.phase {
        case .idle, .downloading:
            return [.download]
        case .writingUSB, .completed:
            return [.download, .writeUSB]
        case .failed:
            // On failure, show whichever steps the user already started, so the failed badge
            // is rendered on the right card.
            return wasWriting ? [.download, .writeUSB] : [.download]
        }
    }

    // MARK: - Step state mapping

    private enum StepState: Equatable {
        case pending
        case running
        case done
        case failed
    }

    private func currentStepState(_ step: Step) -> StepState {
        switch e2e.phase {
        case .idle:
            return .pending
        case .downloading:
            return (step == .download) ? .running : .pending
        case .writingUSB:
            if step == .download { return .done }
            if step == .writeUSB { return .running }
            return .pending
        case .completed:
            return .done
        case .failed:
            if step == .writeUSB, wasWriting { return .failed }
            if step == .download, wasDownloading { return .failed }
            if step.rawValue < failedStepIndex { return .done }
            return .pending
        }
    }

    private var wasDownloading: Bool {
        e2e.downloadProgress != nil || (e2e.downloadStatusLine?.isEmpty == false)
    }

    private var wasWriting: Bool {
        usbWriter.isWriting || (usbWriter.lastError?.isEmpty == false) || !usbWriter.logLines.isEmpty
    }

    private var failedStepIndex: Int {
        if wasWriting { return Step.writeUSB.rawValue }
        return Step.download.rawValue
    }

    // MARK: - UI

    @ViewBuilder
    private func stepCard(_ step: Step) -> some View {
        let state = currentStepState(step)
        let isFrozen = (state == .done || state == .failed)
        let isActive = state == .running

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                stepCenterpiece(step: step, state: state)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(step.title)
                        .font(WistFont.headlineRounded(15))
                    Text(step.subtitle)
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if state == .failed {
                        HStack(spacing: 10) {
                            Button {
                                isPresentingLog = true
                            } label: {
                                Label(String(localized: "View log"), systemImage: "doc.text.magnifyingglass")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                onCopyError()
                            } label: {
                                Label(String(localized: "Copy error"), systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 8)
            }

            switch step {
            case .download:
                downloadPanel(state: state)
            case .writeUSB:
                writePanel(state: state)
            }
        }
        .padding(16)
        .background(stepBackground(state: state))
        .overlay(stepOverlay(state: state))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if isFrozen { frozenGlassOverlay(state: state) }
        }
        .shadow(
            color: isActive ? FluffyColor.purpleGlow.opacity(0.32) : Color.black.opacity(0.18),
            radius: isActive ? 18 : 10,
            y: isActive ? 6 : 4
        )
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(FluffyColor.purpleGlow.opacity(0.22), lineWidth: 1.2)
                    .shadow(color: FluffyColor.purpleGlow.opacity(0.35), radius: 16)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
        }
    }

    private func stepCenterpiece(step: Step, state: StepState) -> some View {
        let slot: CGFloat = (state == .done) ? 80 : 74

        return Group {
            if state == .done {
                Image("FluffyIconDone")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(13)
            } else if state == .failed {
                Image("FluffyIconWarning")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(18)
            } else {
                Image(step.iconAssetName)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(20)
                    .opacity(state == .pending ? 0.45 : 0.92)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: slot, height: slot)
        .clipped()
        .shadow(color: Color.black.opacity(0.28), radius: 10, y: 4)
    }

    @ViewBuilder
    private func downloadPanel(state: StepState) -> some View {
        let label: String = {
            switch state {
            case .done: return String(localized: "Download complete.")
            case .failed: return String(localized: "Download failed.")
            case .pending: return String(localized: "Preparing download…")
            case .running:
                if let line = e2e.downloadActivityLine, !line.isEmpty {
                    return line
                }
                return String(localized: "Downloading…")
            }
        }()
        let progressValue: CGFloat? = {
            switch state {
            case .done: return 1.0
            case .failed: return e2e.downloadProgress.map { CGFloat($0) }
            case .pending: return 0.0
            case .running: return e2e.downloadProgress.map { CGFloat($0) }
            }
        }()
        let isCompleted = (state == .done)

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if isCompleted {
                    Text(String(localized: "Cached and ready."))
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else if let st = e2e.downloadStatusLine, !st.isEmpty {
                    Text(st)
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                } else {
                    Text(String(localized: "Waiting for download output…"))
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let eta = e2e.downloadEtaFormatted, !isCompleted {
                    Text(eta)
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                }
            }

            FluffyRopeProgressBar(
                value: progressValue,
                label: label,
                compactVertical: false
            )

            if state == .running, let started = e2e.downloadStartedAt {
                elapsedFooter(started: started)
            }
        }
        .opacity(state == .pending ? 0.55 : 1.0)
    }

    /// Once-per-second updating "Elapsed mm:ss" footer used on the active step card.
    @ViewBuilder
    private func elapsedFooter(started: Date) -> some View {
        TimelineView(.periodic(from: started, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(started)))
            let minutes = seconds / 60
            let secs = seconds % 60
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                Text(String(format: String(localized: "Elapsed %02d:%02d"), minutes, secs))
                    .font(WistFont.caption(10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func writePanel(state: StepState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(writeDetailLine(state: state))
                .font(WistFont.caption(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Keep write UI minimal; show log only on failure to avoid impacting throughput.
            if state == .failed {
                liveLogTail
                    .padding(.top, 2)
            }

            if state == .running, case .writingUSB(let current, let total) = e2e.phase, total > 0 {
                let driveLabel = String(format: String(localized: "%lld of %lld"), Int64(current), Int64(total))
                let sub = currentSubphase
                FluffyRopeProgressBar(
                    value: CGFloat(sub.fraction),
                    label: "\(sub.label)  •  \(driveLabel)",
                    compactVertical: false
                )
                // Resetting the view identity on subphase changes makes the bar visibly start
                // from 0% for each of Erase / Mount / createinstallmedia, instead of animating
                // backwards from a previous full bar.
                .id(sub.id)
            } else if state == .done {
                FluffyRopeProgressBar(value: 1.0, label: nil, compactVertical: false)
            } else if state == .failed {
                // Empty track — `nil` would shimmer and read as "still running".
                FluffyRopeProgressBar(value: 0, label: nil, compactVertical: false)
            } else {
                // Pending: explicit 0%, never indeterminate. The card is still on screen because
                // the parent's `visibleSteps` decided to show it (writing has begun or the run
                // already failed mid-write); the empty bar tells the user "this stage hasn't
                // produced output yet" rather than "something is happening".
                FluffyRopeProgressBar(value: 0, label: nil, compactVertical: false)
            }

            if state == .running, let started = e2e.writeStartedAt {
                elapsedFooter(started: started)
            }
        }
        .opacity(state == .pending ? 0.55 : 1.0)
    }

    private var liveLogTail: some View {
        let tail = usbWriter.logLines.suffix(80)
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(tail.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                    }
                }
                .padding(10)
            }
            .frame(maxHeight: 140)
            .background(Color.black.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onChange(of: usbWriter.logLines.count) { _, _ in
                // Auto-scroll to bottom as new lines arrive.
                if let last = tail.indices.last {
                    withAnimation(.linear(duration: 0.12)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private struct SubphaseProgress {
        let id: String
        let label: String
        let fraction: Double
    }

    /// One of three independent 0...1 progress slots, one per writer subphase. Each slot
    /// resets to 0 when the subphase becomes active, so the user sees the bar fill from
    /// scratch for Erase, then Mount, then createinstallmedia.
    private var currentSubphase: SubphaseProgress {
        switch usbWriter.phase {
        case .idle:
            return SubphaseProgress(id: "idle", label: String(localized: "Preparing…"), fraction: 0)
        case .erasingDisk:
            return SubphaseProgress(
                id: "erasing",
                label: String(localized: "Erasing disk…"),
                fraction: usbWriter.erasingProgress
            )
        case .waitingForMount:
            return SubphaseProgress(
                id: "mounting",
                label: String(localized: "Mounting volume…"),
                fraction: usbWriter.mountingProgress
            )
        case .runningCreateInstallMedia:
            return SubphaseProgress(
                id: "createinstallmedia",
                label: String(localized: "Writing installer…"),
                fraction: usbWriter.createInstallMediaProgress ?? 0
            )
        case .completed:
            return SubphaseProgress(id: "completed", label: String(localized: "Done."), fraction: 1.0)
        case .failed:
            return SubphaseProgress(id: "failed", label: String(localized: "Failed."), fraction: 0)
        }
    }

    private func writeDetailLine(state: StepState) -> String {
        switch state {
        case .running:
            if case .writingUSB(let current, let total) = e2e.phase, total > 0, let drive = drives[safe: current - 1] {
                let stepText: String = switch usbWriter.phase {
                case .erasingDisk: String(localized: "Erasing disk…")
                case .waitingForMount: String(localized: "Waiting for mount…")
                case .runningCreateInstallMedia: String(localized: "Running createinstallmedia…")
                case .completed: String(localized: "Done.")
                case .failed: String(localized: "Failed.")
                case .idle: String(localized: "Preparing…")
                }
                return "\(stepText)  •  " + String(format: String(localized: "Write %lld of %lld: %@"), Int64(current), Int64(total), drive.mediaName)
            }
            return String(localized: "Preparing…")
        case .pending:
            // Never echo the download status line here: it would duplicate raw mist output
            // into the second card and read as "writing is already happening".
            return String(localized: "Starts after the installer is downloaded.")
        case .done:
            return String(localized: "All selected drives finished.")
        case .failed:
            return String(localized: "One or more drives failed.")
        }
    }

    // MARK: - Styling borrowed from FluffyStepProgressView

    private func stepBackground(state: StepState) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(FluffyColor.surface.opacity(0.92))
            if state == .running {
                LinearGradient(
                    colors: [
                        FluffyColor.purpleGlow.opacity(0.16),
                        Color.clear,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private func stepOverlay(state: StepState) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(state == .running ? 0.14 : 0.09), lineWidth: 1)
    }

    private func frozenGlassOverlay(state: StepState) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.black.opacity(state == .failed ? 0.12 : 0.08))
            .allowsHitTesting(false)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}

