//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

/// A customizable formatter that transforms a ``LogMessage`` instance into a final string representation for output.
///
/// `LogFormatter` uses a modular "builder" pattern, allowing you to construct log output by assembling different parts (e.g., tags, message, metadata) in any order. Each part can be customized with prefixes, suffixes, and its own internal formatting.
///
/// **Default Format**
///
/// The default formatter produces logs in the following structure:
/// ```
/// Date [InternalTags] [LogType.symbolicValue] [ExternalTags] Message {Metadata}
/// ```
/// An example log output using the default format:
/// ```
/// 2023-10-27 10:30:00 +0000 [function: login, line: 123] [D] User logged in {"source": "LoginVC"}
/// ```
///
/// **Customization**
///
/// You can create a custom formatter to rearrange parts, change separators, or filter tags. For example, to produce the above log output using a custom formatter having the following structure:
/// ```
/// [LogType.symbolicValue] [InternalTags] [ExternalTags] Message
/// ```
/// Create a new one using `LogFormatter.Builder`:
/// ```swift
/// let myFormatter = LogFormatter.Builder()
///     .addTagsPart(prefix: "[", suffix: "] ", filter: { $0.identifier.uppercased() == "DEBUG" }) // Matches the symbolic tag
///     .addTagsPart(prefix: "[", format: { "\($0.identifier): \($0.value)" }, suffix: "] ", filter: { $0.tagType == .internal })
///     .addTagsPart(prefix: "[", separator: ", ", suffix: "] ")
///     .addMessagePart(prefix: "The ", suffix: ".")
///     .build()
/// ```
/// Now, the same log output will appear like the following:
/// ```
///[D] [function: login, line: 123] The User logged in.
/// ```
/// >Note: Even though the `LogMessage` have the date & metadata as well but just because custom formatter doesn't include it. It will not appear in the final log output.

@objcMembers
final class LogFormatter: NSObject, Sendable {
    
    private let parts: [any LogPart]
    private static let logTypeValues = LogType.allCases.map { $0.stringValue }
    
    /// A default formatter instance that provides a standard log structure.
    ///
    /// Format structure:
    /// ```
    /// Date [InternalTags] [LogType.symbolicValue] [ExternalTags] Message {Metadata}
    /// ```
    /// Example log output:
    /// ```
    /// 2023-10-27 10:30:00 +0000 [function: login, line: 123] [D] User logged in {"source": "LoginVC"}
    /// ```
    public static var `default`: LogFormatter {
            Builder()
            .addTagsPart(suffix: " ", filter: { $0.identifier == LogTagIdentifiers.date })
            .addTagsPart(prefix: "[", format: {"\($0.identifier): \($0.value)"}, separator: ", ", suffix: "] ", filter: { $0.tagType == .internal })
            .addTagsPart(prefix: "[", suffix: "] ", filter: { logTypeValues.contains($0.identifier) })
            .addTagsPart(prefix: "[", separator: ", ", suffix: "] ")
            .addMessagePart()
            .addMetadataPart(prefix: " ")
            .build()
    }

    private init(parts: [any LogPart]) {
        self.parts = parts
    }

    /// Formats a ``LogMessage`` into a single string based on the added log parts (e.g., tags, message, metadata).
    /// - Parameter message: The ``LogMessage`` instance containing the raw data.
    /// - Returns: A formatted string ready for output.
    public func format(message: LogMessage) -> String {
        let state = FormattingState(tags: message.tags)
        return parts.map { $0.format(logMessage: message, formattingState: state) }.joined()
    }
    
    // MARK: - Nested Builder Class
    
    /// A helper class for constructing a custom ``LogFormatter``.
    @objcMembers
    final class Builder: NSObject, @unchecked Sendable {
        
        private var parts: [any LogPart] = []
        private let lock = NSLock()
        
        /// Adds the log message content into the log format.
        ///
        /// - Parameters:
        ///   - prefix: Text to be append before the message. By default, it will be an empty string.
        ///   - format: A closure to define specific format for the message. By default, it will return the input message string.
        ///   - suffix: Text to be append after the message. By default, it will be an empty string.
        /// - Returns: The `Builder` instance for chaining.
        @discardableResult
        public func addMessagePart(prefix: String = "", format: @escaping @Sendable (String) -> String = { $0 }, suffix: String = "") -> Self {
            lock.lock()
            defer { lock.unlock() }
            self.parts.append(MessagePart(prefix: prefix, format: format, suffix: suffix))
            return self
        }
        
        /// Adds the log metadata dictionary into the log format.
        ///
        /// - Parameters:
        ///   - prefix: Text to be append before the metadata. By default, it will be an empty string.
        ///   - format: A closure to define specifc format for the metadata dictionary. By default, it will return the input metadata dictionary as string.
        ///   - suffix: Text to be append after the metadata. By default, it will be an empty string.
        /// - Returns: The `Builder` instance for chaining.
        @discardableResult
        public func addMetadataPart(prefix: String = "", format: @escaping @Sendable ([String: String]) -> String = { "\($0)" }, suffix: String = "") -> Self {
            lock.lock()
            defer { lock.unlock() }
            self.parts.append(MetadataPart(prefix: prefix, format: format, suffix: suffix))
            return self
        }

        /// Adds a subset of tags (based upon filter) into the log format.
        ///
        /// This method is highly flexible, allowing you to filter which tags are displayed and control their formatting.
        ///
        /// >Note: `LogMessage` instance tags which are consumed by first `addTagsPart` (based upon filter), will no longer be available to the subsequent `addTagsPart`.
        /// This behaviour will prevent tags from being displayed multiple times in the final formatted output.
        ///
        /// - Parameters:
        ///   - prefix: Text to be append before *this subset* of tags. By default, it will be an empty string.
        ///   - format: A closure to define specific format for *each individual tag*. By default, it will return the tag's value.
        ///   - separator: Text to insert between tags (if multiple tags are captured by the filter).
        ///   - suffix: Text to be append after *this subset* of tags. By default, it will be an empty string.
        ///   - filter: A closure to select which tags should be included in this part.
        /// - Returns: The `Builder` instance for chaining.
        @discardableResult
        public func addTagsPart(prefix: String = "", format: @escaping @Sendable (Tag) -> String = { $0.value }, separator: String = " ",
                                suffix: String = "", filter: @escaping @Sendable (Tag) -> Bool = { _ in true }) -> Self {
            lock.lock()
            defer { lock.unlock() }
            let tagPart = LogTagPart(prefix: prefix, format: format, separator: separator, suffix: suffix, filter: filter)
            self.parts.append(tagPart)
            return self
        }

        /// Finalizes the configuration and build a new ``LogFormatter`` instance.
        /// - Returns: A new ``LogFormatter`` instance with the configured parts.
        public func build() -> LogFormatter {
            lock.lock()
            defer { lock.unlock() }
            return LogFormatter(parts: self.parts)
        }
    }
}

/// Manages the state of tags during the formatting process to ensure a tag is only used once.
@objcMembers
internal final class FormattingState: NSObject, @unchecked Sendable {
    /// A mutable array of tags that have not yet been consumed by a `LogTagPart`.
    var unformattedTags: [Tag]
      
    init(tags: [Tag]) {
      self.unformattedTags = tags
    }
}

/// A protocol defining a single component (or "part") of a formatted log message.
@objc internal protocol LogPart: Sendable {
    
    /// Generates a formatted string for this part based on the log message and current formatting state.
    /// - Parameters:
    ///   - logMessage: The original ``LogMessage`` being formatted.
    ///   - formattingState: The current state, primarily used for tracking unconsumed tags.
    /// - Returns: A formatted string for this specific part.
    func format(logMessage: LogMessage, formattingState: FormattingState) -> String
}

/// A `LogPart` responsible for formatting the log message string.
@objcMembers
private final class MessagePart: NSObject, LogPart {
    
    private let prefix: String
    private let suffix: String
    private let format: @Sendable (String) -> String
    
    init(prefix: String = "", format: @escaping @Sendable (String) -> String = { $0 }, suffix: String = "") {
        self.prefix = prefix
        self.format = format
        self.suffix = suffix
    }
    
    func format(logMessage: LogMessage, formattingState: FormattingState) -> String {
        guard !logMessage.message.isEmpty else { return "" }
        let content = format(logMessage.message)
        return "\(prefix)\(content)\(suffix)"
    }
}

/// A `LogPart` responsible for formatting the log metadata dictionary.
@objcMembers
private final class MetadataPart: NSObject, LogPart {
    
    private let prefix: String
    private let suffix: String
    private let format: @Sendable ([String: String]) -> String
    
    init(prefix: String = "", format: @escaping @Sendable ([String : String]) -> String = { "\($0)" }, suffix: String = "") {
        self.prefix = prefix
        self.format = format
        self.suffix = suffix
    }
    
    func format(logMessage: LogMessage, formattingState: FormattingState) -> String {
        guard !logMessage.metadata.isEmpty else { return "" }
        let content = format(logMessage.metadata)
        return "\(prefix)\(content)\(suffix)"
    }
}

/// A `LogPart` responsible for filtering and formatting a subset of tags.
@objcMembers
private final class LogTagPart: NSObject, LogPart {
    
    private let prefix: String
    private let suffix: String
    private let filter: @Sendable (Tag) -> Bool
    private let format: @Sendable (Tag) -> String
    private let separator: String

    init(prefix: String = "", format: @escaping @Sendable (Tag) -> String = { $0.value }, separator: String = " ",
         suffix: String = "", filter: @escaping @Sendable (Tag) -> Bool = { _ in true }) {
        self.prefix = prefix
        self.format = format
        self.suffix = suffix
        self.filter = filter
        self.separator = separator
    }

    func format(logMessage: LogMessage, formattingState: FormattingState) -> String {
        let tagsToProcess = formattingState.unformattedTags.filter(filter)
        guard !tagsToProcess.isEmpty else { return "" }
        
        // Remove the tags that have been processed so they aren't used again.
        formattingState.unformattedTags.removeAll(where: { originalTag in
            tagsToProcess.contains(where: { $0 === originalTag })
        })

        let content = tagsToProcess.map(format).joined(separator: separator)
        return "\(prefix)\(content)\(suffix)"
    }
}
