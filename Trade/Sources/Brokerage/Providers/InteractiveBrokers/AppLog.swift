//
//  AppLog.swift
//  TradeApp
//
//  Created by jk on 26/09/2025.
//


import Foundation
import os

public enum LogLevel: Int, CaseIterable, CustomStringConvertible, Sendable {
    case debug = 0
    case info = 1
    case error = 2
    
    public var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .error: return "ERROR"
        }
    }
    
    public var displayName: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .error: return "Error"
        }
    }
}
/// Simple application logger that writes to unified logging (os.Logger)
/// and optionally appends to a rotating file in Application Support.
public actor AppLog {
    public static let shared = AppLog()
    
    // Toggle file logging; default is false for privacy.
    nonisolated public static func setEnabled(_ v: Bool) {
        Task { await AppLog.shared.setEnabled(v) }
    }
    
    nonisolated public static func isEnabled() async -> Bool {
        await AppLog.shared.isEnabled()
    }
    
    nonisolated public static func debug(_ message: String) {
        Task { await AppLog.shared.log(.debug, message) }
    }
    
    nonisolated public static func info(_ message: String) {
        Task { await AppLog.shared.log(.info, message) }
    }
    
    nonisolated public static func error(_ message: String) {
        Task { await AppLog.shared.log(.error, message) }
    }
    
    nonisolated public static func setFileLogLevel(_ level: LogLevel) {
        Task { await AppLog.shared.setFileLogLevel(level) }
    }
    
    nonisolated public static func currentFileLogLevel() async -> LogLevel {
        await AppLog.shared.currentFileLogLevel()
    }
    
    private let logger: Logger
    private var logFileURL: URL?
    private var enabledInternal: Bool = false
    private var fileLogLevel: LogLevel = .debug
    
    public init() {
        let subsystem = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        logger = Logger(subsystem: subsystem, category: "TradeUI")
        
        if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first {
            let dir = appSupport.appendingPathComponent("Swift&Smart/Logs", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            logFileURL = dir.appendingPathComponent("app.log")
        }
        // Read persisted preferences at actor init so defaults written externally take effect.
        let ud = UserDefaults.standard
        if ud.object(forKey: "logging.enabled") != nil {
            enabledInternal = ud.bool(forKey: "logging.enabled")
        }
        if let lvl = ud.string(forKey: "logging.level")?.lowercased() {
            switch lvl {
            case "debug": fileLogLevel = .debug
            case "info": fileLogLevel = .info
            case "error": fileLogLevel = .error
            default: break
            }
        }
    }
    
    // Actor-isolated helpers
    private func setEnabled(_ v: Bool) { enabledInternal = v }
    private func isEnabled() -> Bool { enabledInternal }
    private func setFileLogLevel(_ level: LogLevel) { fileLogLevel = level }
    private func currentFileLogLevel() -> LogLevel { fileLogLevel }
    
    private func log(_ level: LogLevel, _ message: String) {
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        
        guard enabledInternal, let url = logFileURL, level.rawValue >= fileLogLevel.rawValue else {
            return
        }
        
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] [\(level.description)] \(message)\n"
        
        if let data = line.data(using: .utf8) {
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: data, attributes: nil)
            } else if let fh = try? FileHandle(forWritingTo: url) {
                defer { try? fh.close() }
                _ = try? fh.seekToEnd()
                try? fh.write(contentsOf: data)
            }
            try? rotateIfNeeded(url: url)
        }
    }
    
    private func rotateIfNeeded(url: URL) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attrs[.size] as? UInt64 else { return }
        let maxSize: UInt64 = 5_000_000  // 5 MB
        guard size > maxSize else { return }
        
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
    
    nonisolated public static var logFileURLPublic: URL? {
        if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first {
            return appSupport.appendingPathComponent("Swift&Smart/Logs/app.log")
        }
        return nil
    }
}
