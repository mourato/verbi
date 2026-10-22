import CoreData
import Foundation
import VerbiCoreDomain

// CaptureArtifactMO - Managed Object para CaptureArtifactEntity
// Modelo CoreData thread-safe seguindo Clean Architecture

/// Managed Object para entidade CaptureArtifact
@objc(TranscriptionMO)
public final class CaptureArtifactMO: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var text: String
    @NSManaged public var rawText: String
    @NSManaged public var processedContent: String?
    @NSManaged public var postProcessingPromptId: UUID?
    @NSManaged public var postProcessingPromptTitle: String?
    @NSManaged public var postProcessingRequestSystemPrompt: String?
    @NSManaged public var postProcessingRequestUserPrompt: String?
    @NSManaged public var language: String
    @NSManaged public var createdAt: Date
    @NSManaged public var modelName: String

    // New Metadata Fields
    @NSManaged public var inputSource: String?
    @NSManaged public var transcriptionDuration: Double
    @NSManaged public var postProcessingDuration: Double
    @NSManaged public var postProcessingModel: String?
    @NSManaged public var postProcessingFailureReason: String?
    @NSManaged public var postProcessingOutputStateRawValue: String?
    @NSManaged public var transcriptionFailureReason: String?
    @NSManaged public var meetingType: String?
    @NSManaged public var lifecycleStateRawValue: String
    @NSManaged public var meetingConversationStateData: Data?
    @NSManaged public var contextItemsData: Data?
    @NSManaged public var canonicalSummaryData: Data?
    @NSManaged public var transcriptionQualityData: Data?
    @NSManaged public var executionProvenanceData: Data?
    @NSManaged public var canonicalSummarySchemaVersion: Int16
    @NSManaged public var summaryGroundedInTranscript: Bool
    @NSManaged public var summaryContainsSpeculation: Bool
    @NSManaged public var summaryHumanReviewed: Bool
    @NSManaged public var summaryConfidenceScore: Double
    @NSManaged public var transcriptConfidenceScore: Double
    @NSManaged public var transcriptContainsUncertainty: Bool

    // Relacionamentos
    @NSManaged public var meeting: CaptureSessionMO
    @NSManaged public var segments: Set<CaptureArtifactSegmentMO>
    @NSManaged public var performanceAttempts: Set<ModelPerformanceAttemptMO>
}

// MARK: - Fetch Requests

public extension CaptureArtifactMO {
    static let mockArtifactDefaultText = "Mock transcription text"
    static let mockArtifactDefaultModel = "mock-model"

    /// Fetch request para buscar todas as transcrições ordenadas por data
    @nonobjc class func fetchRequest() -> NSFetchRequest<CaptureArtifactMO> {
        let request = NSFetchRequest<CaptureArtifactMO>(entityName: "TranscriptionMO")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return request
    }

    @nonobjc class func visibleHistoryFetchRequest() -> NSFetchRequest<CaptureArtifactMO> {
        let request = fetchRequest()
        request.predicate = NSPredicate(
            format: "lifecycleStateRawValue IN %@",
            [TranscriptionLifecycleState.completed.rawValue, TranscriptionLifecycleState.failed.rawValue]
        )
        return request
    }

    /// Fetch request para buscar transcrição por ID
    @nonobjc class func fetchRequest(forTranscriptionId id: UUID) -> NSFetchRequest<CaptureArtifactMO> {
        let request = NSFetchRequest<CaptureArtifactMO>(entityName: "TranscriptionMO")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return request
    }

    /// Fetch request para buscar transcrições de uma reunião
    @nonobjc class func fetchRequest(forMeetingId meetingId: UUID) -> NSFetchRequest<CaptureArtifactMO> {
        let request = NSFetchRequest<CaptureArtifactMO>(entityName: "TranscriptionMO")
        request.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                NSPredicate(format: "meeting.id == %@", meetingId as CVarArg),
                NSPredicate(
                    format: "lifecycleStateRawValue IN %@",
                    [TranscriptionLifecycleState.completed.rawValue, TranscriptionLifecycleState.failed.rawValue]
                )
            ]
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return request
    }

    @nonobjc class func mockArtifactsFetchRequest() -> NSFetchRequest<CaptureArtifactMO> {
        let request = NSFetchRequest<CaptureArtifactMO>(entityName: "TranscriptionMO")
        request.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "modelName == %@", mockArtifactDefaultModel),
            NSPredicate(format: "text == %@", mockArtifactDefaultText)
        ])
        return request
    }

    static func removeMockArtifacts(in context: NSManagedObjectContext) throws -> Int {
        let artifacts = try context.fetch(mockArtifactsFetchRequest())
        guard !artifacts.isEmpty else { return 0 }

        for artifact in artifacts {
            context.delete(artifact)
        }

        try context.save()
        return artifacts.count
    }
}

// MARK: - Conversion Methods

extension CaptureArtifactMO {
    private static let contextItemsDecoder = JSONDecoder()
    private static let contextItemsEncoder = JSONEncoder()
    private static let canonicalSummaryDecoder = JSONDecoder()
    private static let canonicalSummaryEncoder = JSONEncoder()
    private static let meetingConversationStateDecoder = JSONDecoder()
    private static let meetingConversationStateEncoder = JSONEncoder()
    private static let transcriptionQualityDecoder = JSONDecoder()
    private static let transcriptionQualityEncoder = JSONEncoder()
    private static let executionProvenanceDecoder = JSONDecoder()
    private static let executionProvenanceEncoder = JSONEncoder()
    private static func segmentSortComparator(_ lhs: CaptureArtifactEntity.Segment, _ rhs: CaptureArtifactEntity.Segment) -> Bool {
        if lhs.startTime != rhs.startTime {
            return lhs.startTime < rhs.startTime
        }
        if lhs.endTime != rhs.endTime {
            return lhs.endTime < rhs.endTime
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Converte Managed Object para Domain Entity
    func toDomain() -> CaptureArtifactEntity {
        let sortedSegments = segments
            .map { $0.toDomain() }
            .sorted(by: Self.segmentSortComparator)

        var config = CaptureArtifactEntity.Configuration(
            text: text,
            rawText: rawText,
            segments: sortedSegments,
            language: language
        )
        config.id = id
        config.contextItems = decodeContextItems()
        config.processedContent = processedContent
        config.postProcessingPromptId = postProcessingPromptId
        config.postProcessingPromptTitle = postProcessingPromptTitle
        config.postProcessingRequestSystemPrompt = postProcessingRequestSystemPrompt
        config.postProcessingRequestUserPrompt = postProcessingRequestUserPrompt
        config.createdAt = createdAt
        config.modelName = modelName
        config.inputSource = inputSource
        config.transcriptionDuration = transcriptionDuration
        config.postProcessingDuration = postProcessingDuration
        config.postProcessingModel = postProcessingModel
        config.postProcessingFailureReason = postProcessingFailureReason
        config.postProcessingOutputState = postProcessingOutputStateRawValue.flatMap(DomainPostProcessingOutputState.init(rawValue:))
        config.transcriptionFailureReason = transcriptionFailureReason
        config.meetingType = meetingType
        config.lifecycleState = lifecycleState
        config.meetingConversationState = decodeMeetingConversationState()
        config.canonicalSummary = decodeCanonicalSummary()
        config.qualityProfile = decodeTranscriptionQuality()
        config.executionProvenance = decodeExecutionProvenance()

        return CaptureArtifactEntity(meeting: meeting.toDomain(), config: config)
    }

    /// Atualiza Managed Object com dados da Domain Entity
    func update(from entity: CaptureArtifactEntity, meeting: CaptureSessionMO) {
        id = entity.id
        text = entity.text
        rawText = entity.rawText
        processedContent = entity.processedContent
        postProcessingPromptId = entity.postProcessingPromptId
        postProcessingPromptTitle = entity.postProcessingPromptTitle
        postProcessingRequestSystemPrompt = entity.postProcessingRequestSystemPrompt
        postProcessingRequestUserPrompt = entity.postProcessingRequestUserPrompt
        language = entity.language
        createdAt = entity.createdAt
        modelName = entity.modelName
        inputSource = entity.inputSource
        transcriptionDuration = entity.transcriptionDuration
        postProcessingDuration = entity.postProcessingDuration
        postProcessingModel = entity.postProcessingModel
        postProcessingFailureReason = entity.postProcessingFailureReason
        postProcessingOutputStateRawValue = entity.postProcessingOutputState?.rawValue
        transcriptionFailureReason = entity.transcriptionFailureReason
        meetingType = entity.meetingType
        lifecycleStateRawValue = entity.lifecycleState.rawValue
        meetingConversationStateData = encodeMeetingConversationState(entity.meetingConversationState)
        contextItemsData = encodeContextItems(entity.contextItems)
        applyCanonicalSummary(entity.canonicalSummary)
        applyTranscriptionQuality(entity.qualityProfile)
        executionProvenanceData = encodeExecutionProvenance(entity.executionProvenance)

        self.meeting = meeting

        // Atualizar segmentos
        guard let context = managedObjectContext else { return }
        segments.forEach { context.delete($0) }
        let newSegments = entity.segments.map {
            CaptureArtifactSegmentMO.create(from: $0, transcription: self, in: context)
        }
        segments = Set(newSegments)
    }

    /// Cria novo Managed Object a partir de Domain Entity
    static func create(from entity: CaptureArtifactEntity, meeting: CaptureSessionMO, in context: NSManagedObjectContext) -> CaptureArtifactMO {
        let transcriptionMO = CaptureArtifactMO(
            entity: resolvedEntityDescription(named: "TranscriptionMO", in: context),
            insertInto: context
        )
        transcriptionMO.id = entity.id
        transcriptionMO.text = entity.text
        transcriptionMO.rawText = entity.rawText
        transcriptionMO.processedContent = entity.processedContent
        transcriptionMO.postProcessingPromptId = entity.postProcessingPromptId
        transcriptionMO.postProcessingPromptTitle = entity.postProcessingPromptTitle
        transcriptionMO.postProcessingRequestSystemPrompt = entity.postProcessingRequestSystemPrompt
        transcriptionMO.postProcessingRequestUserPrompt = entity.postProcessingRequestUserPrompt
        transcriptionMO.language = entity.language
        transcriptionMO.createdAt = entity.createdAt
        transcriptionMO.modelName = entity.modelName
        transcriptionMO.inputSource = entity.inputSource
        transcriptionMO.transcriptionDuration = entity.transcriptionDuration
        transcriptionMO.postProcessingDuration = entity.postProcessingDuration
        transcriptionMO.postProcessingModel = entity.postProcessingModel
        transcriptionMO.postProcessingFailureReason = entity.postProcessingFailureReason
        transcriptionMO.postProcessingOutputStateRawValue = entity.postProcessingOutputState?.rawValue
        transcriptionMO.transcriptionFailureReason = entity.transcriptionFailureReason
        transcriptionMO.meetingType = entity.meetingType
        transcriptionMO.lifecycleStateRawValue = entity.lifecycleState.rawValue
        transcriptionMO.meetingConversationStateData = transcriptionMO.encodeMeetingConversationState(entity.meetingConversationState)
        transcriptionMO.contextItemsData = transcriptionMO.encodeContextItems(entity.contextItems)
        transcriptionMO.applyCanonicalSummary(entity.canonicalSummary)
        transcriptionMO.applyTranscriptionQuality(entity.qualityProfile)
        transcriptionMO.executionProvenanceData = transcriptionMO.encodeExecutionProvenance(entity.executionProvenance)
        transcriptionMO.meeting = meeting

        // Criar segmentos
        let segments = entity.segments.map {
            CaptureArtifactSegmentMO.create(from: $0, transcription: transcriptionMO, in: context)
        }
        transcriptionMO.segments = Set(segments)

        return transcriptionMO
    }

    private func decodeContextItems() -> [TranscriptionContextItem] {
        guard let data = contextItemsData else { return [] }
        return (try? Self.contextItemsDecoder.decode([TranscriptionContextItem].self, from: data)) ?? []
    }

    private func encodeContextItems(_ items: [TranscriptionContextItem]) -> Data? {
        guard !items.isEmpty else { return nil }
        return try? Self.contextItemsEncoder.encode(items)
    }

    private func decodeMeetingConversationState() -> MeetingConversationState? {
        guard let data = meetingConversationStateData else { return nil }
        return try? Self.meetingConversationStateDecoder.decode(MeetingConversationState.self, from: data)
    }

    private func encodeMeetingConversationState(_ state: MeetingConversationState?) -> Data? {
        guard let state else { return nil }
        return try? Self.meetingConversationStateEncoder.encode(state)
    }

    private var lifecycleState: TranscriptionLifecycleState {
        TranscriptionLifecycleState(rawValue: lifecycleStateRawValue) ?? .completed
    }

    private func decodeCanonicalSummary() -> CanonicalSummary? {
        guard let data = canonicalSummaryData, let summary = try? Self.canonicalSummaryDecoder.decode(CanonicalSummary.self, from: data) else {
            return nil
        }

        do {
            try summary.validate()
            return summary
        } catch {
            return nil
        }
    }

    private func decodeTranscriptionQuality() -> TranscriptionQualityProfile? {
        guard let data = transcriptionQualityData else { return nil }
        return try? Self.transcriptionQualityDecoder.decode(TranscriptionQualityProfile.self, from: data)
    }

    private func decodeExecutionProvenance() -> ExecutionProvenance? {
        guard let data = executionProvenanceData else { return nil }
        return try? Self.executionProvenanceDecoder.decode(ExecutionProvenance.self, from: data)
    }

    private func encodeExecutionProvenance(_ provenance: ExecutionProvenance?) -> Data? {
        guard let provenance else { return nil }
        return try? Self.executionProvenanceEncoder.encode(provenance)
    }

    private func applyCanonicalSummary(_ summary: CanonicalSummary?) {
        guard let summary, let encodedSummary = try? Self.canonicalSummaryEncoder.encode(summary) else {
            canonicalSummaryData = nil
            canonicalSummarySchemaVersion = 0
            summaryGroundedInTranscript = false
            summaryContainsSpeculation = false
            summaryHumanReviewed = false
            summaryConfidenceScore = 0.0
            return
        }

        canonicalSummaryData = encodedSummary
        canonicalSummarySchemaVersion = Self.clampSchemaVersion(summary.schemaVersion)
        summaryGroundedInTranscript = summary.trustFlags.isGroundedInTranscript
        summaryContainsSpeculation = summary.trustFlags.containsSpeculation
        summaryHumanReviewed = summary.trustFlags.isHumanReviewed
        summaryConfidenceScore = summary.trustFlags.confidenceScore
    }

    private func applyTranscriptionQuality(_ qualityProfile: TranscriptionQualityProfile?) {
        guard let qualityProfile, let encoded = try? Self.transcriptionQualityEncoder.encode(qualityProfile) else {
            transcriptionQualityData = nil
            transcriptConfidenceScore = 0.5
            transcriptContainsUncertainty = false
            return
        }

        transcriptionQualityData = encoded
        transcriptConfidenceScore = qualityProfile.overallConfidence
        transcriptContainsUncertainty = qualityProfile.containsUncertainty
    }

    private static func clampSchemaVersion(_ version: Int) -> Int16 {
        let clamped = max(0, min(version, Int(Int16.max)))
        return Int16(clamped)
    }
}

/// Compatibility name for the frozen Core Data managed-object class.
@available(*, deprecated, renamed: "CaptureArtifactMO")
public typealias TranscriptionMO = CaptureArtifactMO
