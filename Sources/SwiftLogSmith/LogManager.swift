//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objc internal protocol LogManagerOperations: Sendable {
    
    @objc func addLogger(newLogger: any ILogger, minLogLevel: LogLevel, minLogType: LogType, completion: (@Sendable(Bool) -> Void)?)
    @objc func removeLogger(logger: any ILogger, completion: (@Sendable(Bool) -> Void)?)
    @objc func setMinimumLogLevel(_ logLevel: LogLevel)
    @objc func setMinimumLogType(_ logType: LogType)
}

@objcMembers
final class LogManager: NSObject, LogManagerOperations, LogTaggerOperations, @unchecked Sendable {
    
    private var loggerItems: Array<LoggerItem>
    private let logTagger: LogTagger
    private let queue: DispatchQueue
    private var minLogLevel: LogLevel
    private var minLogType: LogType
    
    public init(defaultLogger: any ILogger, minLogLevel: LogLevel = .default, minLogType: LogType = .none) {
        self.queue = DispatchQueue(label: "com.swift.logman.\(NSUUID().uuidString)")
        self.loggerItems = [LoggerItem(logger: defaultLogger, minLogLevel: minLogLevel, minLogType: minLogType, isDefault: true)]
        self.logTagger = LogTagger()
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
    
    //MARK: Log message public API
    
    public func log(type: LogType, message: String) {
        queue.async {
            if type.logLevel.rawValue >= self.minLogLevel.rawValue && type.rawValue >= self.minLogType.rawValue {
                self.embedTags(logTagger: self.logTagger, message: message, logType: type) { tagsEmbedMessage in
                    self.loggerItems.forEach { loggerItem in
                        if type.logLevel.rawValue >= loggerItem.minLogLevel.rawValue && type.rawValue >= loggerItem.minLogType.rawValue {
                            self.embedTags(logTagger: loggerItem.logger.logTagger, message: tagsEmbedMessage, logType: type) { finalMessage in
                                loggerItem.logger.log(type: type, message: finalMessage)
                            }
                        }
                    }
                }
            }
        }
    }
    
    //MARK: Private operation API's
    
    private func embedTags(logTagger: LogTagger?, message: String, logType: LogType? = nil, completion: @escaping (@Sendable(String) -> Void)) {
        
        if let logTagger = logTagger {
            logTagger.logPrefixValue(logType: logType) { prefixTags in
                logTagger.logPostfixValue(logType: logType) { postfixTags in
                    var finalValue = String()
                    if !prefixTags.isEmpty {
                        finalValue.append(" \(prefixTags)")
                    }
                    if !message.isEmpty {
                        finalValue.append(" \(message)")
                    }
                    if !postfixTags.isEmpty {
                        finalValue.append(" \(postfixTags)")
                    }
                    completion(finalValue.isEmpty ? finalValue : String(finalValue.dropFirst()))
                }
            }
        }
        else {
            completion(message)
        }
    }
    
    //MARK: Log Tagger operations public API's
    
    public func addLogPrefix(logTag: LogTag, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { self.logTagger.addLogPrefix(logTag: logTag, completion: completion) }
    }
    
    public func removeLogPrefix(identifier: String, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { self.logTagger.removeLogPrefix(identifier: identifier, completion: completion) }
    }
    
    public func addLogPostfix(logTag: LogTag, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { self.logTagger.addLogPostfix(logTag: logTag, completion: completion) }
    }
    
    public func removeLogPostfix(identifier: String, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { self.logTagger.removeLogPostfix(identifier: identifier, completion: completion) }
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
