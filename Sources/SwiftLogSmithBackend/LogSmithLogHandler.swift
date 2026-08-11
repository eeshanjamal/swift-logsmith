//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

public import Logging
public import SwiftLogSmith

/// A `swift-log` `LogHandler` that routes messages into SwiftLogSmith.
///
/// Installing this handler makes SwiftLogSmith the backend for `swift-log`, so every `Logger(label:)` in the
/// process — including loggers inside third-party packages you depend on — is delivered to your registered
/// `ILogger` destinations, honouring the same filters, tags and formatters as first-party
/// `LogSmith` calls.
///
/// **Usage:**
/// ```swift
/// import Logging
/// import SwiftLogSmith
/// import SwiftLogSmithBackend
///
/// LoggingSystem.bootstrapWithLogSmith()
/// LogSmith.addLogger(newLogger: FileLogger())
///
/// let logger = Logger(label: "com.example.network")
/// logger.error("Request failed", metadata: ["code": "404"])
/// // Delivered to OSLogger and FileLogger, just like LogSmith.logE would be.
/// ```
///
/// **Filtering.** `swift-log` performs its own level check before calling a handler, so the effective
/// threshold is the *stricter* of ``logLevel`` and SwiftLogSmith's own minimums. Because these two systems
/// order their low-severity cases differently (see below), prefer to filter bridged loggers with
/// ``logLevel`` — or `bootstrapWithLogSmith(defaultLogLevel:)` — and leave
/// `LogSmith.setMinimumLogType(_:)` at its permissive default.
///
/// > Warning: `LogType` orders its raw values `notice` < `info` < `debug` < `trace`, which is
/// the reverse of `swift-log`'s `trace` < `debug` < `info` < `notice`. Since SwiftLogSmith filters on those
/// raw values, calling `LogSmith.setMinimumLogType(.info)` will silently discard `swift-log` `.notice`
/// messages even though `.notice` is the more severe of the two.
///
/// **Structured metadata.** `swift-log` metadata is a tree, while `LogMessage.metadata` is a
/// flat `[String: String]`. The handler populates both: a stringified rendering lands in `metadata` so the
/// default formatter shows it with no configuration, and the untouched original travels in a
/// ``SwiftLogPayload`` on `LogMessage.payload`.
public struct LogSmithLogHandler: LogHandler {

    /// The metadata key under which the emitting `Logger`'s label is recorded.
    ///
    /// Only used when the handler is created with `includesSwiftLogContextInMetadata` enabled.
    public static let labelMetadataKey = "label"

    /// The metadata key under which the log's `swift-log` source (usually the module name) is recorded.
    ///
    /// Only used when the handler is created with `includesSwiftLogContextInMetadata` enabled.
    public static let sourceMetadataKey = "source"

    /// Where a handler sends the messages it receives.
    private enum Destination: Sendable {
        /// The shared `LogSmith` pipeline.
        case shared
        /// A caller-owned `LogManager`.
        case manager(LogManager)
    }

    /// The label of the `Logger` this handler was created for.
    public let label: String

    /// The minimum severity this handler emits.
    ///
    /// Defaults to `.trace` so that SwiftLogSmith's own configuration governs filtering. See the discussion
    /// on ``LogSmithLogHandler`` before raising it.
    public var logLevel: Logger.Level

    /// Baseline metadata applied to every message from this handler.
    ///
    /// Overridden by the `Logger.MetadataProvider`, which is in turn overridden by call-site metadata.
    public var metadata: Logger.Metadata

    /// The metadata provider consulted on each log statement, if any.
    public var metadataProvider: Logger.MetadataProvider?

    /// Whether ``label`` and the log's source are copied into the flat metadata dictionary.
    private let includesSwiftLogContextInMetadata: Bool

    private let destination: Destination

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { self.metadata[key] }
        set { self.metadata[key] = newValue }
    }

    /// Creates a handler that forwards into the shared `LogSmith` pipeline.
    ///
    /// Messages reach exactly the destinations, tags and thresholds configured through
    /// `LogSmith`, so no additional setup is required.
    ///
    /// - Parameters:
    ///   - label: The label of the `Logger` this handler serves.
    ///   - logLevel: The minimum severity to emit. Defaults to `.trace`, deferring to SwiftLogSmith's filters.
    ///   - metadata: Baseline metadata for every message from this handler. Defaults to empty.
    ///   - metadataProvider: A provider consulted on each log statement. Defaults to `nil`.
    ///   - includesSwiftLogContextInMetadata: Whether to copy the logger label and source into the flat
    ///     metadata dictionary under ``labelMetadataKey`` and ``sourceMetadataKey``, so they appear in
    ///     formatted output. Both remain available on ``SwiftLogPayload`` regardless. Defaults to `true`.
    public init(label: String,
                logLevel: Logger.Level = .trace,
                metadata: Logger.Metadata = [:],
                metadataProvider: Logger.MetadataProvider? = nil,
                includesSwiftLogContextInMetadata: Bool = true) {
        self.label = label
        self.logLevel = logLevel
        self.metadata = metadata
        self.metadataProvider = metadataProvider
        self.includesSwiftLogContextInMetadata = includesSwiftLogContextInMetadata
        self.destination = .shared
    }

    /// Creates a handler that forwards into a caller-owned `LogManager`.
    ///
    /// Use this to keep `swift-log` traffic on a separate pipeline with its own loggers, tags and thresholds,
    /// isolated from the shared `LogSmith` configuration.
    ///
    /// > Important: If both pipelines should write to the same place, register the *same* logger instance on
    /// both rather than constructing a second one. `FileLogger` serialises writes per
    /// `FileLoggerManager` instance, not per directory, so two managers pointed at one log
    /// directory will race on the same files.
    ///
    /// - Parameters:
    ///   - label: The label of the `Logger` this handler serves.
    ///   - manager: The manager to deliver messages to.
    ///   - logLevel: The minimum severity to emit. Defaults to `.trace`, deferring to the manager's filters.
    ///   - metadata: Baseline metadata for every message from this handler. Defaults to empty.
    ///   - metadataProvider: A provider consulted on each log statement. Defaults to `nil`.
    ///   - includesSwiftLogContextInMetadata: Whether to copy the logger label and source into the flat
    ///     metadata dictionary. Defaults to `true`.
    public init(label: String,
                manager: LogManager,
                logLevel: Logger.Level = .trace,
                metadata: Logger.Metadata = [:],
                metadataProvider: Logger.MetadataProvider? = nil,
                includesSwiftLogContextInMetadata: Bool = true) {
        self.label = label
        self.logLevel = logLevel
        self.metadata = metadata
        self.metadataProvider = metadataProvider
        self.includesSwiftLogContextInMetadata = includesSwiftLogContextInMetadata
        self.destination = .manager(manager)
    }

    public func log(event: LogEvent) {
        let resolvedMetadata = Self.resolveMetadata(base: self.metadata,
                                                    provider: self.metadataProvider,
                                                    explicit: event.metadata,
                                                    error: event.error)
        let payload = SwiftLogPayload(label: self.label, event: event, resolvedMetadata: resolvedMetadata)
        let logType = LogType(swiftLogLevel: event.level)
        var flatMetadata = Self.flatten(resolvedMetadata)

        if self.includesSwiftLogContextInMetadata {
            // Inserted only when absent so that user-supplied metadata always wins on a key collision.
            flatMetadata[Self.labelMetadataKey] = flatMetadata[Self.labelMetadataKey] ?? self.label
            flatMetadata[Self.sourceMetadataKey] = flatMetadata[Self.sourceMetadataKey] ?? event.source
        }

        switch self.destination {
        case .shared:
            LogSmith.log(event.message.description,
                         logType: logType,
                         metadata: flatMetadata,
                         payload: payload,
                         fileId: event.file,
                         function: event.function,
                         line: event.line)
        case .manager(let manager):
            manager.log(message: event.message.description,
                        logType: logType,
                        metadata: flatMetadata,
                        payload: payload,
                        fileId: event.file,
                        function: event.function,
                        line: event.line)
        }
    }

    //MARK: Metadata handling

    /// Merges the three metadata sources following `swift-log`'s documented precedence.
    ///
    /// Base metadata is overridden by the provider, which is overridden by call-site metadata. An associated
    /// error contributes `error.message` and `error.type`. Returns `nil` when the statement carried nothing
    /// beyond the handler's baseline, matching the behaviour of `swift-log`'s own `StreamLogHandler`.
    internal static func resolveMetadata(base: Logger.Metadata,
                                         provider: Logger.MetadataProvider?,
                                         explicit: Logger.Metadata?,
                                         error: (any Error)?) -> Logger.Metadata? {
        var metadata = base
        let provided = provider?.get() ?? [:]

        guard !provided.isEmpty || !(explicit ?? [:]).isEmpty || error != nil else {
            // Nothing beyond the baseline was supplied for this statement.
            return nil
        }

        if !provided.isEmpty {
            metadata.merge(provided, uniquingKeysWith: { _, provided in provided })
        }

        if let explicit, !explicit.isEmpty {
            metadata.merge(explicit, uniquingKeysWith: { _, explicit in explicit })
        }

        if let error {
            metadata["error.message"] = "\(error)"
            metadata["error.type"] = "\(String(reflecting: type(of: error)))"
        }

        return metadata
    }

    /// Renders structured metadata into SwiftLogSmith's flat `[String: String]` form.
    ///
    /// Nested dictionaries and arrays are rendered through `Logger.MetadataValue`'s own `description`, so a
    /// value of `.dictionary(["id": "7"])` becomes the string `["id": "7"]`. They remain readable but stop
    /// being traversable; the untouched original is preserved on ``SwiftLogPayload/resolvedMetadata``.
    internal static func flatten(_ metadata: Logger.Metadata?) -> [String: String] {
        guard let metadata else { return [:] }
        return metadata.mapValues { $0.description }
    }
}
