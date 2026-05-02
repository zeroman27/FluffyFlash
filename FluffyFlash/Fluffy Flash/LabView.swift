//
//  LabView.swift
//  Wist
//

import SwiftUI

#if DEBUG
struct LabView: View {
    var body: some View {
        #if LAB_LOCAL
        LabExperimentsView()
        #else
        MistDetailCanvas {
            VStack(alignment: .leading, spacing: 0) {
                MistPageHeader(
                    eyebrow: "Lab",
                    title: "Internal only",
                    subtitle: "Enable LAB_LOCAL to load local experiments.",
                    symbolName: "testtube.2",
                    assetName: "FluffyIconInfo"
                )
                .padding(WistTheme.pagePadding)
                .background(MistHeroBackground())

                Divider().opacity(0.5)

                MistSectionCard(title: "Lab is disabled", systemImage: "lock.fill") {
                    Text("This screen is intentionally kept out of git. Add experiments in LabExperiments.local.swift and enable the LAB_LOCAL compilation condition in Debug.")
                        .font(WistFont.body(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(WistTheme.pagePadding)

                Spacer(minLength: 0)
            }
        }
        #endif
    }
}

#Preview {
    LabView()
        .frame(width: 1040, height: 720)
        .preferredColorScheme(.dark)
}
#endif

