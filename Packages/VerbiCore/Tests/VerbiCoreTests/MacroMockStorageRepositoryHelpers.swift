@testable import VerbiCoreDomain

func makeMacroMockTranscriptionStorageRepository() -> VerbiCoreDomain.MacroMockTranscriptionStorageRepository {
    let storageRepository = VerbiCoreDomain.MacroMockTranscriptionStorageRepository()
    storageRepository.saveModelPerformanceAttemptHandler = { _ in }
    return storageRepository
}
