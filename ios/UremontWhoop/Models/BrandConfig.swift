import Foundation

/// Единая точка URL, лимитов и дефолтов Wi‑Fi (white-label, зеркало Android `AppConfig`).
enum BrandConfig {
    static let mapScheme = "https"
    static let mapHost = "map.uremont.com"
    static let mapQueryAi = "ai"

    static let sessionsFileName = "sessions.json"
    static let maxSessionRecords = 100

    static let defaultWifiHost = "192.168.0.10"
    static let defaultWifiPort = 35_000

    /// Значения `timestamp` в JSON ниже — секунды Unix (legacy iOS); иначе — миллисекунды.
    static let timestampUnixSecondsCeiling: Double = 100_000_000_000

    static let livePollMinIntervalSeconds = 0.3
    static let livePollBackgroundDelaySeconds = 2.0
    static let postConnectDelaySeconds = 0.5
}
