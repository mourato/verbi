import CoreData
import Foundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
@testable import MeetingAssistantCoreUI
import XCTest

final class TranscriptionHistoryPerformanceTests: XCTestCase {
    private let datasetSizes = [50, 250, 1_000]
    private let measurementSamples = 3

    func testPerformance_HistoryQueryAndFilteringBaseline() async throws {
        for size in datasetSizes {
            let fixture = try await HistoryPerformanceFixture.make(size: size)
            let allQuery = TranscriptionMetadataQuery(limit: nil)

            _ = try await fixture.storage.loadMetadata(matching: allQuery)

            var queryDurations: [TimeInterval] = []
            var metadata: [TranscriptionMetadata] = []
            for _ in 0..<measurementSamples {
                let start = Date()
                metadata = try await fixture.storage.loadMetadata(matching: allQuery)
                queryDurations.append(Date().timeIntervalSince(start))
            }

            XCTAssertEqual(metadata.count, size)

            let filtered = TranscriptionHistoryFilterEngine.filteredTranscriptions(
                from: metadata,
                configuration: .init(
                    capturePurposeFilter: .meetings,
                    dateFilter: .allEntries,
                    searchText: "needle",
                    appFilterId: "raw:zoom",
                    allAppsId: "__all_apps__",
                    rawAppPrefix: "raw:",
                    bundleAppPrefix: "bundle:",
                    nameAppPrefix: "name:",
                ),
            )
            XCTAssertEqual(filtered.count, fixture.expectedFilteredCount)

            var filterDurations: [TimeInterval] = []
            for _ in 0..<measurementSamples {
                let start = Date()
                let result = TranscriptionHistoryFilterEngine.filteredTranscriptions(
                    from: metadata,
                    configuration: .init(
                        capturePurposeFilter: .meetings,
                        dateFilter: .allEntries,
                        searchText: "needle",
                        appFilterId: "raw:zoom",
                        allAppsId: "__all_apps__",
                        rawAppPrefix: "raw:",
                        bundleAppPrefix: "bundle:",
                        nameAppPrefix: "name:",
                    ),
                )
                filterDurations.append(Date().timeIntervalSince(start))
                XCTAssertEqual(result.count, fixture.expectedFilteredCount)
            }

            let queryAverage = milliseconds(average(queryDurations))
            let queryMinimum = milliseconds(queryDurations.min() ?? 0)
            let filterAverage = milliseconds(average(filterDurations))
            let filterMinimum = milliseconds(filterDurations.min() ?? 0)
            print(
                "HISTORY_PERF_BASELINE dataset=\(size) "
                    + "query_mapping_ms_avg=\(queryAverage) "
                    + "query_mapping_ms_min=\(queryMinimum) "
                    + "filter_ms_avg=\(filterAverage) "
                    + "filter_ms_min=\(filterMinimum) "
                    + "filtered_rows=\(filtered.count)",
            )
        }
    }

    @MainActor
    func testPerformance_ViewModelReloadCountBaseline() async {
        let storage = MockStorageService()
        storage.mockTranscriptions = (0..<250).map(Self.makeMockTranscription)
        let viewModel = TranscriptionLibraryViewModel(storage: storage)

        let start = Date()
        for _ in 0..<measurementSamples {
            await viewModel.loadTranscriptions()
        }
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(storage.loadMetadataCallCount, measurementSamples)
        XCTAssertEqual(storage.loadAllMetadataCallCount, 0)
        XCTAssertEqual(viewModel.transcriptions.count, 250)

        print(
            "HISTORY_PERF_BASELINE "
                + "dataset=250 "
                + "view_model_reload_count=\(storage.loadMetadataCallCount) "
                + "view_model_reload_ms_total=\(milliseconds(elapsed))",
        )
    }

    func testHistoryFilterFixtureCoversSourceAppAndSearch() async throws {
        let fixture = try await HistoryPerformanceFixture.make(size: 250)
        let metadata = try await fixture.storage.loadMetadata(matching: TranscriptionMetadataQuery(limit: nil))

        let filtered = TranscriptionHistoryFilterEngine.filteredTranscriptions(
            from: metadata,
            configuration: .init(
                capturePurposeFilter: .meetings,
                dateFilter: .allEntries,
                searchText: "needle",
                appFilterId: "raw:zoom",
                allAppsId: "__all_apps__",
                rawAppPrefix: "raw:",
                bundleAppPrefix: "bundle:",
                nameAppPrefix: "name:",
            ),
        )

        XCTAssertEqual(filtered.count, fixture.expectedFilteredCount)
        XCTAssertTrue(filtered.allSatisfy { $0.capturePurpose == .meeting })
        XCTAssertTrue(filtered.allSatisfy { $0.appRawValue == "zoom" })
        XCTAssertTrue(filtered.allSatisfy { $0.previewText.localizedCaseInsensitiveContains("needle") })
    }

    private static func makeMockTranscription(index: Int) -> CaptureArtifact {
        let id = HistoryPerformanceFixture.identifier(for: index)
        let meeting = CaptureSession(
            id: id,
            app: .zoom,
            startTime: Date(timeIntervalSince1970: TimeInterval(index)),
            endTime: Date(timeIntervalSince1970: TimeInterval(index + 60)),
        )
        return CaptureArtifact(
            id: id,
            meeting: meeting,
            segments: [],
            text: "History item \(index)",
            rawText: "History item \(index)",
        )
    }

    private func average(_ values: [TimeInterval]) -> TimeInterval {
        values.reduce(0, +) / Double(values.count)
    }

    private func milliseconds(_ value: TimeInterval) -> String {
        String(format: "%.3f", value * 1_000)
    }
}

private struct HistoryPerformanceFixture {
    let storage: FileSystemStorageService
    let expectedFilteredCount: Int

    static func make(size: Int) async throws -> HistoryPerformanceFixture {
        let stack = CoreDataStack(name: "HistoryPerformance-\(size)", inMemory: true)
        let storage = FileSystemStorageService(
            honorsConfiguredRecordingDirectory: false,
            coreDataStack: stack,
        )

        try await stack.performBackgroundTask { context in
            for index in 0..<size {
                let id = identifier(for: index)
                let app: CaptureOrigin = index.isMultiple(of: 3) ? .zoom : .slack
                let capturePurpose: CapturePurpose = index.isMultiple(of: 4) ? .meeting : .dictation
                let includesSearchTerm = index.isMultiple(of: 10)
                let text = includesSearchTerm
                    ? "Needle result \(index)"
                    : "Regular transcription result \(index)"
                let date = Date(timeIntervalSince1970: TimeInterval(index + 1_700_000_000))
                let meeting = CaptureSessionEntity(
                    id: id,
                    app: app,
                    capturePurpose: capturePurpose,
                    appDisplayName: app == .zoom ? "Zoom" : "Slack",
                    title: capturePurpose == .meeting ? "Meeting \(index)" : nil,
                    startTime: date,
                    endTime: date.addingTimeInterval(60),
                )
                var configuration = CaptureArtifactEntity.Configuration(text: text, rawText: text)
                configuration.id = id
                configuration.createdAt = date
                configuration.lifecycleState = .completed
                configuration.inputSource = "Microphone"
                let transcription = CaptureArtifactEntity(meeting: meeting, config: configuration)
                let meetingMO = CaptureSessionMO.create(from: meeting, in: context)
                _ = CaptureArtifactMO.create(from: transcription, meeting: meetingMO, in: context)
            }
            try context.save()
        }

        let expectedFilteredCount = (size + 59) / 60
        return HistoryPerformanceFixture(storage: storage, expectedFilteredCount: expectedFilteredCount)
    }

    static func identifier(for index: Int) -> UUID {
        guard let identifier = UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", index + 1))") else {
            preconditionFailure("Performance fixture identifier must be valid")
        }
        return identifier
    }
}
