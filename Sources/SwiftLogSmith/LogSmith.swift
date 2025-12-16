//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objcMembers
final class LogSmith: NSObject, LogManagerOperations, LogTaggerOperations, @unchecked Sendable {
    
    private static let shared = LogSmith()
    
    private let defaultManager = LogManager(identifier: String(describing: LogSmith.self), defaultLogger: OSLogger())
    private let queue = DispatchQueue(label: "com.swift.logsmith")
    
    private override init() {
        super.init()
        //Log type symbolic tag
        LogType.allCases.forEach { logType in
            guard !logType.stringValue.isEmpty && !logType.symbolicValue.isEmpty else { return }
            addTag(InternalTag(identifier: logType.stringValue, value: logType.symbolicValue, logType: logType), completion: nil)
        }
    }
    
    //MARK: Log Manager operations internal API's
    
    internal func addLogger(newLogger: any ILogger, minLogLevel: LogLevel, minLogType: LogType, completion: (@Sendable (Bool) -> Void)?) {
        queue.async { self.defaultManager.addLogger(newLogger: newLogger, minLogLevel: minLogLevel, minLogType: minLogType, completion: completion) }
    }
    
    internal func removeLogger(logger: any ILogger, completion: (@Sendable (Bool) -> Void)?) {
        queue.async { self.defaultManager.removeLogger(logger: logger, completion: completion) }
    }
    
    internal func setMinimumLogLevel(_ logLevel: LogLevel) {
        queue.async { self.defaultManager.setMinimumLogLevel(logLevel)}
    }
    
    internal func setMinimumLogType(_ logType: LogType) {
        queue.async { self.defaultManager.setMinimumLogType(logType)}
    }
    
    //MARK: Log Manager operations public API's
    
    public static func addLogger(newLogger: any ILogger, minLogLevel: LogLevel = .default, minLogType: LogType = .none,_ completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.addLogger(newLogger: newLogger, minLogLevel: minLogLevel, minLogType: minLogType, completion: completion)
    }
    
    public static func removeLogger(logger: any ILogger,_ completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.removeLogger(logger: logger, completion: completion)
    }
    
    public static func setMinimumLogLevel(_ logLevel: LogLevel) {
        shared.setMinimumLogLevel(logLevel)
    }
    
    public static func setMinimumLogType(_ logType: LogType) {
        shared.setMinimumLogType(logType)
    }
    
    //MARK: Log Tagger operations internal API's
    
    internal func addTag(_ logTag: any LogTag, completion: (@Sendable (Bool) -> Void)?) {
        queue.async { self.defaultManager.addTag(logTag, completion: completion) }
    }
    
    internal func removeTag(_ logTag: any LogTag, completion: (@Sendable(Bool) -> Void)?) {
        queue.async { self.defaultManager.removeTag(logTag, completion: completion) }
    }
    
    internal func removeTag(identifier: String, completion: (@Sendable (Bool) -> Void)?) {
        queue.async { self.defaultManager.removeTag(identifier: identifier, completion: completion) }
    }
    
    //MARK: Log Tagger operations public API's
    
    public static func addTag(_ logTag: any LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.addTag(logTag, completion: completion)
    }
    
    public static func removeTag(_ logTag: any LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.removeTag(logTag, completion: completion)
    }
    
    public static func removeTag(identifier: String, completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.removeTag(identifier: identifier, completion: completion)
    }
    
    //MARK: Log public API's
    
    public static func log(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .none, metadata: metadata, fileId: fileId, function: function, line: line) }
    }
    
    public static func logT(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .trace, metadata: metadata, fileId: fileId, function: function, line: line) }
    }
    
    public static func logD(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .debug, metadata: metadata, fileId: fileId, function: function, line: line) }
    }
    
    public static func logN(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .notice, metadata: metadata, fileId: fileId, function: function, line: line) }
    }
    
    public static func logI(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .info, metadata: metadata, fileId: fileId, function: function, line: line) }
    }
    
    public static func logW(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .warning, metadata: metadata, fileId: fileId, function: function, line: line) }
    }
    
    public static func logE(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .error, metadata: metadata, fileId: fileId, function: function, line: line) }
    }
    
    public static func logC(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .critical, metadata: metadata, fileId: fileId, function: function, line: line) }
    }
    
    public static func logF(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .fault, metadata: metadata, fileId: fileId, function: function, line: line) }
    }
    
}

@objc public enum LogType: Int, CaseIterable, @unchecked Sendable {
    
    case undefined  = -1
    case none       = 0
    case notice     = 1
    case info       = 2
    case debug      = 3
    case trace      = 4
    case warning    = 5
    case error      = 6
    case fault      = 7
    case critical   = 8
    
    var stringValue: String {
        switch self {
            case .undefined, .none:
                return ""
            case .notice:
                return "notice"
            case .info:
                return "info"
            case .debug:
                return "debug"
            case .trace:
                return "trace"
            case .warning:
                return "warning"
            case .error:
                return "error"
            case .fault:
                return "fault"
            case .critical:
                return "critical"
        }
    }
    
    var symbolicValue: String {
        return stringValue.isEmpty ? stringValue : stringValue.prefix(1).uppercased()
    }
    
    var logLevel: LogLevel {
        switch self {
            case .undefined:
                return .undefined
            case .none, .notice:
                return .default
            case .info:
                return .info
            case .debug, .trace:
                return .debug
            case .warning, .error:
                return .error
            case .fault, .critical:
                return .fault
        }
    }
}

@objc public enum LogLevel: Int, CaseIterable, @unchecked Sendable {
    case undefined  = -1
    case `default`  = 0
    case info       = 1
    case debug      = 2
    case error      = 3
    case fault      = 4
}

