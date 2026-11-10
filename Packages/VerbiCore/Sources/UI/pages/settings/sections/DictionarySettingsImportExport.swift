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
            switch DictionaryArchive.validate(data: data) {
            case let .success(archive):
                let outcome = archive.merge(
                    into: settings.vocabularyTerms,
                    existingRules: settings.vocabularyReplacementRules
                )
                settings.vocabularyTerms = outcome.terms
                settings.vocabularyReplacementRules = outcome.rules
                vocabularyViewModel.reloadFromStore()
                importExportMessage = importResultMessage(
                    outcome.result,
                    conflictingOriginCount: VocabularySubstitutionGroup
                        .conflictingOriginKeys(in: outcome.rules)
                        .count
                )
            case let .failure(error):
                importExportMessage = "settings.dictionary.import.error_invalid".localized(with: error.localizedDescription)
            }
        } catch {
            importExportMessage = "settings.dictionary.import.error_read".localized(with: error.localizedDescription)
        }
        showImportExportAlert = true
    }

    private func importResultMessage(
        _ result: DictionaryArchive.ImportResult,
        conflictingOriginCount: Int
    ) -> String {
        var parts: [String] = []
        if result.termsImported > 0 {
            parts.append("settings.dictionary.import.result.terms".localized(with: result.termsImported))
        }
        if result.rulesImported > 0 {
            parts.append("settings.dictionary.import.result.rules".localized(with: result.rulesImported))
        }
        if result.totalDuplicates > 0 {
            parts.append("settings.dictionary.import.result.skipped".localized(with: result.totalDuplicates))
        }
        if conflictingOriginCount > 0 {
            parts.append("settings.dictionary.import.result.conflicts".localized(with: conflictingOriginCount))
        }
        if parts.isEmpty {
            return "settings.dictionary.import.result.nothing".localized
        }
        return parts.joined(separator: "\n")
    }
}
