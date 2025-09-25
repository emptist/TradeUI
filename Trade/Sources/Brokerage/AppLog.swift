import Foundation
import os

public enum LogLevel: Int, CustomStringConvertible {
    case debug = 0, info = 1, error = 2
    public var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .error: return "ERROR"
        }
    }
}

/// Simple application logger that writes to unified logging (os.Logger)
/// and optionally appends to a rotating file in Application Support.
public final class AppLog {
    public static let shared = AppLog()

    // Toggle file logging; default is false for privacy.
    public static var enabled: Bool {
        get { shared.enabledInternal }
        set { shared.setEnabled(newValue) }
    }

    private let logger: Logger
    private let fileQueue = DispatchQueue(label: "com.tradeui.applog.file")
    private var logFileURL: URL?
    private var enabledInternal: Bool = false

    private init() {
        let subsystem = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        logger = Logger(subsystem: subsystem, category: "TradeUI")

        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("Trade With It/Logs", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            logFileURL = dir.appendingPathComponent("app.log")
        }
    }

    public static func setEnabled(_ enabled: Bool) {
        AppLog.enabled = enabled
    }

    private func setEnabled(_ v: Bool) {
        fileQueue.sync { enabledInternal = v }
    }

    public static func debug(_ message: String) {
        shared.log(.debug, message)
    }

    public static func info(_ message: String) {
        shared.log(.info, message)
    }

    public static func error(_ message: String) {
        shared.log(.error, message)
    }

    private func log(_ level: LogLevel, _ message: String) {
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }

        guard enabledInternal, let url = logFileURL else { return }

        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] [\(level)] \(message)\n"

        fileQueue.async { [url] in
            if let data = line.data(using: .utf8) {
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: data, attributes: nil)
                } else if let fh = try? FileHandle(forWritingTo: url) {
                    defer { try? fh.close() }
                    try? fh.seekToEnd()
                    try? fh.write(contentsOf: data)
                }
                try? self.rotateIfNeeded(url: url)
            }
        }
    }

    private func rotateIfNeeded(url: URL) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attrs[.size] as? UInt64 else { return }
        let maxSize: UInt64 = 5_000_000 // 5 MB
        guard size > maxSize else { return }

        // Rotate: app.log -> app.log.1, .1 -> .2, keep 3 backups
        for i in stride(from: 3, to: 0, by: -1) {
            let older = url.appendingPathExtension(String(i))
            let next = url.appendingPathExtension(String(i + 1))
            if FileManager.default.fileExists(atPath: older.path) {
                try? FileManager.default.removeItem(at: next)
                try? FileManager.default.moveItem(at: older, to: next)
            }
        }
        let first = url.appendingPathExtension("1")
        try FileManager.default.moveItem(at: url, to: first)
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
    }

    /// Expose the log file path for UI actions (optional)
    public static var logFileURLPublic: URL? { shared.logFileURL }
}
