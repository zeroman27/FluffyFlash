//
//  FluffyPerDriveStrip.swift
//  Fluffy Flash
//
//  Compact progress strip per active USB write. Lives below the high-level
//  FluffyStepProgressView when the user is flashing more than one drive at a
//  time, so each drive has its own status row with throughput and ETA.
//

import SwiftUI

struct FluffyPerDriveStrip: View {
    @ObservedObject var usbWriter: USBWriterViewModel
    let drives: [RemovableDriveInfo]

    private static let bytesFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f
    }()

    var body: some View {
        if drives.count > 1 {
            MistSectionCard(title: String(localized: "Per-drive progress"), systemImage: "list.bullet.rectangle") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(drives, id: \.deviceIdentifier) { drive in
                        row(for: drive)
                    }
                }
            }
        } else {
            EmptyView()
        }
    }

    private func row(for drive: RemovableDriveInfo) -> some View {
        let progress = usbWriter.perDriveProgress[drive.deviceIdentifier]
        let stepText = progress?.step.title ?? String(localized: "Waiting…")
        let percent = progress.map { Int(($0.stepProgress * 100).rounded()) } ?? 0
        let mbps = progress?.stepBytesPerSecond ?? 0
        let etaText = progress?.stepEtaSeconds.flatMap { USBWriterViewModel.formatETA(seconds: $0) }

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(drive.mediaName)
                    .font(WistFont.headline(12))
                    .lineLimit(1)
                Text(stepText)
                    .font(WistFont.caption(10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: 220, alignment: .leading)

            FluffyRopeProgressBar(
                value: progress.map { CGFloat($0.stepProgress) },
                label: nil,
                compactVertical: true
            )
            .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                if mbps > 0 {
                    Text("\(Self.bytesFormatter.string(fromByteCount: Int64(mbps)))/s")
                        .font(WistFont.caption(10).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let etaText {
                    Text(etaText)
                        .font(WistFont.caption(10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Text("\(percent)%")
                    .font(WistFont.caption(10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.8)
        }
    }
}

