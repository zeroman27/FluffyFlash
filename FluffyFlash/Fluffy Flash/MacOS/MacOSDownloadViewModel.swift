//
//  MacOSDownloadViewModel.swift
//  Wist
//

import Combine
import Foundation

@MainActor
final class MacOSDownloadViewModel: ObservableObject {
    enum SourceKind: String, CaseIterable, Identifiable {
        case installer
        case firmware
        case local

        var id: String { rawValue }

        var title: String {
            switch self {
            case .installer: return String(localized: "Installer")
            case .firmware: return String(localized: "Firmware (IPSW)")
            case .local: return String(localized: "Local file")
            }
        }
    }

    @Published var sourceKind: SourceKind = .installer
    @Published var includeBetas: Bool = false
    @Published var selectedCatalog: MistCLITool.Catalog = .standard

    @Published private(set) var installers: [MistCLITool.InstallerListItem] = []
    @Published private(set) var firmwares: [MistCLITool.FirmwareListItem] = []

    @Published var selectedInstaller: MistCLITool.InstallerListItem?
    @Published var selectedFirmware: MistCLITool.FirmwareListItem?

    @Published var installerOutputTypes: Set<MistCLITool.InstallerOutputType> = [.application]

    @Published private(set) var isLoadingList: Bool = false
    @Published private(set) var lastError: String?

    /// Drives SwiftUI `.task(id:)` so the catalog list prefetches when Home (macOS) appears and when list-affecting options change.
    var catalogAutoRefreshTaskID: String {
        switch sourceKind {
        case .installer:
            return "installer|\(selectedCatalog.rawValue)|\(includeBetas)"
        case .firmware:
            return "firmware|\(includeBetas)"
        case .local:
            return "local"
        }
    }

    func refreshList() async {
        guard sourceKind != .local else { return }

        lastError = nil
        isLoadingList = true
        defer { isLoadingList = false }

        do {
            try FileManager.default.createDirectory(at: MacOSCache.rootDirectory, withIntermediateDirectories: true)
            let exportURL = MacOSCache.rootDirectory.appendingPathComponent("mist-list-\(sourceKind.rawValue).json")

            if sourceKind == .installer {
                installers = try await MistCLITool.listInstallers(
                    exportURL: exportURL,
                    includeBetas: includeBetas,
                    catalog: selectedCatalog
                )
                reconcileInstallerSelection()
            } else {
                firmwares = try await MistCLITool.listFirmwares(
                    exportURL: exportURL,
                    includeBetas: includeBetas
                )
                reconcileFirmwareSelection()
            }
        } catch is CancellationError {
            // SwiftUI cancels `.task` when identity changes or the view is torn down; do not treat as a catalog error.
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func reconcileInstallerSelection() {
        guard let sel = selectedInstaller else { return }
        if let match = installers.first(where: { $0.build == sel.build }) {
            selectedInstaller = match
        } else {
            selectedInstaller = nil
        }
    }

    private func reconcileFirmwareSelection() {
        guard let sel = selectedFirmware else { return }
        if let match = firmwares.first(where: { $0.build == sel.build }) {
            selectedFirmware = match
        } else {
            selectedFirmware = nil
        }
    }
}

