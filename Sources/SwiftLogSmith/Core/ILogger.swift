//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

/// A protocol that defines the essential requirements for a logger.
///
/// Any logger that conforms to `ILogger` can be added to ``LogSmith`` (or ``LogManager``) to receive and process log messages. This protocol provides a standardized way to handle log formatting, tagging, and output.
///
/// **Creating a Custom Logger**
///
/// To create a custom logger, you must implement this protocol. A simple implementation might look like this:
///
/// ```swift
/// class MyCustomLogger: ILogger {
///     let tagger: LogTagger?
///     let formatter: LogFormatter
///
///     init(formatter: LogFormatter = .default, tagger: LogTagger? = nil) {
///         self.formatter = formatter
///         self.tagger = tagger
///     }
///
///     func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)?) {
///         // 1. Format the message. Taggers will automatically included in it (if defined).
///         let formattedMessage = formatter.format(message: message)
///
///         // 2. Write to your desired destination (e.g., console, file, network)
///         print(formattedMessage)
///
///         // 3. Call the completion handler
///         completion?(true)
///     }
/// }
/// ```
@objc public protocol ILogger: Sendable {
    
    /// An optional ``LogTagger`` instance used to append contextual tags automatically to log messages.
    ///
    /// If provided, the logger will use this tagger to inject tags (e.g., User ID, Session ID) out of the box into the final log output.
    @objc var tagger: LogTagger? { get }
    
    /// A ``LogFormatter`` instance that determines the final structure and content of the log message.
    ///
    /// The formatter is responsible for converting a ``LogMessage`` instance into a string representation suitable for output.
    @objc var formatter: LogFormatter { get }
    
    /// Processes and records a log message.
    ///
    /// This is the core method where a logger implemetation receives message logging  request. Logger can format it using its ``formatter``, and writes it to a specific destination (e.g., console, file, or a remote server).
    /// - Parameters:
    ///   - message: The ``LogMessage`` instance to be logged.
    ///   - completion: An optional closure that is called after the log has been processed. It returns `true` if logging was successful.
    @objc func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)?)
}
