//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objcMembers
final class LogSmith: NSObject, @unchecked Sendable {
    
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
            defaultManager.addLogPrefix(logPrefix: LogTag(identifier: logType.stringValue,
                                                          value: logType.symbolicValue,
                                                          logType: logType))
        }
    }
    
    public static func addLogger(newLogger: any ILogger, minLogLevel: LogLevel = .default, minLogType: LogType = .none,_ completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.queue.async { shared.defaultManager.addLogger(newLogger: newLogger, minLogLevel: minLogLevel, minLogType: minLogType, completion: completion) }
    }
    
    public static func removeLogger(logger: any ILogger,_ completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.queue.async { shared.defaultManager.removeLogger(logger: logger, completion: completion) }
    }
    
    public static func setMinimumLogLevel(_ logLevel: LogLevel) {
        shared.queue.async { shared.defaultManager.setMinimumLogLevel(logLevel)}
    }
    
    public static func setMinimumLogType(_ logType: LogType) {
        shared.queue.async { shared.defaultManager.setMinimumLogType(logType)}
    }
    
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

@objcMembers
final class LogTag: NSObject, @unchecked Sendable {
    
    let identifier: String
    let logType: LogType?
    let value: String
    
    init(identifier: String, value: String, logType: LogType? = nil){
        self.identifier = identifier
        self.logType = logType
        self.value = value
        super.init()
    }
    
}

@objcMembers
final class LogTagCollection: NSObject, @unchecked Sendable {
    
    private var logTags: Array<LogTag>
    private let queue = DispatchQueue(label: "com.swift.logtag")
    private var values: String
    private var typeValues: [LogType? : String]
    
    override init() {
        self.logTags = []
        self.values = ""
        self.typeValues = Dictionary()
        super.init()
    }
    
    init(_ logTags: Array<LogTag>) {
        self.logTags = Array(logTags)
        self.values = LogTagCollection.toStringValue(logTags: self.logTags)
        self.typeValues = LogTagCollection.toTypeStringValue(logTags: self.logTags)
        super.init()
    }
    
    func toString(completion: @escaping (@Sendable(String) -> Void)) {
        queue.async {
            completion(self.values)
        }
    }
    
    func toNoTypeString(completion: @escaping (@Sendable(String) -> Void)) {
        queue.async {
            completion(self.typeValues[nil, default: ""])
        }
    }
    
    func toTypeString(logType: LogType, completion: @escaping (@Sendable(String) -> Void)) {
        queue.async {
            completion(self.typeValues[logType, default: ""])
        }
    }
    
    func addTag(_ logTag: LogTag,_ completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            if self.logTags.first(where: {$0.identifier == logTag.identifier}) != nil {
                completion?(false)
            }
            else {
                self.logTags.append(logTag)
                self.values = LogTagCollection.toStringValue(logTags: self.logTags)
                self.typeValues = LogTagCollection.toTypeStringValue(logTags: self.logTags)
                completion?(true)
            }
        }
    }
    
    func removeTag(_ identifier: String,_ completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            if let tagIndex = self.logTags.firstIndex(where: {$0.identifier == identifier}) {
                self.logTags.remove(at: tagIndex)
                self.values = LogTagCollection.toStringValue(logTags: self.logTags)
                self.typeValues = LogTagCollection.toTypeStringValue(logTags: self.logTags)
                completion?(true)
            }
            else {
                completion?(false)
            }
        }
    }
    
    private static func toStringValue(logTags: Array<LogTag>) -> String {
        var valueBuilder = ""
        logTags.forEach { valueBuilder.append(formattedTagValue($0))  }
        return finalValue(inputValue: valueBuilder)
    }
    
    private static func toTypeStringValue(logTags: Array<LogTag>) -> [LogType? : String] {
        var typeValues = [LogType? : String]()
        logTags.forEach { logTag in
            let typeValue = typeValues[logTag.logType, default: ""].appending(formattedTagValue(logTag))
            typeValues.updateValue(typeValue, forKey: logTag.logType)
        }
        typeValues.keys.forEach { logType in
            typeValues.updateValue(finalValue(inputValue: typeValues[logType, default: ""]), forKey: logType)
        }
        return typeValues
    }
    
    private static func formattedTagValue(_ logTag: LogTag) -> String {
        return " [\(logTag.value)]"
    }
    
    private static func finalValue(inputValue: String) -> String {
        return inputValue.isEmpty ? inputValue : String(inputValue.dropFirst())
    }
    
    
}

