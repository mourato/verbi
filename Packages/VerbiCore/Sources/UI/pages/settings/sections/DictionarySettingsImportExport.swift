import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

extension DictionarySettingsPage {
    var importExportSection: some View {
        Section {
            HStack(spacing: 12) {
                Button("settings.dictionary.export".localized) {
                    exportDictionary()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button("settings.dictionary.import".localized) {
                    importDictionary()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()
            }
        } header: {
            SettingsFormSectionHeader(
                title: "settings.dictionary.import_export".localized,
                icon: "arrow.up.arrow.down"
            )
        }
    }

    private func exportDictionary() {
        let archive = DictionaryArchive(
            vocabularyTerms: settings.vocabularyTerms,
            substitutionRules: settings.vocabularyReplacementRules
        )

        guard let data = try? JSONEncoder().encode(archive) else {
            importExportMessage = "settings.dictionary.export.error_encode".localized
            showImportExportAlert = true
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.json]
        panel.nameFieldStringValue = "\(AppIdentity.displayName.lowercased())-dictionary-export.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url, options: .atomic)
            importExportMessage = "settings.dictionary.export.success".localized
        } catch {
            importExportMessage = "settings.dictionary.export.error_write".localized(with: error.localizedDescription)
        }
        showImportExportAlert = true
    }

    private func importDictionary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let coordinator = DictionaryImportCoordinator()
            importPreview = try coordinator.prepareImportPreview(from: data, store: settings)
        } catch let error as DictionaryArchiveError {
            importExportMessage = "settings.dictionary.import.error_invalid".localized(with: error.localizedDescription)
            showImportExportAlert = true
        } catch {
            importExportMessage = "settings.dictionary.import.error_read".localized(with: error.localizedDescription)
            showImportExportAlert = true
        }
    }

    func confirmImport(preview: DictionaryImportPreview) {
        let coordinator = DictionaryImportCoordinator()
        do {
            let result = try coordinator.confirmImport(preview: preview, into: settings)
            vocabularyViewModel.reloadFromStore()
            importPreview = nil

            importExportMessage = importPreviewSuccessMessage(
                termsImported: result.importedTermsCount,
                variantsImported: result.importedVariantsCount,
                duplicates: result.duplicatesCount,
                conflicts: result.conflictsCount
            )
            showImportExportAlert = true
        } catch let error as DictionaryImportError {
            importPreview = nil
            importExportMessage = error.errorDescription ?? error.localizedDescription
            showImportExportAlert = true
        } catch {
            importPreview = nil
            importExportMessage = error.localizedDescription
            showImportExportAlert = true
        }
    }

    private func importPreviewSuccessMessage(
        termsImported: Int,
        variantsImported: Int,
        duplicates: Int,
        conflicts: Int
    ) -> String {
        var parts: [String] = []
        if termsImported > 0 {
            parts.append("settings.dictionary.import.result.terms".localized(with: termsImported))
        }
        if variantsImported > 0 {
            parts.append("settings.dictionary.import.result.variants".localized(with: variantsImported))
        }
        if duplicates > 0 {
            parts.append("settings.dictionary.import.result.skipped".localized(with: duplicates))
        }
        if conflicts > 0 {
            parts.append("settings.dictionary.import.result.conflicts_preserved".localized(with: conflicts))
        }
        if parts.isEmpty {
            return "settings.dictionary.import.result.nothing".localized
        }
        return parts.joined(separator: " ")
    }
}
