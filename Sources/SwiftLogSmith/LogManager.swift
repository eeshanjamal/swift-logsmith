//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objcMembers
final class LogManager: NSObject, ILogger, @unchecked Sendable {
    
    private var loggerItems: Array<LoggerItem>
    private var logPrefixes: LogTagCollection
    private var logPostfixes: LogTagCollection
    private let queue = DispatchQueue(label: "com.swift.logman")
    private var minLogLevel: LogLevel
    private var minLogType: LogType
    
    public init(defaultLogger: any ILogger, minLogLevel: LogLevel = .default, minLogType: LogType = .none) {
        self.loggerItems = [LoggerItem(logger: defaultLogger, minLogLevel: minLogLevel, minLogType: minLogType, isDefault: true)]
        self.logPrefixes = LogTagCollection()
        self.logPostfixes = LogTagCollection()
        self.minLogLevel = .default
        self.minLogType = .none
        super.init()
    }
    
    //MARK: Logger API's
    
    public func addLogger(newLogger: any ILogger, minLogLevel: LogLevel = .default, minLogType: LogType = .none, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            let newLoggerType = type(of: newLogger)
            guard !self.loggerItems.contains(where: { type(of: $0.logger) == newLoggerType}) else {
                completion?(false)
                return
            }
            self.loggerItems.append(LoggerItem(logger: newLogger, minLogLevel: minLogLevel, minLogType: minLogType))
            completion?(true)
        }
    }
    
    public func removeLogger(logger: any ILogger, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            let loggerType = type(of: logger)
            if let index = self.loggerItems.firstIndex(where: {type(of: $0.logger) == loggerType}), !self.loggerItems[index].isDefault {
                self.loggerItems.remove(at: index)
                completion?(true)
            }
            else {
                completion?(false)
            }
        }
    }
    
    //MARK: Log Prefix API's
    
    public func addLogPrefix(logPrefix: LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            self.logPrefixes.addTag(logPrefix, completion)
        }
    }
    
    public func  removeLogPrefix(identifier: String, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            self.logPrefixes.removeTag(identifier, completion)
        }
    }
    
    //MARK: Log Postfix API's
    
    public func addLogPostfix(logPostfix: LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            self.logPostfixes.addTag(logPostfix, completion)
        }
    }
    
    public func  removeLogPostfix(identifier: String, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            self.logPostfixes.removeTag(identifier, completion)
        }
    }
    
    //MARK: Set Log level and Log Type
    
    public func setMinimumLogLevel(_ logLevel: LogLevel) {
        queue.async {
            self.minLogLevel = logLevel
        }
    }
    
    public func setMinimumLogType(_ logType: LogType) {
        queue.async {
            self.minLogType = logType
        }
    }
    
    
    //MARK: ILogger protocol implmentation
    
    func log(type: LogType, message: String) {
        queue.async {
            if type.logLevel.rawValue >= self.minLogLevel.rawValue && type.rawValue >= self.minLogType.rawValue {
                self.addOnLogMessage(logType: type, message: message) { finalMessage in
                    self.loggerItems.forEach { loggerItem in
                        if type.logLevel.rawValue >= loggerItem.minLogLevel.rawValue && type.rawValue >= loggerItem.minLogType.rawValue {
                            loggerItem.logger.log(type: type, message: finalMessage)
                        }
                    }
                }
            }
            
        }
    }
    
    //MARK: Private API's
    
    private func addOnLogMessage(logType: LogType? = nil, message: String, completion: @escaping (@Sendable(String) -> Void)) {
        logPrefixes.toNoTypeString { noTypePrefix in
            self.logPostfixes.toNoTypeString { noTypePostfix in
                if let logType = logType {
                    self.logPrefixes.toTypeString(logType: logType) { typePrefix in
                        self.logPostfixes.toTypeString(logType: logType) { typePostfix in
                            completion("\(noTypePrefix) \(typePrefix) \(message) \(typePostfix) \(noTypePostfix)")
                        }
                    }
                }
                else {
                    completion("\(noTypePrefix) \(message) \(noTypePostfix)")
                }
            }
        }
    }
    
}

@objcMembers
private final class LoggerItem: NSObject, @unchecked Sendable {
    
    let logger: any ILogger
    let minLogLevel: LogLevel
    let minLogType: LogType
    let isDefault: Bool
    
    init(logger: any ILogger, minLogLevel: LogLevel, minLogType: LogType, isDefault: Bool = false) {
        self.logger = logger
        self.minLogLevel = minLogLevel
        self.minLogType = minLogType
        self.isDefault = isDefault
        super.init()
    }
    
}
