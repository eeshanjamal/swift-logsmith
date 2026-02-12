//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation
import OSLog

/// An ``ILogger`` compliant class that writes to the Apple Unified Logging System (`os.Logger`).
///
/// `OSLogger` directs log messages to the system console, making them viewable in Xcode's debug area and the `Console.app`. This logger is highly efficient and is the standard for system-level logging on Apple platforms. It automatically maps the library's ``LogType`` to the corresponding `OSLogType` (e.g., ``LogType.error`` maps to `OSLogType.error`).
///
/// **Default Behavior**
///
/// An `OSLogger` instance is configured as the default logger when you use ``LogSmith``, so you rarely need to instantiate it manually unless you are building a custom ``LogManager`` configuration or need to specify a custom subsystem and category.
///
/// **Usage with Custom Subsystem and Category**
///
/// ```swift
/// let networkingLogger = OSLogger(
///     subsystem: "com.mycompany.myapp",
///     category: "Networking",
///     logFormatter: .myCustomFormatter // Optional
/// )
///
/// LogSmith.replaceDefaultLogger(with: networkingLogger)
/// ```
@objcMembers
final class OSLogger: NSObject, ILogger {
    
    private let logger: Logger
    let formatter: LogFormatter
    let tagger: LogTagger?
    
    /// Creates a new `OSLogger` instance with the default subsystem and category.
    ///
    /// - Parameters:
    ///   - logFormatter: The ``LogFormatter`` to use for structuring the log message. Defaults to ``LogFormatter.default``.
    ///   - logTagger: An optional ``LogTagger`` to automatically add tags to the logs of this specific logger.
    init(logFormatter: LogFormatter = LogFormatter.default, logTagger: LogTagger? = nil) {
        logger = Logger()
        formatter = logFormatter
        tagger = logTagger
    }
    
    /// Creates a new `OSLogger` instance with a specific subsystem and category for granular filtering in the Console app.
    ///
    /// - Parameters:
    ///   - subsystem: An identifier for your app or a major module (e.g., "com.example.myapp").
    ///   - category: A specific functional area within the subsystem (e.g., "Authentication", "UI").
    ///   - logFormatter: The ``LogFormatter`` to use for structuring the log message. Defaults to ``LogFormatter.default``.
    ///   - logTagger: An optional ``LogTagger`` to automatically add tags to the logs of this specific logger.
    init(subsystem: String, category: String, logFormatter: LogFormatter = LogFormatter.default, logTagger: LogTagger? = nil) {
        logger = Logger(subsystem: subsystem, category: category)
        formatter = logFormatter
        tagger = logTagger
    }
    
    /// Formats the ``LogMessage`` and writes it to the system console using the appropriate `OSLogType`.
    ///
    /// It first convert the raw ``LogMessage`` into a formatted string. Then logs it by mapping the message's ``LogType`` to the corresponding function
    /// on the underlying `os.Logger` instance (e.g., `logger.notice`, `logger.error`).
    ///
    /// - Parameters:
    ///   - message: The ``LogMessage`` instance to be logged.
    ///   - completion: An optional closure called after the message is sent to the system. It returns `true` if the log was processed or `false` if the ``LogType`` was `.undefined`.
    func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)? = nil) {
        let formattedMessage = formatter.format(message: message)
        var didLog = true
        switch message.logType {
        case .undefined: 
            didLog = false
        case .none:
            logger.log("\(formattedMessage)")
        case .notice:
            logger.notice("\(formattedMessage)")
        case .info:
            logger.info("\(formattedMessage)")
        case .debug:
            logger.debug("\(formattedMessage)")
        case .trace:
            logger.trace("\(formattedMessage)")
        case .warning:
            logger.warning("\(formattedMessage)")
        case .error:
            logger.error("\(formattedMessage)")
        case .fault:
            logger.fault("\(formattedMessage)")
        case .critical:
            logger.critical("\(formattedMessage)")
        }
        completion?(didLog)
    }
    
}
