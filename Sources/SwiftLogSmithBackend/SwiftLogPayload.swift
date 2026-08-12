//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

public import Foundation
public import Logging
public import SwiftLogSmith

/// The structured `swift-log` context attached to every `LogMessage` produced by ``LogSmithLogHandler``.
///
/// `LogMessage.metadata` is a flat `[String: String]` dictionary, so it cannot represent
/// `swift-log`'s nested metadata (`Logger.MetadataValue` can hold dictionaries and arrays) nor its `label`
/// and `source`. This payload carries all of it through the pipeline untouched, so a custom
/// `ILogger` can consume the original structure rather than a stringified rendering.
///
/// Recover it with a conditional cast inside your logger:
///
/// ```swift
/// func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)?) {
///     if let payload = message.payload as? SwiftLogPayload {
///         print(payload.label)                  // "com.example.network"
///         print(payload.resolvedMetadata ?? [:]) // nested structure preserved
///     }
///     completion?(true)
/// }
/// ```
///
/// > Note: `LogMessage.payload` is `nil` for logs made directly through `LogSmith`,
/// so the cast doubles as a way to tell `swift-log` traffic apart from first-party logging.
public final class SwiftLogPayload: NSObject, LogPayload {

    /// The label of the `Logger` that emitted this message, e.g. `"com.example.network"`.
    public let label: String

    /// The source where the log originated — usually the module name.
    public let source: String

    /// The original, unmodified `swift-log` event.
    ///
    /// Includes the raw `Logger.Message`, the per-call metadata, the associated error (if any) and the
    /// full source location.
    public let event: LogEvent

    /// The effective metadata after merging, or `nil` when the log carried no per-statement metadata.
    ///
    /// Merge precedence follows `swift-log`'s own convention: the handler's base metadata is overridden by
    /// the `Logger.MetadataProvider`, which is in turn overridden by the metadata passed at the call site.
    /// Any associated error contributes `error.message` and `error.type` entries.
    ///
    /// This differs from ``event`` — `event.metadata` holds only what was supplied at the call site.
    public let resolvedMetadata: Logger.Metadata?

    internal init(label: String, event: LogEvent, resolvedMetadata: Logger.Metadata?) {
        self.label = label
        self.source = event.source
        self.event = event
        self.resolvedMetadata = resolvedMetadata
        super.init()
    }
}
