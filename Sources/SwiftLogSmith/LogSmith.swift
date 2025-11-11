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
    
    private let defaultManager = LogManager(defaultLogger: OSLogger())
    private let queue = DispatchQueue(label: "com.swift.logsmith")
    
    private override init() {
        super.init()
        //Add symbolic prefix for all log types
        LogType.allCases.forEach { logType in
            guard !logType.stringValue.isEmpty && !logType.symbolicValue.isEmpty else {
                return
            }
            addLogPrefix(logTag: LogTag(identifier: logType.stringValue, value: logType.symbolicValue,
                                        logType: logType), completion: nil)
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
    
    internal func addLogPrefix(logTag: LogTag, completion: (@Sendable (Bool) -> Void)?) {
        queue.async { self.defaultManager.addLogPrefix(logTag: logTag, completion: completion) }
    }
    
    internal func removeLogPrefix(identifier: String, completion: (@Sendable (Bool) -> Void)?) {
        queue.async { self.defaultManager.removeLogPrefix(identifier: identifier, completion: completion) }
    }
    
    internal func addLogPostfix(logTag: LogTag, completion: (@Sendable (Bool) -> Void)?) {
        queue.async { self.defaultManager.addLogPostfix(logTag: logTag, completion: completion) }
    }
    
    internal func removeLogPostfix(identifier: String, completion: (@Sendable (Bool) -> Void)?) {
        queue.async { self.defaultManager.removeLogPostfix(identifier: identifier, completion: completion) }
    }
    
    //MARK: Log Tagger operations public API's
    
    public static func addLogPrefix(logTag: LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.addLogPrefix(logTag: logTag, completion: completion)
    }
    
    public static func removeLogPrefix(identifier: String, completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.removeLogPrefix(identifier: identifier, completion: completion)
    }
    
    public static func addLogPostfix(logTag: LogTag, completion: (@Sendable (Bool) -> Void)? = nil) {
        shared.addLogPostfix(logTag: logTag, completion: completion)
    }
    
    public static func removeLogPostfix(identifier: String, completion: (@Sendable (Bool) -> Void)? = nil) {
        shared.removeLogPostfix(identifier: identifier, completion: completion)
    }
    
    //MARK: Log public API's
    
    public static func log(_ message: String) {
        shared.queue.async { shared.defaultManager.log(type: .none, message: message) }
    }
    
    public static func logT(_ message: String) {
        shared.queue.async { shared.defaultManager.log(type: .trace, message: message) }
    }
    
    public static func logD(_ message: String) {
        shared.queue.async { shared.defaultManager.log(type: .debug, message: message) }
    }
    
    public static func logN(_ message: String) {
        shared.queue.async { shared.defaultManager.log(type: .notice, message: message) }
    }
    
    public static func logI(_ message: String) {
        shared.queue.async { shared.defaultManager.log(type: .info, message: message) }
    }
    
    public static func logW(_ message: String) {
        shared.queue.async { shared.defaultManager.log(type: .warning, message: message) }
    }
    
    public static func logE(_ message: String) {
        shared.queue.async { shared.defaultManager.log(type: .error, message: message) }
    }
    
    public static func logC(_ message: String) {
        shared.queue.async { shared.defaultManager.log(type: .critical, message: message) }
    }
    
    public static func logF(_ message: String) {
        shared.queue.async { shared.defaultManager.log(type: .fault, message: message) }
    }
    
}

@objc public enum LogType: Int, CaseIterable, @unchecked Sendable {
    
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
            case .none:
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
            case .none:
                return .default
            case .notice:
                return .default
            case .info:
                return .info
            case .debug:
                return .debug
            case .trace:
                return .debug
            case .warning:
                return .error
            case .error:
                return .error
            case .fault:
                return .fault
            case .critical:
                return .fault
        }
    }
}

@objc public enum LogLevel: Int, CaseIterable, @unchecked Sendable {
    case `default`  = 0
    case info       = 1
    case debug      = 2
    case error      = 3
    case fault      = 4
}

