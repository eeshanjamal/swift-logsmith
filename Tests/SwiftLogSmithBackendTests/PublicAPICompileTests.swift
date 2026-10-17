//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import XCTest
import Logging
import SwiftLogSmith
import SwiftLogSmithBackend // Deliberately NOT `@testable`: this file may only see what a consumer sees.

/// Compile-time checks of the public API, written the way a consumer of the package would use it.
///
/// Every other test file in this target uses `@testable import SwiftLogSmithBackend`, which exposes `internal`
/// declarations and so cannot notice when something meant to be `public` is accidentally `internal`. Imports are
/// per file, so this file sees only the public surface: if an API stops being public, it stops compiling.
///
/// The README's "Using SwiftLogSmith as a swift-log Backend" snippets are mirrored below; keep them in sync.
///
/// > Note: Nothing here runs a bootstrap. `LoggingSystem.bootstrap` traps on a second call per process, so the
/// bootstrap functions are only referenced inside closures that are never invoked.
final class PublicAPICompileTests: XCTestCase {

    /// README: the payload-recovery snippet, with its `// ...` elision filled in by the members `ILogger` requires.
    private final class PayloadReadingLogger: ILogger {
        let tagger: LogTagger? = nil
        let formatter: LogFormatter = LogFormatter.default

        func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)?) {
            if let payload = message.payload as? SwiftLogPayload {
                _ = payload.label
                _ = payload.source
                _ = payload.event
                _ = payload.resolvedMetadata
            }
            completion?(true)
        }
    }

    func testPublicSurface_ShouldBeReachableWithoutTestableAccess() {
        // README: bootstrap against the shared pipeline, with every option, and against a caller-owned manager.
        let bootstrapShared: () -> Void = {
            LoggingSystem.bootstrapWithLogSmith()
        }
        let bootstrapWithOptions: () -> Void = {
            LoggingSystem.bootstrapWithLogSmith(defaultLogLevel: .info,
                                                metadataProvider: nil,
                                                includesSwiftLogContextInMetadata: false)
        }
        let bootstrapIsolated: () -> Void = {
            let manager = LogManager(identifier: "swift-log", defaultLogger: OSLogger())
            LoggingSystem.bootstrapWithLogSmith(manager: manager)
        }

        // The handler, through both public initialisers.
        let shared = LogSmithLogHandler(label: "com.example.shared")
        let isolated = LogSmithLogHandler(label: "com.example.isolated",
                                          manager: LogManager(identifier: "isolated", defaultLogger: OSLogger()),
                                          logLevel: .info,
                                          metadata: ["key": "value"],
                                          metadataProvider: nil,
                                          includesSwiftLogContextInMetadata: false)

        // Public constants and the level mapping.
        let metadataKeys = (LogSmithLogHandler.labelMetadataKey, LogSmithLogHandler.sourceMetadataKey)
        let mappedType = LogType(swiftLogLevel: .notice)

        // The logging statics take Strings, so a wrapper or facade can forward a call site it holds at runtime.
        let logWithRuntimeLocation: (String) -> Void = { location in
            LogSmith.logE("message", fileId: location, function: location, line: 1)
        }

        // Referencing the values is enough; none of the closures is ever invoked.
        _ = (bootstrapShared, bootstrapWithOptions, bootstrapIsolated, shared, isolated, metadataKeys, mappedType,
             PayloadReadingLogger.self, logWithRuntimeLocation)
    }
}
