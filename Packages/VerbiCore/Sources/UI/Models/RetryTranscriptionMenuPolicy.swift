/// Display rules for the retry actions in the history menu.
///
/// The primary action retries with the captured provider/model. The model
/// submenu exposes every eligible choice, including the only eligible option
/// when the captured provider is no longer available. With no eligible option
/// the actions stay disabled instead of starting a request that cannot run.
enum RetryTranscriptionMenuPolicy {
    static func showsModelOptions(_ options: [RetryTranscriptionOption]) -> Bool {
        !options.isEmpty
    }

    static func isRetryEnabled(options: [RetryTranscriptionOption], hasAudio: Bool) -> Bool {
        hasAudio && !options.isEmpty
    }
}
