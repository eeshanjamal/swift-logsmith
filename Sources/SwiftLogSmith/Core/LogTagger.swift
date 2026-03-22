//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

public import Foundation

/// A protocol that defines a tag, which adds contextual information to a log message.
///
/// This protocol provides a standardized way to handle tags in your log messages. It helps in providing additional context to your logs (e.g., log type or timestamp).
///
/// It can be tied to specific ``LogType`` logs. It also helps in filtering log data with specific context. For example, logs with ``LogType.error`` or logs within an hour timestamp.
@objc public protocol LogTag: Sendable {
    
    /// A string to uniquely identify the tag
    var identifier: String {get}
    
    /// The ``LogType`` this tag is associated with.
    ///
    /// If set to a specific type (e.g., `.error`), the tag will only be applied to logs of that type. If `.undefined`, it applies to all log types.
    var logType: LogType {get}
    
    /// This function helps in type-safe processing of the tag.
    /// - Parameter logTagVisitor: The ``LogTagVisitor`` instance that will process this tag.
    func visit(logTagVisitor: any LogTagVisitor)
}

/// Common log tag identifier constants.
///
/// This class contains some common log tag identifiers (as static constants) which can be used when creating any ``LogTag`` compliant class instance.
@objcMembers
public final class LogTagIdentifiers: NSObject, Sendable {
    /// Identifier for a timestamp tag.
    public static let date = "date"
    /// Identifier for a source file path tag.
    public static let file = "file"
    /// Identifier for a source function name tag.
    public static let function = "function"
    /// Identifier for a source line number tag.
    public static let line = "line"
    /// Identifier for a thread name tag.
    public static let threadName = "threadName"
}

/// This enum represents the different types of implicit tags an ``InternalTag`` instance can generate.
@objc public enum InternalTagType: Int, Sendable {
    
    /// An internal tag type to represent the relative file source path.
    ///
    /// It request the relative source path (e.g., package/filename) of file where a log statement is written along with this tag type.
    case file
    /// An internal tag type to represent the function name.
    ///
    /// It request the name of the function where a log statement is written along with this tag type.
    case function
    /// An internal tag type to represent the line number.
    ///
    /// It request the line number (within a file) where a log statement is written along with this tag type.
    case line
    /// An internal tag type to represent the name of the current thread.
    ///
    /// It request the name of the current thread where a log statement is executed along with this tag type.
    case threadName
    
    /// The string value of the internal tag type.
    public var stringValue: String {
        switch self {
        case .file:
            return LogTagIdentifiers.file
        case .function:
            return LogTagIdentifiers.function
        case .line:
            return LogTagIdentifiers.line
        case .threadName:
            return LogTagIdentifiers.threadName
        }
    }
}

/// A utility class providing Objective-C compatible access to `InternalTagType` properties.
@objcMembers
public final class InternalTagTypeUtils: NSObject, Sendable {
    
    /// Returns the string value of an `InternalTagType`.
    /// - Parameter tagType: The `InternalTagType` enum.
    /// - Returns: The string representation (e.g., "file" for .file).
    public static func stringValue(for tagType: InternalTagType) -> String {
        return tagType.stringValue
    }
}

/// A protocol for visiting concrete implementations of ``LogTag``.
///
/// This protocol allows to process different `LogTag` implementations (e.g., `InternalTag`, `ExternalTag`) in a type-safe manner without casting.
@objc public protocol LogTagVisitor: Sendable {
    
    /// Processes an ``InternalTag``.
    /// - Parameter internalTag: The ``InternalTag`` instance to visit.
    func visit(internalTag: InternalTag)
    
    /// Processes an ``ExternalTag``.
    /// - Parameter externalTag: The ``ExternalTag`` instance to visit.
    func visit(externalTag: ExternalTag)
}

/// A concrete implemenation of ``LogTag`` for creating user-defined, dynamic data tags.
///
/// This type of log tag can be used to capture contextual information that is specific to your application's domain. The value of the tag can be provided as a static string or as a dynamic closure (which is evaluated each time the log is processed). This is useful for capturing transient state like the current date, user ID or network status.
///
/// **Usage:**
/// ```swift
/// // Static value
/// let envTag = ExternalTag(identifier: "environment", value: "staging")
///
/// // Dynamic value
/// let userTag = ExternalTag(identifier: LogTagIdentifiers.date, valueProvider: { Date().description })
/// ```
@objcMembers
public final class ExternalTag: NSObject, LogTag {
    
    public let identifier: String
    public let logType: LogType
    /// A string representing the static or dynamic value of the tag.
    public var value: String {
        return valueProvider()
    }
    
    private let valueProvider: @Sendable () -> String
    
    /// Creates an `ExternalTag` instance with a static string value.
    /// - Parameters:
    ///   - identifier: The unique identifier for the tag.
    ///   - value: The static string value of the tag.
    ///   - logType: The ``LogType`` this tag should apply to. Defaults to `.undefined` (available to all log types).
    public init(identifier: String, value: String, logType: LogType = .undefined){
        self.identifier = identifier
        self.logType = logType
        self.valueProvider = { value }
    }
    
    /// Creates an `ExternalTag` instance with a dynamically evaluated value.
    /// - Parameters:
    ///   - identifier: The unique identifier for the tag.
    ///   - valueProvider: A closure that returns the tag's value. This closure is executed each time ``value`` is requested.
    ///   - logType: The ``LogType`` this tag should apply to. Defaults to `.undefined` (which means available to all log types).
    public init(identifier: String, valueProvider: @escaping @Sendable () -> String, logType: LogType = .undefined){
        self.identifier = identifier
        self.logType = logType
        self.valueProvider = valueProvider
    }
    
    public func visit(logTagVisitor: any LogTagVisitor) {
        logTagVisitor.visit(externalTag: self)
    }
}

/// A concrete implemetation of ``LogTag`` for automatically capturing compile-time source & runtime system-level metadata.
///
/// This type of log tag can be used by the logging system to capture details about the log source call site info (e.g., file, function or  line) and log execution info (e.g., thread name).
/// These tags are typically generated automatically by the system by providing the intended `InternalLogType`.
@objcMembers
public final class InternalTag: NSObject, LogTag {
    
    public let identifier: String
    public let logType: LogType
    /// An enum representing the requested tag type for this internal tag.
    public let internalTagType: InternalTagType
    
    /// Creates an `InternalTag` instance.
    /// - Parameters:
    ///   - internalTagType: The ``InternalTagType`` this tag represents (e.g., ``.file``, ``.line``).
    ///   - logType: The ``LogType`` this tag should apply to. Defaults to `.undefined` (which means available to all log types).
    public init(internalTagType: InternalTagType, logType: LogType = .undefined) {
        self.identifier = internalTagType.stringValue
        self.logType = logType
        self.internalTagType = internalTagType
    }
    
    public func visit(logTagVisitor: any LogTagVisitor) {
        logTagVisitor.visit(internalTag: self)
    }
}

/// A protocol defining the core operations for managing a collection of log tags.
@objc internal protocol LogTaggerOperations: Sendable {

    /// Adds a tag to the collection.
    /// - Parameters:
    ///   - logTag: Any ``LogTag`` compliant class instance to add.
    ///   - completion: An optional closure that returns `true` if the tag was added, or `false` if a tag with the same identifier already exists.
    @objc func addTag(_ logTag: any LogTag, completion: (@Sendable(Bool) -> Void)?)
    
    /// Removes a tag from the collection by its instance.
    /// - Parameters:
    ///   - logTag: Any ``LogTag`` compliant class instance to remove.
    ///   - completion: An optional closure that returns `true` if a matching tag was found and removed.
    @objc func removeTag(_ logTag: any LogTag, completion: (@Sendable(Bool) -> Void)?)
    
    /// Removes a tag from the collection by its identifier.
    /// - Parameters:
    ///   - identifier: The unique identifier of the tag to remove.
    ///   - completion: An optional closure that returns `true` if a matching tag was found and removed.
    @objc func removeTag(identifier: String, completion: (@Sendable(Bool) -> Void)?)
}

/// A manager to manage a collection of ``LogTag`` instances in a thread-safe manner.
///
/// It's a ``LogTaggerOperations`` compliant class providing the necessary tag collection operations.
/// It ensures that all operations on its instance are internally performed on a serial dispatch queue, making it safe to use from multiple threads.
@objcMembers
public final class LogTagger: NSObject, LogTaggerOperations {
    
    private let logTagCollection: LogTagCollection
    private let queue: DispatchQueue
    
    public override init() {
        queue = DispatchQueue(label: "com.swift.logtag.\(NSUUID().uuidString)")
        logTagCollection = LogTagCollection()
        super.init()
    }
    
    //MARK: Log API's
    
    public func addTag(_ logTag: any LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            let result = self.logTagCollection.addTag(logTag)
            completion?(result)
        }
    }
    
    public func removeTag(_ logTag: any LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            let result = self.logTagCollection.removeTag(logTag.identifier)
            completion?(result)
        }
    }
    
    public func removeTag(identifier: String, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            let result = self.logTagCollection.removeTag(identifier)
            completion?(result)
        }
    }
    
    /// Retrieves all tags that apply to a provided ``LogType``.
    ///
    /// >Note: This function return all tags having the provided `logType` as well as tags where `logType` is `.undefined`.
    /// - Parameters:
    ///   - logType: The specific ``LogType`` for tags have to be filtered.
    ///   - completion: A closure that receives an array of matching ``LogTag`` instances.
    public func logTags(logType: LogType, completion: @escaping (@Sendable([any LogTag]) -> Void)) {
        queue.async {
            completion(self.logTagCollection.logTags.filter { $0.logType == .undefined || $0.logType == logType })
        }
    }

}

/// A private class that provides the underlying storage for `LogTagger`.
private final class LogTagCollection: NSObject, @unchecked Sendable {
    
    private var _logTags: [any LogTag]
    private let lock = NSLock()
    
    /// The array of ``LogTag`` instances.
    var logTags: [any LogTag] {
        lock.lock()
        defer { lock.unlock() }
        return _logTags
    }
    
    override init() {
        _logTags = []
        super.init()
    }
    
    init(_ logTags: [any LogTag]) {
        _logTags = Array(logTags)
        super.init()
    }
    
    /// Adds a tag to the collection if an entry with the same identifier does not already exist.
    /// - Parameter logTag: The ``LogTag`` to add.
    /// - Returns: `true` if the tag was added, `false` otherwise.
    func addTag(_ logTag: any LogTag) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _logTags.first(where: {$0.identifier == logTag.identifier}) != nil {
            return false
        }
        else {
            _logTags.append(logTag)
            return true
        }
    }
    
    /// Removes a tag from the collection by its identifier.
    /// - Parameter identifier: The unique identifier of the tag to remove.
    /// - Returns: `true` if a matching tag was found and removed, `false` otherwise.
    func removeTag(_ identifier: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let tagIndex = _logTags.firstIndex(where: {$0.identifier == identifier}) {
            _logTags.remove(at: tagIndex)
            return true
        }
        else {
            return false
        }
    }
    
}
