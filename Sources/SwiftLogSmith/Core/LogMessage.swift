//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

public import Foundation

/// An enum that distinguishes between different implementations of ``LogTag`` by associating a type to each one.
@objc public enum TagType: Int, Sendable {
    
    /// This type represent ``InternalTag`` implementation.
    case `internal`
    /// This type represent ``ExternalTag`` implementation.
    case external
}

/// A concrete, internal-facing data instance representing a single tag.
///
/// This class holds the final, evaluated value of a ``LogTag`` instance along with its type. It gets created automatically by the system and doesn't require manual creation by the user.
/// It also gets associated automatically to the ``LogMessage`` instance which later can be used by the ``LogFormatter`` to format and represent.
@objcMembers
public final class Tag: NSObject, Sendable {
    
    /// The unique identifier for the tag.
    public let identifier: String
    /// The final, string-represented value of the tag.
    public let value: String
    /// The type of the tag, representing a specific implementation of ``LogType``
    public let tagType: TagType
    
    internal init(identifier: String, value: String, tagType: TagType) {
        self.identifier = identifier
        self.value = value
        self.tagType = tagType
    }
}

/// A data class that encapsulates all the raw information for a single log.
///
/// A `LogMessage` is created automatically by the system (and doesn't required manual creation by the user) which later passed to concrete implementations of Iogger's ``ILogger.log(message:completion:)`` method.
///
/// It serves as a container for a single log raw data (including message, severity, metadata, and all associated tags) before it gets processed by any implementation of ``ILogger``.
@objcMembers
public final class LogMessage: NSObject, Sendable {
    
    /// The raw (or non-formatted) log message string.
    public let message: String
    /// The severity type of the log.
    public let logType: LogType
    /// An array of tags associated with the log.
    public let tags: [Tag]
    /// A dictionary of additional data associated with the log.
    public let metadata: [String: String]
    
    internal init(message: String, logType: LogType, tags: [Tag], metadata: [String: String]) {
        self.message = message
        self.logType = logType
        self.tags = tags
        self.metadata = metadata
    }
}

