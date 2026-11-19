//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

public import Foundation

/// A protocol defining the core operations for managing a collection of loggers.
@objc internal protocol LogManagerOperations: Sendable {
    
    /// Adds a new logger to the manager.
    /// - Parameters:
    ///   - newLogger: Any ``ILogger`` compliant class instance to add.
    ///   - minLogLevel: The minimum ``LogLevel`` this logger should handle.
    ///   - minLogType: The minimum ``LogType`` this logger should handle.
    ///   - completion: An optional closure that returns `true` if the logger was added, or `false` if it was already present.
    @objc func addLogger(newLogger: any ILogger, minLogLevel: LogLevel, minLogType: LogType, completion: (@Sendable(Bool) -> Void)?)
    
    /// Removes a logger from the manager.
    /// - Parameters:
    ///   - logger: Any ``ILogger`` compliant class instance to remove.
    ///   - completion: An optional closure that returns `true` if the logger was found and removed.
    @objc func removeLogger(logger: any ILogger, completion: (@Sendable(Bool) -> Void)?)
    
    /// Replaces the default logger with a new one.
    /// - Parameters:
    ///   - newLogger: Any new ``ILogger`` compliant class instance to set as the default.
    ///   - minLogLevel: The minimum ``LogLevel`` the new default logger should handle.
    ///   - minLogType: The minimum ``LogType`` the new default logger should handle.
    ///   - completion: An optional closure that returns `true` if the default logger was successfully replaced.
    @objc func replaceDefaultLogger(with newLogger: any ILogger, minLogLevel: LogLevel, minLogType: LogType, completion: (@Sendable(Bool) -> Void)?)
    
    /// Sets the global minimum log level.
    ///
    /// This will set the minimum ``LogLevel`` of the manager (applicable to all loggers of it).
    /// - Parameter logLevel: The minimum ``LogLevel`` to apply.
    @objc func setMinimumLogLevel(_ logLevel: LogLevel)
    
    /// Sets the global minimum log type.
    ///
    /// This will set the minimum ``LogType`` of the manager (applicable to all loggers of it).
    /// - Parameter logType: The minimum ``LogType`` to apply.
    @objc func setMinimumLogType(_ logType: LogType)
}

extension UserDefaults {
    func contains(key: String) -> Bool {
        return object(forKey: key) != nil
    }
}

/// A thread-safe class that manages logging operations.
///
/// This class is a central component of logging mainly responsible for:
/// - Maintaining a collection of active loggers by conforming to `LogManagerOperations`.
/// - Filtering logs based on global and per-logger minimum ``LogLevel`` and ``LogType``.
/// - Asynchronously dispatching ``LogMessage`` objects to all relevant loggers.
/// - Managing a collection of log tags by conforming to `LogTaggerOperations`.
/// - Performing all operations on serial dispatch queue to ensure thread safety.
///
/// >Note: Usually, you don't need to interact directly with this class because all its operations are already facilitated by ``LogSmith``.
/// However, if your use case is not covered by ``LogSmith`` or you need multiple instances of `LogManager` to manage your logging then you can use it directly.
@objcMembers
public final class LogManager: NSObject, LogManagerOperations, LogTaggerOperations, @unchecked Sendable {
    
    internal enum defaults: String {
        case minimumLogLevel
        case minimumLogType
    }
    
    internal let identifier: String
    private var loggerItems: [LoggerItem]
    private let logTagger = LogTagger()
    private let queue = DispatchQueue(label: "com.swift.logsmith.logman.\(NSUUID().uuidString)")
    private var minLogLevel = LogLevel.all
    private var minLogType = LogType.none
    
    /// Creates a `LogManager` instance.
    ///
    /// >Note: You can't initialize the log manager instance properties `minimumLogLevel` & `minimumLogType` directly from the constructor. So, when creating a new instance they will be defaults to `LogLevel.all` & `LogType.none`.
    /// However, they can be later updated using ``setMinimumLogLevel(_:)`` & ``setMinimumLogType(_:)``.
    ///
    /// - Parameters:
    ///   - identifier: A unique string to identify this manager. It helps in storing instance specific properties (e.g., `minLogLevel` or `minLogType`) in persistance storage (such as `UserDefaults`).
    ///   - defaultLogger: Any ``ILogger`` compliant class instance to use as default logger. It's mandatory because log manager instances must always have at least one logger (as default).
    ///   - minLogLevel: The minimum ``LogLevel`` for the default logger. Defaults to `.all` (which means available to all log levels).
    ///   - minLogType: The minimum ``LogType`` for the default logger. Defaults to `.none` (which means available to all log types).
    public init(identifier: String, defaultLogger: any ILogger, minLogLevel: LogLevel = .all, minLogType: LogType = .none) {
        self.identifier = identifier
        self.loggerItems = []
        super.init()
        self.loggerItems.append(LoggerItem(logger: defaultLogger, parent: self, minLogLevel: minLogLevel, minLogType: minLogType, isDefault: true))
    }
    
    //MARK: Logger API's
    
    public func addLogger(newLogger: any ILogger, minLogLevel: LogLevel = .all, minLogType: LogType = .none, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            // Check for instance identity to prevent adding the exact same logger twice
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
    
    public func replaceDefaultLogger(with newLogger: any ILogger, minLogLevel: LogLevel = .all, minLogType: LogType = .none, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            if let index = self.loggerItems.firstIndex(where: { $0.isDefault }) {
                self.loggerItems.remove(at: index)
                self.loggerItems.insert(LoggerItem(logger: newLogger, parent: self, minLogLevel: minLogLevel, minLogType: minLogType, isDefault: true), at: index)
                completion?(true)
            } else {
                // Should technically never happen if initialized correctly, but safe to handle
                self.loggerItems.insert(LoggerItem(logger: newLogger, parent: self, minLogLevel: minLogLevel, minLogType: minLogType, isDefault: true), at: 0)
                completion?(true)
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
    
    /// Returns the minimum ``LogLevel`` of the manager. Will be overridden by a ``UserDefaults`` value if a valid raw value is provided.
    private func getMinimumLogLevel() -> LogLevel {
        let minLogLevelKey = "\(identifier).\(defaults.minimumLogLevel.rawValue)"
        if UserDefaults.standard.contains(key: minLogLevelKey), let overriddenLevel = LogLevel(rawValue: UserDefaults.standard.integer(forKey: minLogLevelKey)) {
            return overriddenLevel
        }
        else {
            return minLogLevel
        }
    }
    
    /// Returns the minimum ``LogType`` of the manager. Will be overridden by a ``UserDefaults`` value if a valid raw value is provided.
    private func getMinimumLogType() -> LogType {
        let minLogTypeKey = "\(identifier).\(defaults.minimumLogType.rawValue)"
        if UserDefaults.standard.contains(key: minLogTypeKey), let overriddenType = LogType(rawValue: UserDefaults.standard.integer(forKey: minLogTypeKey)) {
            return overriddenType
        }
        else {
            return minLogType
        }
    }
    
    //MARK: Log message public API
    
    /// Logs a message along with optional metadata and tags to all loggers.
    ///
    /// It's a main logging function that filters and dispatches a log message to all relevant loggers. It does that by:
    ///
    /// - First checking whether the message's `logType` meets the global minimums (`minLogLevel` and `minLogType`).
    /// - Extract tags from the manager's ``LogTagger`` matching message's `logType`.
    /// - Identifies all active loggers that can handle the message's `logType`.
    /// - Extract (logger-specific) tags for each active logger's ``LogTagger``.
    /// - Construct a new ``LogMessage`` for each logger with all provided & extracted info and dispatches to it.
    ///
    /// > Note: `fileId` and `function` are captured automatically by the compiler via `#fileID`/`#function`, so ordinary
    /// call sites need not provide them. Callers that receive source information at runtime — such as a logging facade
    /// bridging into this manager — can forward the original call site.
    ///
    /// > Note: The time of the call is captured as the first step, on the caller's thread, before the message is queued. It becomes
    /// ``LogMessage/timestamp`` and the value of any ``InternalTagType/timestamp`` tag, so it records when the log was called rather than when it was processed.
    ///
    /// - Parameters:
    ///   - message: The raw message string.
    ///   - logType: The severity type of the log.
    ///   - metadata: An optional dictionary to provide additional info for this log.
    ///   - payload: Optional structured context to attach to the resulting ``LogMessage``. See ``LogPayload``.
    ///   - fileId: The source file where the log was called.
    ///   - function: The source function where the log was called.
    ///   - line: The source line number where the log was called.
    ///   - completion: A closure that is called after all relevant loggers have processed the message. Returns `true` if all loggers succeeded.
    public func log(message: String, logType: LogType, metadata: [String: String] = Dictionary(), payload: (any LogPayload)? = nil, fileId: String = #fileID, function: String = #function, line: UInt = #line, completion: (@Sendable (Bool) -> Void)? = nil) {
        // Captured here, on the caller's thread, before the hop onto the manager's queue.
        let callSite = LogCallSite(fileId: fileId, function: function, line: line, timestamp: Date())
        log(message: message, logType: logType, metadata: metadata, payload: payload, callSite: callSite, completion: completion)
    }

    /// Logs a message whose call site has already been captured.
    ///
    /// ``LogSmith`` and the `SwiftLogSmithBackend` module call this directly, because they capture the call site before their own queue hop or
    /// metadata resolution; going through the public `log` would capture it again, later. It is `package`-scoped, so consumers of the library cannot call it.
    package func log(message: String, logType: LogType, metadata: [String: String], payload: (any LogPayload)?, callSite: LogCallSite, completion: (@Sendable (Bool) -> Void)?) {
        queue.async {
            // Check Manager Level
            guard logType.logLevel.rawValue >= self.getMinimumLogLevel().rawValue && logType.rawValue >= self.getMinimumLogType().rawValue else {
                completion?(true)
                return
            }

            // Identify which loggers accept this log level. This has to happen here, on the manager's queue: `loggerItems` is only
            // safe to read on it, and taking the snapshot now means a logger added or removed after this call doesn't change who receives it.
            let activeItems = self.loggerItems.filter { loggerItem in
                logType.logLevel.rawValue >= loggerItem.getMinimumLogLevel().rawValue && logType.rawValue >= loggerItem.getMinimumLogType().rawValue
            }

            // The completion runs on the tagger's queue, so it must only use values captured above, never the manager's mutable state.
            self.extractTags(logTagger: self.logTagger, logType: logType, callSite: callSite) { managerTags in

                let group = DispatchGroup()
                let tracker = ResultTracker()

                activeItems.forEach { loggerItem in
                    group.enter()
                    self.extractTags(logTagger: loggerItem.logger.tagger, logType: logType, callSite: callSite) { loggerTags in
                        loggerItem.logger.log(message: LogMessage(message: message, logType: logType, tags: managerTags+loggerTags, metadata: metadata, payload: payload, timestamp: callSite.timestamp)) { success in
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

    private func extractTags(logTagger: LogTagger?, logType: LogType, callSite: LogCallSite, completion: @escaping (@Sendable([Tag]) -> Void)) {
        if let logTagger = logTagger {
            let managerQueueLabel = queue.label
            logTagger.logTags(logType: logType) { logTags in
                completion(LogTagsExtractor(callSite: callSite, managerQueueLabel: managerQueueLabel).extract(logTags: logTags))
            }
        }
        else {
            completion([])
        }
    }
    
    //MARK: Log Tagger operations public API's
    
    /// Adds a global tag to the manager.
    ///
    /// The added tag will appear for all log messages of this manager If matches ``LogType``.
    /// They are useful for adding context like User IDs, Session IDs, or Environment info.
    ///
    /// > Note: Tags are unique by their identifier. If a tag with the same identifier already exists, the new tag will not be added.
    ///
    /// - Parameters:
    ///   - logTag: The `ExternalTag` or `InternalTag` to add.
    ///   - completion: An optional closure executed when the operation completes. Returns `true` if added.
    public func addTag(_ logTag: any LogTag, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { self.logTagger.addTag(logTag, completion: completion) }
    }
    
    /// Removes a global tag by its instance from the manager.
    ///
    /// - Parameters:
    ///   - logTag: The specific tag instance to remove.
    ///   - completion: An optional closure executed when the operation completes.
    public func removeTag(_ logTag: any LogTag, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { self.logTagger.removeTag(logTag, completion: completion) }
    }
    
    /// Removes a global tag by its identifier string from the manager.
    ///
    /// - Parameters:
    ///   - identifier: The unique identifier of the tag to remove.
    ///   - completion: An optional closure executed when the operation completes.
    public func removeTag(identifier: String, completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { self.logTagger.removeTag(identifier: identifier, completion: completion) }
    }

}

/// A thread-safe helper class to track the collective result of multiple asynchronous log operations.
private final class ResultTracker: @unchecked Sendable {
    private var _allSuccess = true
    private let lock = NSLock()
    
    /// Returns `true` only if all recorded results have been successful.
    var allSuccess: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _allSuccess
    }
    
    /// Records the result of a single operation. If `false`, the overall `allSuccess` will be set to `false`.
    func record(_ success: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if !success { _allSuccess = false }
    }
}

/// The context of a single log call, captured on the caller's thread before any queue hop.
///
/// Everything here describes the call itself, so it has to be read where the call happens: by the time the message reaches a
/// queue, the time has moved on. The values are immutable, so they can be carried across queues safely.
package struct LogCallSite: Sendable {
    /// The source file where the log was called.
    package let fileId: String
    /// The source function where the log was called.
    package let function: String
    /// The source line number where the log was called.
    package let line: UInt
    /// The moment the log was called.
    package let timestamp: Date
    /// The value of a ``InternalTagType/callerThreadName`` tag: the calling thread's name, `main`, or its thread ID in hex.
    package let threadName: String
    /// The value of a ``InternalTagType/callerQueueLabel`` tag: the label of the dispatch queue the caller is running.
    package let queueLabel: String
    /// The value of a ``InternalTagType/callerName`` tag: the calling thread's name if it has one, otherwise ``queueLabel``.
    package let callerName: String

    /// Captures the context of a log call. Call it on the caller's thread, since it also reads the current thread and queue.
    /// - Parameters:
    ///   - fileId: The source file where the log was called.
    ///   - function: The source function where the log was called.
    ///   - line: The source line number where the log was called.
    ///   - timestamp: The moment the log was called.
    package init(fileId: String, function: String, line: UInt, timestamp: Date) {
        self.fileId = fileId
        self.function = function
        self.line = line
        self.timestamp = timestamp

        let ownName = Thread.current.name.flatMap { $0.isEmpty ? nil : $0 }
        let queueLabel = DispatchQueue.currentLabel ?? ""
        self.queueLabel = queueLabel
        self.threadName = ownName ?? (Thread.isMainThread ? "main" : LogCallSite.currentThreadID())
        self.callerName = ownName ?? queueLabel
    }

    /// The system-wide ID of the current thread in hex, as Console and Instruments show it (e.g., `0x1102e33`).
    private static func currentThreadID() -> String {
        var threadID: UInt64 = 0
        #if swift(>=6.2)
            _ = unsafe pthread_threadid_np(nil, &threadID)
        #else
            _ = pthread_threadid_np(nil, &threadID)
        #endif
        return "0x" + String(threadID, radix: 16)
    }
}

/// A helper class that uses the visitor pattern to convert ``LogTag`` protocol instances into concrete ``Tag`` data instances.
///
/// > Note: This class is not internally thread-safe and is marked as `@unchecked Sendable` because each instance handles a single extraction,
/// on the serial queue of the ``LogTagger`` being read. It shouldn't be shared across concurrent domains before actually making it thread-safe.
private final class LogTagsExtractor: LogTagVisitor, @unchecked Sendable {
    
    /// Writes ``InternalTagType/timestamp`` tag values: ISO 8601 in UTC, as ``InternalTagType/valueFormat`` documents.
    private static let timestampValueFormatter = LockedDateFormatter(format: InternalTagType.timestampValueFormat, timeZone: TimeZone(identifier: "UTC")!)

    private var tags = [Tag]()
    private let callSite: LogCallSite
    private let managerQueueLabel: String

    /// Creates an extractor for one log call.
    /// - Parameters:
    ///   - callSite: The context of the log call, used for the values of ``InternalTag`` instances.
    ///   - managerQueueLabel: The label of the ``LogManager`` queue processing the log, used for any ``InternalTag`` of type `.managerQueueLabel`.
    init(callSite: LogCallSite, managerQueueLabel: String) {
        self.callSite = callSite
        self.managerQueueLabel = managerQueueLabel
    }
    
    /// Extracts and transforms a collection of ``LogTag`` into an array of ``Tag``.
    /// - Parameter logTags: The array of ``LogTag`` to process.
    /// - Returns: An array of concrete ``Tag`` objects.
    func extract(logTags: [any LogTag]) -> [Tag] {
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
            value = callSite.fileId
        case .function:
            value = callSite.function
        case .line:
            value = "\(callSite.line)"
        case .threadName, .callerName:
            value = callSite.callerName
        case .timestamp:
            value = LogTagsExtractor.timestampValueFormatter.string(from: callSite.timestamp)
        case .callerThreadName:
            value = callSite.threadName
        case .callerQueueLabel:
            value = callSite.queueLabel
        case .managerQueueLabel:
            value = managerQueueLabel
        }
        tags.append(Tag(identifier: internalTag.identifier, value: value, tagType: .internal))
    }
}


/// A private wrapper that holds an ``ILogger`` instance along with its specific configuration.
@objcMembers
private final class LoggerItem: NSObject, Sendable {
    
    /// The underlying logger instance.
    let logger: any ILogger
    /// A flag indicating if this is the default logger for the manager.
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
    
    /// Returns the minimum ``LogLevel`` for this specific logger. Will be overridden by a ``UserDefaults`` value if a valid raw value is provided.
    internal func getMinimumLogLevel() -> LogLevel {
        let minLogLevelKey = "\(parent.identifier).\(loggerName).\(LogManager.defaults.minimumLogLevel.rawValue)"
        if UserDefaults.standard.contains(key: minLogLevelKey), let overriddenLevel = LogLevel(rawValue: UserDefaults.standard.integer(forKey: minLogLevelKey)) {
            return overriddenLevel
        }
        else {
            return minLogLevel
        }
    }
    
    /// Returns the minimum ``LogType`` for this specific logger. Will be overridden by a ``UserDefaults`` value if a valid raw value is provided.
    internal func getMinimumLogType() -> LogType {
        let minLogTypeKey = "\(parent.identifier).\(loggerName).\(LogManager.defaults.minimumLogType.rawValue)"
        if UserDefaults.standard.contains(key: minLogTypeKey), let overriddenType = LogType(rawValue: UserDefaults.standard.integer(forKey: minLogTypeKey)) {
            return overriddenType
        }
        else {
            return minLogType
        }
    }
}

