import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RopeProgressTestView: View {
    @State private var progress: CGFloat = 0.35
    @State private var thickness: Double = 22

    @State private var selectedImageURL: URL?
    @State private var isPickingImage = false

    @State private var lastLoadError: String?

    var body: some View {
        MistDetailCanvas {
            VStack(alignment: .leading, spacing: 0) {
                MistPageHeader(
                    eyebrow: "Lab",
                    title: "Rope progress (test)",
                    subtitle: "Experiment: a progress bar that fills along the \"coil\" using a texture from a single rope fragment (PNG/SVG).",
                    symbolName: "testtube.2",
                    assetName: "FluffyIconInfo"
                )
                .padding(WistTheme.pagePadding)
                .background(MistHeroBackground())

                Divider().opacity(0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: WistTheme.gutter) {
                        previewCard
                        controlsCard
                    }
                    .padding(WistTheme.pagePadding)
                }
            }
        }
        .fileImporter(
            isPresented: $isPickingImage,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                selectedImageURL = urls.first
                lastLoadError = nil
            case .failure(let err):
                lastLoadError = err.localizedDescription
            }
        }
    }

    private var ropeImage: Image? {
        guard let url = selectedImageURL else { return nil }
        guard let img = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: img)
    }

    private var ropeNSImage: NSImage? {
        guard let url = selectedImageURL else { return nil }
        return NSImage(contentsOf: url)
    }

    private var previewCard: some View {
        MistSectionCard(title: "Preview", systemImage: "waveform.path.ecg") {
            VStack(alignment: .leading, spacing: 12) {
                RopeProgressBar(
                    progress: progress,
                    thickness: thickness,
                    ropeImage: ropeNSImage
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)

                HStack(spacing: 10) {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(WistFont.caption(11).monospacedDigit())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        isPickingImage = true
                    } label: {
                        Label(selectedImageURL == nil ? "Choose Rope_part…" : "Change image…", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)

                    if selectedImageURL != nil {
                        Button {
                            selectedImageURL = nil
                            lastLoadError = nil
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }

                if let url = selectedImageURL {
                    Text(url.path)
                        .font(WistFont.caption(10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                } else {
                    Text("No file selected. You can choose `Rope_part.png` or `Rope_part.svg` from Downloads.")
                        .font(WistFont.caption(11))
                        .foregroundStyle(.secondary)
                }

                if ropeImage == nil, selectedImageURL != nil {
                    Text("Failed to load the image. If this is an SVG and it doesn't load via `NSImage`, try a PNG.")
                        .font(WistFont.caption(11))
                        .foregroundStyle(.orange)
                }

                if let lastLoadError {
                    Text(lastLoadError)
                        .font(WistFont.caption(11))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var controlsCard: some View {
        MistSectionCard(title: "Controls", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 14) {
                sliderRow(title: "Progress", valueText: "\(Int((progress * 100).rounded()))%") {
                    Slider(value: Binding(get: { Double(progress) }, set: { progress = CGFloat($0) }), in: 0...1)
                }

                sliderRow(title: "Thickness", valueText: "\(Int(thickness.rounded()))") {
                    Slider(value: $thickness, in: 12...38, step: 1)
                }
            }
        }
    }

    private func sliderRow<Content: View>(
        title: String,
        valueText: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(title)
                    .font(WistFont.headline(12))
                Spacer()
                Text(valueText)
                    .font(WistFont.caption(11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            content()
        }
    }
}

#Preview {
    RopeProgressTestView()
        .frame(width: 1040, height: 720)
        .preferredColorScheme(.dark)
}

