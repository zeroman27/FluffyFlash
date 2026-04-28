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
            ForEach(Step.allCases) { step in
                stepCard(step)
            }
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
        let label = e2e.statusLine.isEmpty ? String(localized: "Downloading…") : e2e.statusLine

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let st = e2e.downloadStatusLine, !st.isEmpty {
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
                if let eta = e2e.downloadEtaFormatted {
                    Text(eta)
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                }
            }

            FluffyRopeProgressBar(
                value: e2e.downloadProgress.map { CGFloat($0) },
                label: label,
                compactVertical: false
            )
        }
        .opacity(state == .pending ? 0.55 : 1.0)
    }

    @ViewBuilder
    private func writePanel(state: StepState) -> some View {
        let title = e2e.statusLine.isEmpty ? String(localized: "Writing…") : e2e.statusLine

        VStack(alignment: .leading, spacing: 8) {
            Text(writeDetailLine(fallback: title))
                .font(WistFont.caption(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if state == .running, case .writingUSB(let current, let total) = e2e.phase, total > 0 {
                let sub = usbWriterSubprogress
                // `current` is 1-based (Write 1 of N). Convert to 0-based completed drives plus sub-progress.
                let completed = max(0, current - 1)
                let progress = min(1.0, (Double(completed) + sub) / Double(total))
                FluffyRopeProgressBar(
                    value: CGFloat(progress),
                    label: String(format: String(localized: "%lld of %lld"), Int64(current), Int64(total)),
                    compactVertical: false
                )
            } else if state == .done {
                FluffyRopeProgressBar(value: 1.0, label: nil, compactVertical: false)
            } else {
                FluffyRopeProgressBar(value: nil, label: nil, compactVertical: false)
            }
        }
        .opacity(state == .pending ? 0.55 : 1.0)
    }

    private var usbWriterSubprogress: Double {
        switch usbWriter.phase {
        case .idle:
            return 0.0
        case .erasingDisk:
            return 0.20
        case .waitingForMount:
            return 0.45
        case .runningCreateInstallMedia:
            return 0.70
        case .completed:
            return 1.0
        case .failed:
            return 0.70
        }
    }

    private func writeDetailLine(fallback: String) -> String {
        if case .writingUSB(let current, let total) = e2e.phase, total > 0, let drive = drives[safe: current - 1] {
            let stepText: String = switch usbWriter.phase {
            case .erasingDisk: String(localized: "Erasing disk…")
            case .waitingForMount: String(localized: "Waiting for mount…")
            case .runningCreateInstallMedia: String(localized: "Running createinstallmedia…")
            case .completed: String(localized: "Done.")
            case .failed: String(localized: "Failed.")
            case .idle: fallback
            }
            return "\(stepText)  •  " + String(format: String(localized: "Write %lld of %lld: %@"), Int64(current), Int64(total), drive.mediaName)
        }
        return fallback
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

