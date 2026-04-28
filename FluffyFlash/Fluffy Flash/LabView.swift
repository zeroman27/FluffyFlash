//
//  LabView.swift
//  Wist
//

import SwiftUI

#if DEBUG
struct LabView: View {
    enum LabTab: String, CaseIterable, Identifiable {
        case modeDial
        case rope

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .modeDial: return "Mode Dial"
            case .rope: return "Rope progress"
            }
        }
    }

    @State private var tab: LabTab = .modeDial
    @State private var demoMode: AppMode = .windows

    var body: some View {
        MistDetailCanvas {
            VStack(alignment: .leading, spacing: 0) {
                MistPageHeader(
                    eyebrow: "Lab",
                    title: "Experiments",
                    subtitle: "UI prototypes and motion tests.",
                    symbolName: "testtube.2",
                    assetName: "FluffyIconInfo"
                )
                .padding(WistTheme.pagePadding)
                .background(MistHeroBackground())

                Divider().opacity(0.5)

                Picker(String(localized: "Lab section"), selection: $tab) {
                    ForEach(LabTab.allCases) { t in
                        Text(t.title).tag(t)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .padding(.horizontal, WistTheme.pagePadding)
                .padding(.top, WistTheme.gutter)

                ScrollView {
                    VStack(alignment: .leading, spacing: WistTheme.gutter) {
                        switch tab {
                        case .modeDial:
                            modeDialSection
                        case .rope:
                            RopeProgressTestView()
                        }
                    }
                    .padding(WistTheme.pagePadding)
                }
            }
        }
    }

    private var modeDialSection: some View {
        MistSectionCard(title: "ModeDial variants", systemImage: "dial.medium") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tap or drag the dial. This is a live prototype.")
                    .font(WistFont.caption(11))
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    ModeDial(mode: $demoMode, size: 92, variant: .variantA)
                    ModeDial(mode: $demoMode, size: 92, variant: .variantB)
                    ModeDial(mode: $demoMode, size: 92, variant: .variantC)
                    Spacer()
                }

                Text("Selected: \(demoMode.title)")
                    .font(WistFont.caption(11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    LabView()
        .frame(width: 1040, height: 720)
        .preferredColorScheme(.dark)
}
#endif

