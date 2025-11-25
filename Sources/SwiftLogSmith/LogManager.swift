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
    
    public func log(message: String, logType: LogType, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line) {
        queue.async {
            if logType.logLevel.rawValue >= self.minLogLevel.rawValue && logType.rawValue >= self.minLogType.rawValue {
                self.extractTags(logTagger: self.logTagger, logType: logType, fileId: fileId, function: function, line: line) { managerPrefixTags, managerPostfixTags in
                    self.loggerItems.forEach { loggerItem in
                        if logType.logLevel.rawValue >= loggerItem.minLogLevel.rawValue && logType.rawValue >= loggerItem.minLogType.rawValue {
                            self.extractTags(logTagger: loggerItem.logger.logTagger, logType: logType, fileId: fileId, function: function, line: line) { loggerPrefixTags, loggerPostfixTags in
                                loggerItem.logger.log(message: LogMessage(message: message, logType: logType, prefixTags: managerPrefixTags+loggerPrefixTags, postfixTags: managerPostfixTags+loggerPostfixTags, metadata: metadata))
                            }
                        }
                    }
                }
            }
        }
    }
    
    //MARK: Private operation API's
    
    private func extractTags(logTagger: LogTagger?, logType: LogType, fileId: StaticString, function: StaticString, line: UInt, completion: @escaping (@Sendable([Tag], [Tag]) -> Void)) {
        if let logTagger = logTagger {
            logTagger.logTags(logType: logType) { prefixTags, postfixTags in
                let tagExtractor = LogTagsExtractor()
                completion(tagExtractor.extract(logTags: prefixTags, fileId: fileId, function: function, line: line),
                           tagExtractor.extract(logTags: postfixTags, fileId: fileId, function: function, line: line))
            }
        }
        else {
            completion([], [])
        }
    }
    
    //MARK: Log Tagger operations public API's
    
    public func addLogPrefix(logTag: any LogTag, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { self.logTagger.addLogPrefix(logTag: logTag, completion: completion) }
    }
    
    public func removeLogPrefix(identifier: String, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { self.logTagger.removeLogPrefix(identifier: identifier, completion: completion) }
    }
    
    public func addLogPostfix(logTag: any LogTag, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { self.logTagger.addLogPostfix(logTag: logTag, completion: completion) }
    }
    
    public func removeLogPostfix(identifier: String, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { self.logTagger.removeLogPostfix(identifier: identifier, completion: completion) }
    }
}

private final class LogTagsExtractor: LogTagVisitor, @unchecked Sendable {
    
    private var tags = [Tag]()
    private var fileId = ""
    private var function = ""
    private var line = 0
    
    func extract(logTags: [any LogTag], fileId: StaticString, function: StaticString, line: UInt) -> [Tag] {
        self.fileId = "\(fileId)"
        self.function = "\(function)"
        self.line = Int(line)
        tags.removeAll()
        logTags.forEach { logTag in
            logTag.visit(logTagVisitor: self)
        }
        return tags
    }
    
    func visit(logInternalTag: LogInternalTag) {
        tags.append(Tag(key: logInternalTag.identifier, value: logInternalTag.value))
    }
    
    func visit(logExternalTag: LogExternalTag) {
        let value: String
        switch logExternalTag.systemTagType {
        case .file:
            value = fileId
        case .function:
            value = function
        case .line:
            value = "\(line)"
        case .threadName:
            value = Utils.threadName()
        }
        tags.append(Tag(key: logExternalTag.identifier, value: value))
    }
}

private final class Utils {
    
    static func threadName() -> String {
        if Thread.isMainThread {
            return "main"
        }
        else {
            let name = __dispatch_queue_get_label(nil)
            return String(cString: name, encoding: .utf8) ?? Thread.current.name ?? "unknown"
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
