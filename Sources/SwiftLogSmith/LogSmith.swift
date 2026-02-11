//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

/// The primary, easy-to-use entry point for logging in your application.
///
/// `LogSmith` is designed to get you logging immediately with zero configuration.
/// It comes pre-configured with a default `OSLogger` (a logger that utilizes Apple's unified logging system),
/// ensuring your logs are visible in the Console app or Xcode debug area right away.
///
/// **Key Features:**
/// - **Zero Config:** Just call `LogSmith.log("Hello")` and it works.
/// - **System Logging:** Includes a default `OSLogger` that outputs to the system console.
/// - **Symbolic Tags:** Automatically adds symbolic tags (e.g., `[I]` for Info, `[E]` for Error) to make logs visually distinct.
/// - **Extensible:** You can easily add more loggers (like ``FileLogger``), custom tags, or change the minimum log level.
///
/// **Basic Usage & Output:**
/// ```swift
/// // 1. Simple Log
/// LogSmith.log("Application launch")
/// // Output: Application launch
///
/// // 2. Error Log with Metadata
/// LogSmith.logE("Network request failed", metadata: ["code": "404"])
/// // Output: [E] Network request failed ["code": "404"]
///
/// // 3. Changing Log Level to allow only .error and .fault (Filtering)
/// LogSmith.setMinimumLogLevel(.error)
/// // Now an info log will produce no output
/// LogSmith.logI("This will be hidden")
/// // Output:
///
/// // 4. Adding Context (Tags)
/// let dateTag = ExternalTag(identifier: "Date", valueProvider: { Date().description })
/// LogSmith.addTag(dateTag)
/// LogSmith.logD("User action")
/// // Output: 2023-10-25 14:30:00 +0000 [D] User action
/// ```
@objcMembers
final class LogSmith: NSObject, LogManagerOperations, LogTaggerOperations {
    
    /// The timestamp when the `LogSmith` session was launched.
    /// This is used by `SessionRollingFrequency` to determine if a log file from a previous session needs to be rolled.
    internal static let sessionLaunchTime = Date()
    private static let shared = LogSmith()
    
    private let defaultManager = LogManager(identifier: String(describing: LogSmith.self), defaultLogger: OSLogger())
    private let queue = DispatchQueue(label: "com.swift.logsmith")
    
    private override init() {
        super.init()
        //Log type symbolic tag
        LogType.allCases.forEach { logType in
            guard !logType.stringValue.isEmpty && !logType.symbolicValue.isEmpty else { return }
            addTag(ExternalTag(identifier: logType.stringValue, value: logType.symbolicValue, logType: logType), completion: nil)
        }
    }
    
    //MARK: Log Manager operations internal API's
    
    internal func addLogger(newLogger: any ILogger, minLogLevel: LogLevel, minLogType: LogType, completion: (@Sendable (Bool) -> Void)?) {
        queue.async { self.defaultManager.addLogger(newLogger: newLogger, minLogLevel: minLogLevel, minLogType: minLogType, completion: completion) }
    }
    
    internal func removeLogger(logger: any ILogger, completion: (@Sendable (Bool) -> Void)?) {
        queue.async { self.defaultManager.removeLogger(logger: logger, completion: completion) }
    }
    
    internal func replaceDefaultLogger(with newLogger: any ILogger, minLogLevel: LogLevel, minLogType: LogType, completion: (@Sendable (Bool) -> Void)?) {
        queue.async { self.defaultManager.replaceDefaultLogger(with: newLogger, minLogLevel: minLogLevel, minLogType: minLogType, completion: completion) }
    }
    
    internal func setMinimumLogLevel(_ logLevel: LogLevel) {
        queue.async { self.defaultManager.setMinimumLogLevel(logLevel)}
    }
    
    internal func setMinimumLogType(_ logType: LogType) {
        queue.async { self.defaultManager.setMinimumLogType(logType)}
    }
    
    //MARK: Log Manager operations public API's
    
    /// Adds a new logger to the system.
    ///
    /// - Parameters:
    ///   - newLogger: The logger instance to add (e.g., `FileLogger`, `OSLogger`, or a custom implementation).
    ///   - minLogLevel: The minimum severity level this specific logger should handle. Defaults to `.default`.
    ///   - minLogType: The minimum specific log type this logger should handle. Defaults to `.none`.
    ///   - completion: An optional closure executed when the operation completes. Returns `true` if added successfully, `false` if it was already present.
    public static func addLogger(newLogger: any ILogger, minLogLevel: LogLevel = .default, minLogType: LogType = .none,_ completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.addLogger(newLogger: newLogger, minLogLevel: minLogLevel, minLogType: minLogType, completion: completion)
    }
    
    /// Removes an existing logger from the system.
    ///
    /// - Parameters:
    ///   - logger: The logger instance to remove.
    ///   - completion: An optional closure executed when the operation completes. Returns `true` if removed, `false` if the logger was not found.
    public static func removeLogger(logger: any ILogger,_ completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.removeLogger(logger: logger, completion: completion)
    }
    
    /// Replaces the current default system logger.
    ///
    /// Use this if you want to swap the default logger (which is initially `OSLogger`) with a customized one (e.g., one with a different formatter)
    /// while maintaining it as the "default" logger for the system.
    ///
    /// - Parameters:
    ///   - newLogger: The new logger instance to set as default.
    ///   - minLogLevel: The minimum severity level this specific logger should handle. Defaults to `.default`.
    ///   - minLogType: The minimum specific log type this logger should handle. Defaults to `.none`.
    ///   - completion: An optional closure executed when the operation completes.
    public static func replaceDefaultLogger(with newLogger: any ILogger, minLogLevel: LogLevel = .default, minLogType: LogType = .none, completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.replaceDefaultLogger(with: newLogger, minLogLevel: minLogLevel, minLogType: minLogType, completion: completion)
    }
    
    /// Sets the global minimum log level required for any message to be processed.
    ///
    /// Logs with a level lower than this will be ignored by *all* loggers managed by `LogSmith`.
    ///
    /// - Parameter logLevel: The minimum `LogLevel` (e.g., `.info`, `.error`).
    public static func setMinimumLogLevel(_ logLevel: LogLevel) {
        shared.setMinimumLogLevel(logLevel)
    }
    
    /// Sets the global minimum log type required for any message to be processed.
    ///
    /// Logs with a type lower than this will be ignored by *all* loggers managed by `LogSmith`.
    ///
    /// - Parameter logType: The minimum `LogType` (e.g., `.info`, `.critical`).
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
    
    /// Adds a global tag.
    ///
    /// The added tag will appear for all log messages of ``LogSmith`` If matches ``LogType``.
    /// They are useful for adding context like User IDs, Session IDs, or Environment info.
    ///
    /// > Note: Tags are unique by their identifier. If a tag with the same identifier already exists, the new tag will not be added.
    ///
    /// - Parameters:
    ///   - logTag: The `ExternalTag` or `InternalTag` to add.
    ///   - completion: An optional closure executed when the operation completes. Returns `true` if added.
    public static func addTag(_ logTag: any LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.addTag(logTag, completion: completion)
    }
    
    /// Removes a global tag by its instance.
    ///
    /// - Parameters:
    ///   - logTag: The specific tag instance to remove.
    ///   - completion: An optional closure executed when the operation completes.
    public static func removeTag(_ logTag: any LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.removeTag(logTag, completion: completion)
    }
    
    /// Removes a global tag by its identifier string.
    ///
    /// - Parameters:
    ///   - identifier: The unique identifier of the tag to remove.
    ///   - completion: An optional closure executed when the operation completes.
    public static func removeTag(identifier: String, completion: (@Sendable(Bool) -> Void)? = nil) {
        shared.removeTag(identifier: identifier, completion: completion)
    }
    
    //MARK: Log public API's
    
    /// Logs a message to all active loggers with `LogType.none`.
    ///
    /// This is the most basic logging level. Use it for general application flow messages that don't fit into more specific categories like debugging or error reporting. It's ideal for high-level events that are always relevant regardless of the current debugging state.
    ///
    /// - Parameters:
    ///   - message: The message string to log.
    ///   - metadata: A dictionary of key-value pairs to attach to this specific log message.
    ///   - completion: An optional completion handler called when the log has been processed by all active loggers. Returns `true` if successful.
    public static func log(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line, completion: (@Sendable (Bool) -> Void)? = nil) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .none, metadata: metadata, fileId: fileId, function: function, line: line, completion: completion) }
    }
    
    /// Logs a trace message to all active loggers with `LogType.trace`.
    ///
    /// Trace logs are even more detailed than debug logs. They are ideal for high-volume logs that help you follow the exact path of code execution, such as entry/exit points of functions, loop iterations, or state transitions in complex state machines.
    ///
    /// - Parameters:
    ///   - message: The message string to log.
    ///   - metadata: A dictionary of key-value pairs to attach to this specific log message.
    ///   - completion: An optional completion handler called when the log has been processed by all active loggers. Returns `true` if successful.
    public static func logT(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line, completion: (@Sendable (Bool) -> Void)? = nil) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .trace, metadata: metadata, fileId: fileId, function: function, line: line, completion: completion) }
    }
    
    /// Logs a debug message to all active loggers with `LogType.debug`.
    ///
    /// Debug logs provide detailed information that is useful for diagnosing issues. They are typically used to inspect the internal state of the application, variable values, or conditional branch execution. These logs are essential during development but might be too verbose for standard production monitoring.
    ///
    /// - Parameters:
    ///   - message: The message string to log.
    ///   - metadata: A dictionary of key-value pairs to attach to this specific log message.
    ///   - completion: An optional completion handler called when the log has been processed by all active loggers. Returns `true` if successful.
    public static func logD(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line, completion: (@Sendable (Bool) -> Void)? = nil) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .debug, metadata: metadata, fileId: fileId, function: function, line: line, completion: completion) }
    }
    
    /// Logs a notice message to all active loggers with `LogType.notice`.
    ///
    /// Notice logs are for events that are unusual or significant enough to be tracked, but are not errors. Examples include configuration changes, successful security audits, or major state transitions that are part of normal operation but worth noting.
    ///
    /// - Parameters:
    ///   - message: The message string to log.
    ///   - metadata: A dictionary of key-value pairs to attach to this specific log message.
    ///   - completion: An optional completion handler called when the log has been processed by all active loggers. Returns `true` if successful.
    public static func logN(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line, completion: (@Sendable (Bool) -> Void)? = nil) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .notice, metadata: metadata, fileId: fileId, function: function, line: line, completion: completion) }
    }
    
    /// Logs an informative message to all active loggers with `LogType.info`.
    ///
    /// Info logs highlight the progress of the application at a coarse-grained level. They provide a high-level overview of what the application is doing, such as "Service started", "User logged in", or "Background task completed". These are the standard logs you'd expect to see in a healthy production environment.
    ///
    /// - Parameters:
    ///   - message: The message string to log.
    ///   - metadata: A dictionary of key-value pairs to attach to this specific log message.
    ///   - completion: An optional completion handler called when the log has been processed by all active loggers. Returns `true` if successful.
    public static func logI(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line, completion: (@Sendable (Bool) -> Void)? = nil) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .info, metadata: metadata, fileId: fileId, function: function, line: line, completion: completion) }
    }
    
    /// Logs a warning message to all active loggers with `LogType.warning`.
    ///
    /// Warning logs indicate that something unexpected happened, but the application is still functioning. It's a "heads-up" that might require investigation to prevent future errors. Examples include using deprecated APIs, low disk space, or retrying a failed network request.
    ///
    /// - Parameters:
    ///   - message: The message string to log.
    ///   - metadata: A dictionary of key-value pairs to attach to this specific log message.
    ///   - completion: An optional completion handler called when the log has been processed by all active loggers. Returns `true` if successful.
    public static func logW(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line, completion: (@Sendable (Bool) -> Void)? = nil) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .warning, metadata: metadata, fileId: fileId, function: function, line: line, completion: completion) }
    }
    
    /// Logs an error message to all active loggers with `LogType.error`.
    ///
    /// Error logs are for issues that prevent a specific operation from completing successfully. While the application itself can still run, a user-facing feature might be broken or a background task failed. These logs usually require attention from developers or operations teams.
    ///
    /// - Parameters:
    ///   - message: The message string to log.
    ///   - metadata: A dictionary of key-value pairs to attach to this specific log message.
    ///   - completion: An optional completion handler called when the log has been processed by all active loggers. Returns `true` if successful.
    public static func logE(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line, completion: (@Sendable (Bool) -> Void)? = nil) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .error, metadata: metadata, fileId: fileId, function: function, line: line, completion: completion) }
    }
    
    /// Logs a critical message to all active loggers with `LogType.critical`.
    ///
    /// Critical logs indicate severe failures that might affect the entire application or system. These represent high-priority issues that often trigger alerts or emergency responses. Examples include primary database failure, loss of core infrastructure connectivity, or security breaches.
    ///
    /// - Parameters:
    ///   - message: The message string to log.
    ///   - metadata: A dictionary of key-value pairs to attach to this specific log message.
    ///   - completion: An optional completion handler called when the log has been processed by all active loggers. Returns `true` if successful.
    public static func logC(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line, completion: (@Sendable (Bool) -> Void)? = nil) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .critical, metadata: metadata, fileId: fileId, function: function, line: line, completion: completion) }
    }
    
    /// Logs a fault message to all active loggers with `LogType.fault`.
    ///
    /// Fault logs (often equivalent to 'Panic' or 'Fatal') represent the most severe level of error. They are used when the application encounters a state from which it cannot recover, such as data corruption or an impossible logic state. These logs are often the last thing recorded before a crash.
    ///
    /// - Parameters:
    ///   - message: The message string to log.
    ///   - metadata: A dictionary of key-value pairs to attach to this specific log message.
    ///   - completion: An optional completion handler called when the log has been processed by all active loggers. Returns `true` if successful.
    public static func logF(_ message: String, metadata: [String: String] = Dictionary(), fileId: StaticString = #fileID, function: StaticString = #function, line: UInt = #line, completion: (@Sendable (Bool) -> Void)? = nil) {
        shared.queue.async { shared.defaultManager.log(message: message, logType: .fault, metadata: metadata, fileId: fileId, function: function, line: line, completion: completion) }
    }
    
}

/// Represents different type (or severity) for logging.
///
/// Provides a granular way to categorize logs, which can be used for low-level filtering. It also provide visual identification (via string or symbolic value).
@objc public enum LogType: Int, CaseIterable, Sendable {
    
    /// This log type can be used for logs with no specified severity. It's useful for maintaining compatibility with systems where severity isn't provided.
    case undefined  = -1
    
    /// This log type can be used for general-purpose logging. It's useful for messages that do not require a specific severity level.
    case none       = 0
    
    /// This log type can be used for important application milestones. It's useful for events that should be noted during the application's lifecycle.
    case notice     = 1
    
    /// This log type can be used for standard application progress. It's useful for general information about the application's state.
    case info       = 2
    
    /// This log type can be used for diagnostic purposes. It's useful for capturing detailed information during development and debugging sessions.
    case debug      = 3
    
    /// This log type can be used for tracing program execution. It's useful for very fine-grained informational events and deep debugging.
    case trace      = 4
    
    /// This log type can be used for non-critical issues. It's useful for flagging potentially harmful situations that don't prevent the app from continuing.
    case warning    = 5
    
    /// This log type can be used for functional failures. It's useful for error events that might still allow the application to continue running.
    case error      = 6
    
    /// This log type can be used for severe failures. It's useful for identifying error events that likely lead to an application crash.
    case fault      = 7
    
    /// This log type can be used for high-priority issues. It's useful for critical conditions that require immediate attention.
    case critical   = 8
    
    /// A string representation of the log type.
    ///
    /// This returns a lowercase string corresponding to the enum case (e.g., "debug", "error").
    ///
    /// > Note: For `.undefined` and `.none`, it returns an empty string.
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
    
    /// A single-character symbolic representation of the log type.
    ///
    /// This typically returns the first letter of the `stringValue` in uppercase (e.g., "D" for debug, "E" for error).
    ///
    /// >Note: For cases with empty `stringValue`, it also returns an empty string.
    var symbolicValue: String {
        return stringValue.isEmpty ? stringValue : stringValue.prefix(1).uppercased()
    }
    
    /// A `LogLevel` value for the log type.
    ///
    /// This mapping is used for identifying the `LogLevel` where Multiple `LogType` might fall under a single `LogLevel`.
    ///
    /// For example, both `LogType.warning` and `LogType.error` map to `LogLevel.error`.
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

/// Represents different level (or severity) for logging.
///
/// Provides a broader way to categorize logs, which can be used for high-level filtering.
@objc public enum LogLevel: Int, CaseIterable, Sendable {
    
    /// This log level can be used for filtering logs with no severity. It's useful when no specific filtering threshold is desired.
    case undefined  = -1
    
    /// This log level can be used for filtering general-purpose logs. It's represented as a high-level filter for `LogType.none` & `LogType.notice`.
    case `default`  = 0
    
    /// This log level can be used for filtering informational messages. It's represented as a high-level filter for `LogType.info`.
    case info       = 1
    
    /// This log level can be used for filtering detailed messages. It's represented as a high-level filter for `LogType.debug` & `LogType.trace`.
    case debug      = 2
    
    /// This log level can be used for filtering non-fatal failures. It's represented as a high-level filter for `LogType.warning` & `LogType.error`.
    case error      = 3
    
    /// This log level can be used for filtering fatal failures. It's represented as a high-level filter for `LogType.fault` & `LogType.critical`.
    case fault      = 4
}

