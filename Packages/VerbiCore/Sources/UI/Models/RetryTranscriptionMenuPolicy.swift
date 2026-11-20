enum RetryTranscriptionMenuPolicy {
    static func showsModelOptions(_ options: [RetryTranscriptionOption]) -> Bool {
        !options.isEmpty
    }

    static func isRetryEnabled(options: [RetryTranscriptionOption], hasAudio: Bool) -> Bool {
        hasAudio && !options.isEmpty
    }
}
