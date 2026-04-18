//
//  WorkflowBottomBar.swift
//  Wist
//
//  Fixed primary CTA strip (Raycast-style) for the end-to-end workflow.
//

import SwiftUI

struct WorkflowBottomBar: View {
    let statusLine: String
    let pipelinePhase: EndToEndMediaPipeline.Phase
    let canRunFullPipeline: Bool
    let isDownloadBusy: Bool
    let isConvertBusy: Bool
    /// Explains why Run all is unavailable when prerequisites aren’t met (shown as tooltip on macOS).
    let primaryActionDisabledHint: String?
    let onRunFullPipeline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !statusLine.isEmpty {
                Text(statusLine)
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            HStack(spacing: 12) {
                Button {
                    onRunFullPipeline()
                } label: {
                    Label(String(localized: "Run all"), systemImage: "bolt.horizontal.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(primaryButtonDisabled)
                .help(primaryButtonHelpText)

                if pipelineBlocksPrimary {
                    MistProProgressIndeterminate(height: 4, label: nil)
                        .frame(maxWidth: 200)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, WistTheme.pagePadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                WistTheme.rayDarkBottom.opacity(0.88)
                Rectangle()
                    .fill(WistTheme.surfaceElevated.opacity(0.35))
                WistTheme.mistVioletTint.opacity(0.12)
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.38),
                        Color.black.opacity(0.06),
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .opacity(0.8)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(WistTheme.hairline)
                .frame(height: 1)
        }
    }

    private var pipelineBlocksPrimary: Bool {
        switch pipelinePhase {
        case .idle, .completed, .failed:
            return false
        case .downloadingUUP, .convertingToISO, .writingUSB:
            return true
        }
    }

    private var primaryButtonDisabled: Bool {
        !canRunFullPipeline || pipelineBlocksPrimary || isDownloadBusy || isConvertBusy
    }

    private var primaryButtonHelpText: String {
        guard primaryButtonDisabled else { return "" }
        if pipelineBlocksPrimary {
            return String(localized: "The pipeline is running. Wait for the current step to finish.")
        }
        if isDownloadBusy {
            return String(localized: "Wait for the download to finish before running the full pipeline.")
        }
        if isConvertBusy {
            return String(localized: "Wait for ISO conversion to finish before running the full pipeline.")
        }
        if let primaryActionDisabledHint, !primaryActionDisabledHint.isEmpty {
            return primaryActionDisabledHint
        }
        return String(localized: "This action is not available yet.")
    }
}
