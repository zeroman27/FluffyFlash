//
//  FluffyStepProgressView.swift
//  Fluffy Flash
//
//  3-step running UI: Download UUP → Build ISO → Write USB.
//

import AppKit
import SwiftUI

struct FluffyStepProgressView: View {
    enum Step: Int, CaseIterable, Identifiable {
        case download
        case buildISO
        case writeUSB

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .download: return String(localized: "Downloading")
            case .buildISO: return String(localized: "Building ISO")
            case .writeUSB: return String(localized: "Writing to USB")
            }
        }

        var subtitle: String {
            switch self {
            case .download: return String(localized: "Fetching UUP files into cache")
            case .buildISO: return String(localized: "Converting cached UUP into an ISO")
            case .writeUSB: return String(localized: "Formatting and writing the selected drives")
            }
        }
    }

    let downloadModel: DownloadISOViewModel
    let usbWriter: USBWriterViewModel
    let e2e: EndToEndMediaPipeline
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
        case .downloadingUUP:
            if step == .download { return .running }
            return .pending
        case .convertingToISO:
            if step == .download { return .done }
            if step == .buildISO { return .running }
            return .pending
        case .writingUSB:
            if step == .download { return .done }
            if step == .buildISO { return .done }
            if step == .writeUSB { return .running }
            return .pending
        case .completed:
            return .done
        case .failed:
            // Mark the current/active step as failed, previous ones as done.
            if step == .writeUSB, wasWriting {
                return .failed
            }
            if step == .buildISO, wasBuilding {
                return .failed
            }
            if step == .download, wasDownloading {
                return .failed
            }
            // Otherwise treat as done/pending based on ordering.
            if step.rawValue < failedStepIndex { return .done }
            return .pending
        }
    }

    private var wasDownloading: Bool {
        downloadModel.isDownloading || downloadModel.downloadProgress != nil
    }

    private var wasBuilding: Bool {
        downloadModel.isConvertingUUP || downloadModel.lastProducedISOPath != nil
    }

    private var wasWriting: Bool {
        usbWriter.isWriting || !e2e.usbWriteStatuses.isEmpty
    }

    private var failedStepIndex: Int {
        if wasWriting { return Step.writeUSB.rawValue }
        if wasBuilding { return Step.buildISO.rawValue }
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
            case .buildISO:
                buildPanel(state: state)
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
        // No circular progress here: just the step icon. For Done we use a slightly larger slot
        // and tighter inner padding so the checkmark reads bigger (the progress bar is below).
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
                Image(step == .writeUSB ? "FluffyUSBDriveOriginal" : "FluffyIconDownloads")
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
        VStack(alignment: .leading, spacing: 8) {
            if state == .running {
                FluffyOrangeProgressBar(value: downloadModel.downloadProgress)
                HStack(spacing: 10) {
                    Text(downloadModel.downloadStatus ?? "")
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let eta = downloadModel.downloadEtaFormatted, !eta.isEmpty {
                        Text(eta)
                            .font(WistFont.caption(11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } else if state == .done {
                FluffyOrangeProgressBar(value: 1.0)
                Text(String(localized: "UUP download completed."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
            } else if state == .failed {
                Text((downloadModel.lastError ?? "").isEmpty ? String(localized: "Download failed.") : (downloadModel.lastError ?? ""))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else {
                Text(String(localized: "Ready to download."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func buildPanel(state: StepState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if state == .running {
                FluffyOrangeProgressBar(value: nil)
                Text(String(localized: "Converting cached UUP into an ISO…"))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
            } else if state == .done {
                FluffyOrangeProgressBar(value: 1.0)
                Text(String(localized: "ISO built successfully."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
            } else if state == .failed {
                Text((downloadModel.convertLastError ?? "").isEmpty ? String(localized: "ISO build failed.") : (downloadModel.convertLastError ?? ""))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            } else {
                Text(String(localized: "Waiting for download."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private func writePanel(state: StepState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if state == .running, case .writingUSB(let current, let total) = e2e.phase, total > 0 {
                let overall = overallUSBProgress(current: current, total: total)
                FluffyOrangeProgressBar(value: overall)
                HStack(spacing: 10) {
                    Text(String(format: String(localized: "Writing %lld of %lld"), Int64(current), Int64(total)))
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let active = activeDriveDetailText {
                        Text(active)
                            .font(WistFont.caption(11).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else if state == .done {
                FluffyOrangeProgressBar(value: 1.0)
                Text(String(localized: "All selected drives finished."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
            } else if state == .failed {
                // Empty track — `nil` would show indeterminate (full rope + shimmer) and reads as “already running”.
                FluffyOrangeProgressBar(value: 0)
                Text(String(localized: "One or more drives failed."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
            } else {
                // Pending: no indeterminate shimmer here; that step is not active yet.
                FluffyOrangeProgressBar(value: 0)
                Text(String(localized: "Waiting for ISO build."))
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(drives) { drive in
                    perDriveRow(drive)
                }
            }
        }
        .padding(12)
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func perDriveRow(_ drive: RemovableDriveInfo) -> some View {
        let status = e2e.usbWriteStatuses[drive.deviceIdentifier] ?? .queued
        let progress = usbWriter.perDriveProgress[drive.deviceIdentifier]
        return HStack(spacing: 10) {
            Image(FluffyUSBIconStyle.resolve(rawValue: UserDefaults.standard.string(forKey: FluffyUSBIconStyle.appStorageKey)).assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 34, height: 34)
                .opacity(0.95)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(drive.mediaName)
                    .font(WistFont.headline(12))
                    .lineLimit(1)
                Text("/dev/\(drive.deviceIdentifier)")
                    .font(WistFont.caption(10).monospacedDigit())
                    .foregroundStyle(.secondary)
                if let p = progress, status == .writing {
                    Text(p.detailLine)
                        .font(WistFont.caption(9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            statusPill(status)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func statusPill(_ status: EndToEndMediaPipeline.USBWriteJobStatus) -> some View {
        let text: String
        let color: Color
        switch status {
        case .queued:
            text = String(localized: "Queued")
            color = Color.white.opacity(0.22)
        case .writing:
            text = String(localized: "Writing")
            color = FluffyColor.purpleGlow.opacity(0.7)
        case .done:
            text = String(localized: "Done")
            color = Color.green.opacity(0.55)
        case .failed:
            text = String(localized: "Failed")
            color = Color.red.opacity(0.55)
        }
        return Text(text)
            .font(WistFont.caption(10).weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(color))
            .foregroundStyle(Color.white.opacity(0.95))
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(
                colors: [
                    FluffyColor.surface.opacity(0.85),
                    FluffyColor.elevated.opacity(0.78),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
    }

    private func stepBackground(state: StepState) -> LinearGradient {
        if state == .failed {
            return LinearGradient(
                colors: [
                    Color.red.opacity(0.22),
                    FluffyColor.elevated.opacity(0.85),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                FluffyColor.surface.opacity(0.92),
                FluffyColor.elevated.opacity(0.84),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func stepOverlay(state: StepState) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(
                state == .failed
                    ? Color.red.opacity(0.35)
                    : Color.white.opacity(0.10),
                lineWidth: 1
            )
    }

    private func frozenGlassOverlay(state: StepState) -> some View {
        // “Matte glass” placed on top after completion/failure.
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(state == .failed ? 0.22 : 0.18)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private func overallUSBProgress(current: Int, total: Int) -> Double? {
        guard total > 0 else { return nil }
        let doneCount = max(0, min(total, current - 1))

        // Prefer the first actively writing drive's progress.
        let writingDrive = drives.first { (e2e.usbWriteStatuses[$0.deviceIdentifier] ?? .queued) == .writing }
        let activeP = writingDrive.flatMap { usbWriter.perDriveProgress[$0.deviceIdentifier]?.overallProgress } ?? 0

        let overall = (Double(doneCount) + activeP) / Double(total)
        return max(0, min(1, overall))
    }

    private var activeDriveDetailText: String? {
        guard let writingDrive = drives.first(where: { (e2e.usbWriteStatuses[$0.deviceIdentifier] ?? .queued) == .writing }),
              let p = usbWriter.perDriveProgress[writingDrive.deviceIdentifier]
        else { return nil }
        if let eta = p.overallEtaSeconds, let etaS = USBWriterViewModel.formatETA(seconds: eta) {
            return "\(Int((p.overallProgress * 100).rounded()))% · ETA \(etaS)"
        }
        return "\(Int((p.overallProgress * 100).rounded()))% · \(p.step.title)"
    }
}

private extension USBWriterViewModel.DriveProgress {
    var detailLine: String {
        let base: String
        if let detail, !detail.isEmpty {
            base = "\(step.title) · \(detail)"
        } else {
            base = step.title
        }
        if let eta = overallEtaSeconds, let etaS = USBWriterViewModel.formatETA(seconds: eta) {
            return "\(base) · ETA \(etaS)"
        }
        return base
    }
}

