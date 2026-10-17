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

/// A marker protocol for attaching arbitrary structured context to a ``LogMessage``.
///
/// ``LogMessage/metadata`` is a flat `[String: String]` dictionary, which is enough for most logs but
/// cannot represent richer, nested or strongly-typed context. `LogPayload` provides an escape hatch:
/// an integration can define its own payload type, hand it to ``LogManager/log(message:logType:metadata:payload:fileId:function:line:completion:)``,
/// and any ``ILogger`` can recover it with a conditional cast.
///
/// The protocol itself has no requirements — it exists purely so the payload can travel through the
/// logging pipeline without the core library needing to know its concrete type.
///
/// **Usage:**
/// ```swift
/// public final class RequestPayload: NSObject, LogPayload {
///     public let requestId: UUID
///     public init(requestId: UUID) { self.requestId = requestId }
/// }
///
/// // Inside a custom ILogger:
/// if let payload = message.payload as? RequestPayload {
///     print(payload.requestId)
/// }
/// ```
///
/// > Note: Conforming types must be `Sendable`, since a ``LogMessage`` may be delivered to loggers on
/// a different thread than the one that created it.
@objc public protocol LogPayload: Sendable {}

/// A data class that encapsulates all the raw information for a single log.
///
/// A `LogMessage` is created automatically by the system (and doesn't require manual creation by the user) which later passed to concrete implementations of logger's ``ILogger/log(message:completion:)`` method.
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
    /// Optional structured context attached by an integration, or `nil` for ordinary logs.
    ///
    /// Recover the concrete type with a conditional cast. See ``LogPayload``.
    public let payload: (any LogPayload)?

    internal init(message: String, logType: LogType, tags: [Tag], metadata: [String: String], payload: (any LogPayload)? = nil) {
        self.message = message
        self.logType = logType
        self.tags = tags
        self.metadata = metadata
        self.payload = payload
    }
}

