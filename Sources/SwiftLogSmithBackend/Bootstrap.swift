//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

public import Logging
public import SwiftLogSmith

extension LoggingSystem {

    /// Installs SwiftLogSmith as the `swift-log` backend for this process.
    ///
    /// After this call every `Logger(label:)` — including loggers created inside packages you depend on —
    /// delivers to the `ILogger` destinations registered with `LogSmith`,
    /// honouring the same filters, tags and formatters as first-party logging.
    ///
    /// ```swift
    /// LoggingSystem.bootstrapWithLogSmith()
    /// LogSmith.addLogger(newLogger: FileLogger())
    ///
    /// Logger(label: "com.example.network").error("Request failed", metadata: ["code": "404"])
    /// ```
    ///
    /// > Important: `swift-log` permits bootstrapping only once per process and traps on a second call. Call
    /// this as early as possible in your application's lifecycle, and never from a unit test — construct
    /// `Logger(label:factory:)` directly there instead.
    ///
    /// - Parameters:
    ///   - defaultLogLevel: The initial `logLevel` for every handler created. Defaults to `.trace`, which
    ///     leaves filtering to SwiftLogSmith's own minimums. Raise it to filter on the `swift-log` side —
    ///     see ``LogSmithLogHandler`` for why that is usually the better place to do it.
    ///   - metadataProvider: A provider consulted on each log statement, typically to pick up contextual
    ///     values such as a trace identifier. Defaults to `nil`.
    ///   - includesSwiftLogContextInMetadata: Whether each message's flat metadata should include the
    ///     originating logger label and source, so they appear in formatted output. Defaults to `true`.
    public static func bootstrapWithLogSmith(defaultLogLevel: Logger.Level = .trace,
                                             metadataProvider: Logger.MetadataProvider? = nil,
                                             includesSwiftLogContextInMetadata: Bool = true) {
        LoggingSystem.bootstrap({ label, provider in
            LogSmithLogHandler(label: label,
                               logLevel: defaultLogLevel,
                               metadataProvider: provider,
                               includesSwiftLogContextInMetadata: includesSwiftLogContextInMetadata)
        }, metadataProvider: metadataProvider)
    }

    /// Installs SwiftLogSmith as the `swift-log` backend, delivering to a caller-owned `LogManager`.
    ///
    /// Use this when `swift-log` traffic should stay on its own pipeline — with separate loggers, tags and
    /// thresholds — rather than joining the shared `LogSmith` configuration.
    ///
    /// ```swift
    /// let manager = LogManager(identifier: "swift-log", defaultLogger: OSLogger())
    /// LoggingSystem.bootstrapWithLogSmith(manager: manager)
    /// ```
    ///
    /// > Important: To have both pipelines write to the same destination, register the *same* logger instance
    /// on both. `FileLogger` serialises writes per `FileLoggerManager`
    /// instance rather than per directory, so two separately constructed file loggers aimed at one log
    /// directory will race on the same files.
    ///
    /// - Parameters:
    ///   - manager: The manager that receives all bridged messages.
    ///   - defaultLogLevel: The initial `logLevel` for every handler created. Defaults to `.trace`.
    ///   - metadataProvider: A provider consulted on each log statement. Defaults to `nil`.
    ///   - includesSwiftLogContextInMetadata: Whether each message's flat metadata should include the
    ///     originating logger label and source. Defaults to `true`.
    public static func bootstrapWithLogSmith(manager: LogManager,
                                             defaultLogLevel: Logger.Level = .trace,
                                             metadataProvider: Logger.MetadataProvider? = nil,
                                             includesSwiftLogContextInMetadata: Bool = true) {
        LoggingSystem.bootstrap({ label, provider in
            LogSmithLogHandler(label: label,
                               manager: manager,
                               logLevel: defaultLogLevel,
                               metadataProvider: provider,
                               includesSwiftLogContextInMetadata: includesSwiftLogContextInMetadata)
        }, metadataProvider: metadataProvider)
    }
}
