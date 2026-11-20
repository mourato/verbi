import Foundation

public enum AppEnvironment {
    case debug
    case release

    public static var current: AppEnvironment {
        #if DEBUG
            .debug
        #else
            .release
        #endif
    }

    public static var isDebug: Bool {
        current == .debug
    }

    public static var isRelease: Bool {
        current == .release
    }
}

public enum EnvironmentConfig {
    public enum Logging {
        public static var isDetailedLoggingEnabled: Bool {
            AppEnvironment.isDebug
        }

        public static var privacyLevel: String {
            AppEnvironment.isDebug ? "public" : "private"
        }
    }

    public enum Features {
        public static var enableExperimentalFeatures: Bool {
            AppEnvironment.isDebug
        }
    }

    public enum API {
        public static var baseURL: URL {
            #if DEBUG
                let urlString = "https://api-dev.meetingassistant.com"
            #else
                let urlString = "https://api.meetingassistant.com"
            #endif

            return URL(string: urlString) ?? URL(string: "https://localhost")!
        }
    }
}
