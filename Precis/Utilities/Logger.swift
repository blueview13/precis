import Foundation
import os.log

public enum PrecisLogger {
    private static let logger = Logger(subsystem: "app.precis.Precis", category: "general")

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
