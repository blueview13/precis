import Foundation

public enum RefreshInterval: Int, CaseIterable, Codable {
    case oneMinute = 1
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case sixtyMinutes = 60

    public var displayName: String {
        switch self {
        case .oneMinute:
            return "1 minute"
        case .fiveMinutes:
            return "5 minutes"
        case .fifteenMinutes:
            return "15 minutes"
        case .thirtyMinutes:
            return "30 minutes"
        case .sixtyMinutes:
            return "60 minutes"
        }
    }
}

public struct RefreshScheduleSettings: Codable {
    public var interval: RefreshInterval
    public var manualRefreshEnabled: Bool
    public var mutedFeedsEnabled: Bool

    public init(interval: RefreshInterval = .fifteenMinutes, manualRefreshEnabled: Bool = true, mutedFeedsEnabled: Bool = false) {
        self.interval = interval
        self.manualRefreshEnabled = manualRefreshEnabled
        self.mutedFeedsEnabled = mutedFeedsEnabled
    }
}
