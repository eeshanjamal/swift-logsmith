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

extension UserDefaults {
    func contains(key: String) -> Bool {
        return object(forKey: key) != nil
    }
}

@objcMembers
final class LogManager: NSObject, LogManagerOperations, LogTaggerOperations, @unchecked Sendable {
    
    internal enum defaults: String {
        case minimumLogLevel
        case minimumLogType
    }
    
    internal let identifier: String
    private var loggerItems: [LoggerItem]
    private let logTagger = LogTagger()
    private let queue = DispatchQueue(label: "com.swift.logsmith.logman.\(NSUUID().uuidString)")
    private var minLogLevel = LogLevel.default
    private var minLogType = LogType.none
    
    public init(identifier: String, defaultLogger: any ILogger, minLogLevel: LogLevel = .default, minLogType: LogType = .none) {
        self.identifier = identifier
        self.loggerItems = []
        super.init()
        self.loggerItems.append(LoggerItem(logger: defaultLogger, parent: self, minLogLevel: minLogLevel, minLogType: minLogType, isDefault: true))
    }
    
    //MARK: Logger API's
    
    public func addLogger(newLogger: any ILogger, minLogLevel: LogLevel = .default, minLogType: LogType = .none, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            // Check for instance identity to prevent adding the exact same logger object twice
            guard !self.loggerItems.contains(where: { $0.logger === newLogger }) else {
                completion?(false)
                return
            }
            self.loggerItems.append(LoggerItem(logger: newLogger, parent: self, minLogLevel: minLogLevel, minLogType: minLogType))
            completion?(true)
        }
    }
    
    public func removeLogger(logger: any ILogger, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            // Find index by instance identity, ignoring the default logger
            if let index = self.loggerItems.firstIndex(where: { $0.logger === logger }), !self.loggerItems[index].isDefault {
                self.loggerItems.remove(at: index)
                completion?(true)
            }
            else {
                completion?(false)
            }
        }
    }
    
    //MARK: Setter/Getter LogLevel and LogType
    
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
    
    private func getMinimumLogLevel() -> LogLevel {
        let minLogLevelKey = "\(identifier).\(defaults.minimumLogLevel.rawValue)"
        if UserDefaults.standard.contains(key: minLogLevelKey) {
            return LogLevel.init(rawValue: UserDefaults.standard.integer(forKey: minLogLevelKey))!
        }
        else {
            return minLogLevel
        }
    }
    
    private func getMinimumLogType() -> LogType {
        let minLogTypeKey = "\(identifier).\(defaults.minimumLogType.rawValue)"
        if UserDefaults.standard.contains(key: minLogTypeKey) {
            return LogType.init(rawValue: UserDefaults.standard.integer(forKey: minLogTypeKey))!
        }
        else {
            return minLogType
        }
    }
    
    //MARK: Log message public API
    
    public func log(message: String, logType: LogType, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async {
            // Check Manager Level
            guard logType.logLevel.rawValue >= self.getMinimumLogLevel().rawValue && logType.rawValue >= self.getMinimumLogType().rawValue else {
                completion?(true)
                return
            }
            
            self.extractTags(logTagger: self.logTagger, logType: logType, fileId: fileId, function: function, line: line) { managerTags in
                
                // Identify which loggers accept this log level
                let activeItems = self.loggerItems.filter { loggerItem in
                    logType.logLevel.rawValue >= loggerItem.getMinimumLogLevel().rawValue && logType.rawValue >= loggerItem.getMinimumLogType().rawValue
                }
                
                let group = DispatchGroup()
                let tracker = ResultTracker()
                
                activeItems.forEach { loggerItem in
                    group.enter()
                    self.extractTags(logTagger: loggerItem.logger.tagger, logType: logType, fileId: fileId, function: function, line: line) { loggerTags in
                        loggerItem.logger.log(message: LogMessage(message: message, logType: logType, tags: managerTags+loggerTags, metadata: metadata)) { success in
                            tracker.record(success)
                            group.leave()
                        }
                    }
                }
                
                group.notify(queue: self.queue) {
                    completion?(tracker.allSuccess)
                }
            }
        }
    }
    
    //MARK: Private operation API's
    
    private func extractTags(logTagger: LogTagger?, logType: LogType, fileId: StaticString, function: StaticString, line: UInt, completion: @escaping (@Sendable([Tag]) -> Void)) {
        if let logTagger = logTagger {
            logTagger.logTags(logType: logType) { logTags in
                completion(LogTagsExtractor().extract(logTags: logTags, fileId: fileId, function: function, line: line))
            }
        }
        else {
            completion([])
        }
    }
    
    //MARK: Log Tagger operations public API's
    
    public func addTag(_ logTag: any LogTag, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { self.logTagger.addTag(logTag, completion: completion) }
    }
    
    func removeTag(_ logTag: any LogTag, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { self.logTagger.removeTag(logTag, completion: completion) }
    }
    
    public func removeTag(identifier: String, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { self.logTagger.removeTag(identifier: identifier, completion: completion) }
    }

}

private final class ResultTracker: @unchecked Sendable {
    private var _allSuccess = true
    private let lock = NSLock()
    
    var allSuccess: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _allSuccess
    }
    
    func record(_ success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if !success { _allSuccess = false }
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
    
    func visit(externalTag: ExternalTag) {
        tags.append(Tag(identifier: externalTag.identifier, value: externalTag.value, tagType: .external))
    }
    
    func visit(internalTag: InternalTag) {
        let value: String
        switch internalTag.internalTagType {
        case .file:
            value = fileId
        case .function:
            value = function
        case .line:
            value = "\(line)"
        case .threadName:
            value = Utils.threadName()
        }
        tags.append(Tag(identifier: internalTag.identifier, value: value, tagType: .internal))
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
    let isDefault: Bool
    private let parent: LogManager
    private let minLogLevel: LogLevel
    private let minLogType: LogType
    private var loggerName: String {
        String(describing: type(of: logger))
    }
    
    init(logger: any ILogger, parent: LogManager, minLogLevel: LogLevel, minLogType: LogType, isDefault: Bool = false) {
        self.logger = logger
        self.parent = parent
        self.minLogLevel = minLogLevel
        self.minLogType = minLogType
        self.isDefault = isDefault
        super.init()
    }
    
    internal func getMinimumLogLevel() -> LogLevel {
        let minLogLevelKey = "\(parent.identifier).\(loggerName).\(LogManager.defaults.minimumLogLevel.rawValue)"
        if UserDefaults.standard.contains(key: minLogLevelKey) {
            return LogLevel.init(rawValue: UserDefaults.standard.integer(forKey: minLogLevelKey))!
        }
        else {
            return minLogLevel
        }
    }
    
    internal func getMinimumLogType() -> LogType {
        let minLogTypeKey = "\(parent.identifier).\(loggerName).\(LogManager.defaults.minimumLogType.rawValue)"
        if UserDefaults.standard.contains(key: minLogTypeKey) {
            return LogType.init(rawValue: UserDefaults.standard.integer(forKey: minLogTypeKey))!
        }
        else {
            return minLogType
        }
    }
}
