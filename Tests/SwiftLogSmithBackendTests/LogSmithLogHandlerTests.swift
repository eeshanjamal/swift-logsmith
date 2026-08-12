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
@testable import SwiftLogSmithBackend

/// Tests for the `swift-log` -> SwiftLogSmith bridge.
///
/// > Note: These never call `LoggingSystem.bootstrap`, which traps on a second call and would make the suite
/// order-dependent. Loggers are built with `Logger(label:factory:)` against an isolated `LogManager` instead.
final class LogSmithLogHandlerTests: XCTestCase {

    private static let label = "com.swiftlogsmith.tests"

    private var mockLogger: BackendMockLogger!
    private var manager: LogManager!

    override func setUp() {
        super.setUp()
        mockLogger = BackendMockLogger()
        manager = LogManager(identifier: "SwiftLogSmithBackendTests.\(UUID().uuidString)", defaultLogger: mockLogger)
    }

    override func tearDown() {
        mockLogger.setOnLog(nil)
        manager = nil
        mockLogger = nil
        super.tearDown()
    }

    /// Builds a `Logger` bound to this test's isolated manager.
    private func makeLogger(logLevel: Logger.Level = .trace,
                            metadata: Logger.Metadata = [:],
                            metadataProvider: Logger.MetadataProvider? = nil,
                            includesContext: Bool = true) -> Logger {
        let manager = self.manager!
        var logger = Logger(label: Self.label) { label in
            LogSmithLogHandler(label: label,
                               manager: manager,
                               logLevel: logLevel,
                               metadata: metadata,
                               metadataProvider: metadataProvider,
                               includesSwiftLogContextInMetadata: includesContext)
        }
        logger.logLevel = logLevel
        return logger
    }

    /// Runs `operation` and waits until `expectedCount` messages have reached the spy.
    private func logAndWait(expectedCount: Int = 1,
                            timeout: TimeInterval = 1.0,
                            logger: Logger? = nil,
                            _ operation: (Logger) -> Void) {
        let target = logger ?? makeLogger()
        expectCompletion(description: "messages delivered", fulfillmentCount: expectedCount, timeout: timeout) { fulfill in
            mockLogger.setOnLog { _ in fulfill() }
            operation(target)
        }
    }

    //MARK: Level mapping

    func testLogLevelMapping_ForEverySwiftLogLevel_ShouldMapOneToOne() {
        // Arrange
        let expected: [(Logger.Level, LogType)] = [
            (.trace, .trace),
            (.debug, .debug),
            (.info, .info),
            (.notice, .notice),
            (.warning, .warning),
            (.error, .error),
            (.critical, .critical)
        ]

        // Act & Assert
        for (level, logType) in expected {
            XCTAssertEqual(LogType(swiftLogLevel: level), logType, "\(level) should map to \(logType)")
        }
    }

    func testLog_WithEverySwiftLogLevel_ShouldReachLoggerWithMappedLogType() {
        // Arrange
        let levels: [Logger.Level] = [.trace, .debug, .info, .notice, .warning, .error, .critical]

        // Act
        logAndWait(expectedCount: levels.count, timeout: 2.0) { logger in
            for level in levels {
                logger.log(level: level, "message at \(level)")
            }
        }

        // Assert
        XCTAssertEqual(mockLogger.messages.map { $0.logType }, levels.map { LogType(swiftLogLevel: $0) })
    }

    //MARK: Filtering

    func testLog_WithLevelBelowLogLevel_ShouldNotReachLogger() {
        // Arrange
        let logger = makeLogger(logLevel: .error)
        let unexpected = XCTestExpectation(description: "unexpected delivery")
        unexpected.isInverted = true
        mockLogger.setOnLog { _ in unexpected.fulfill() }

        // Act
        logger.info("should be filtered by swift-log")
        logger.debug("should also be filtered")

        // Assert
        wait(for: [unexpected], timeout: 0.3)
        XCTAssertEqual(mockLogger.logCallCount, 0)
    }

    //MARK: Metadata

    func testResolveMetadata_WithNoPerStatementValues_ShouldReturnNil() {
        // Arrange & Act
        let resolved = LogSmithLogHandler.resolveMetadata(base: ["base": "value"],
                                                          provider: nil,
                                                          explicit: nil,
                                                          error: nil)

        // Assert — matches swift-log's own StreamLogHandler behaviour.
        XCTAssertNil(resolved)
    }

    func testResolveMetadata_WithAllThreeSources_ShouldApplySwiftLogPrecedence() {
        // Arrange
        let base: Logger.Metadata = ["key": "base", "fromBase": "yes"]
        let provider = Logger.MetadataProvider { ["key": "provider", "fromProvider": "yes"] }
        let explicit: Logger.Metadata = ["key": "explicit", "fromExplicit": "yes"]

        // Act
        let resolved = LogSmithLogHandler.resolveMetadata(base: base,
                                                          provider: provider,
                                                          explicit: explicit,
                                                          error: nil)

        // Assert — explicit beats provider beats base.
        XCTAssertEqual(resolved?["key"], "explicit")
        XCTAssertEqual(resolved?["fromBase"], "yes")
        XCTAssertEqual(resolved?["fromProvider"], "yes")
        XCTAssertEqual(resolved?["fromExplicit"], "yes")
    }

    func testResolveMetadata_WithError_ShouldContributeErrorEntries() {
        // Arrange
        struct SampleError: Error {}

        // Act
        let resolved = LogSmithLogHandler.resolveMetadata(base: [:],
                                                          provider: nil,
                                                          explicit: nil,
                                                          error: SampleError())

        // Assert
        XCTAssertNotNil(resolved?["error.message"])
        XCTAssertTrue("\(resolved?["error.type"] ?? "")".contains("SampleError"))
    }

    func testFlatten_WithNestedMetadata_ShouldRenderReadableStrings() {
        // Arrange
        let metadata: Logger.Metadata = [
            "plain": "value",
            "nested": .dictionary(["id": "7"]),
            "list": .array([.string("a"), .string("b")])
        ]

        // Act
        let flattened = LogSmithLogHandler.flatten(metadata)

        // Assert — nested values are rendered via Logger.MetadataValue's own description.
        XCTAssertEqual(flattened["plain"], "value")
        XCTAssertEqual(flattened["nested"], #"["id": "7"]"#)
        XCTAssertEqual(flattened["list"], #"["a", "b"]"#)
    }

    func testLog_WithNestedMetadata_ShouldPopulateFlatMetadataOnLogMessage() {
        // Arrange & Act
        logAndWait { logger in
            logger.error("Request failed", metadata: ["user": .dictionary(["id": "7"])])
        }

        // Assert
        XCTAssertEqual(mockLogger.lastLogMessage?.metadata["user"], #"["id": "7"]"#)
    }

    func testLog_WithContextEnabled_ShouldIncludeLabelAndSourceInMetadata() {
        // Arrange & Act
        logAndWait { logger in
            logger.info("hello")
        }

        // Assert
        let flat = mockLogger.lastLogMessage?.metadata
        XCTAssertEqual(flat?[LogSmithLogHandler.labelMetadataKey], Self.label)
        XCTAssertNotNil(flat?[LogSmithLogHandler.sourceMetadataKey])
    }

    func testLog_WithUserMetadataCollidingWithLabelKey_ShouldPreferUserValue() {
        // Arrange & Act
        logAndWait { logger in
            logger.info("hello", metadata: [Logger.Metadata.Key(LogSmithLogHandler.labelMetadataKey): "user-supplied"])
        }

        // Assert
        XCTAssertEqual(mockLogger.lastLogMessage?.metadata[LogSmithLogHandler.labelMetadataKey], "user-supplied")
    }

    func testLog_WithContextDisabled_ShouldOmitLabelAndSourceFromMetadata() {
        // Arrange & Act
        logAndWait(logger: makeLogger(includesContext: false)) { logger in
            logger.info("hello")
        }

        // Assert
        let flat = mockLogger.lastLogMessage?.metadata
        XCTAssertNil(flat?[LogSmithLogHandler.labelMetadataKey])
        XCTAssertNil(flat?[LogSmithLogHandler.sourceMetadataKey])
    }

    func testLog_WithFlatMetadata_ShouldRenderThroughDefaultFormatter() {
        // Arrange & Act
        logAndWait(logger: makeLogger(includesContext: false)) { logger in
            logger.error("Request failed", metadata: ["code": "404"])
        }

        // Assert — LogFormatter.default surfaces the flattened metadata with no extra configuration.
        let formatted = mockLogger.lastFormattedMessage ?? ""
        XCTAssertTrue(formatted.contains("Request failed"), formatted)
        XCTAssertTrue(formatted.contains("404"), formatted)

        // The symbolic "[E]" tag is registered by LogSmith's own initialiser, so it is deliberately absent
        // on an isolated LogManager. See SharedPipelineConcurrencyTests for the shared-pipeline behaviour.
        XCTAssertFalse(formatted.contains("[E]"), formatted)
    }

    //MARK: Payload

    func testLog_ShouldAttachSwiftLogPayloadPreservingStructure() {
        // Arrange & Act
        logAndWait { logger in
            logger.error("Request failed", metadata: ["user": .dictionary(["id": "7"])])
        }

        // Assert
        let payload = mockLogger.lastLogMessage?.payload as? SwiftLogPayload
        XCTAssertNotNil(payload, "swift-log messages should carry a SwiftLogPayload")
        XCTAssertEqual(payload?.label, Self.label)
        XCTAssertEqual(payload?.event.level, .error)
        XCTAssertEqual(payload?.event.message.description, "Request failed")
        // The nested structure survives untouched, unlike the flattened copy.
        XCTAssertEqual(payload?.resolvedMetadata?["user"], .dictionary(["id": "7"]))
    }

    func testLog_ViaLogManagerDirectly_ShouldNotAttachPayload() {
        // Arrange & Act — a first-party log through the same manager.
        expectCompletion(description: "log delivered") { fulfill in
            manager.log(message: "first-party", logType: .info) { _ in fulfill() }
        }

        // Assert — the payload cast is how a logger tells swift-log traffic apart.
        XCTAssertNil(mockLogger.lastLogMessage?.payload)
    }

    //MARK: Source location

    func testLog_ShouldForwardCallSiteRatherThanBridgeInternals() {
        // Arrange
        let tagger = LogTagger()
        expectCompletion(description: "tags registered", fulfillmentCount: 3) { fulfill in
            tagger.addTag(InternalTag(internalTagType: .file)) { _ in fulfill() }
            tagger.addTag(InternalTag(internalTagType: .function)) { _ in fulfill() }
            tagger.addTag(InternalTag(internalTagType: .line)) { _ in fulfill() }
        }
        mockLogger.tagger = tagger

        // Act
        logAndWait { logger in
            logger.info("locate me")
        }

        // Assert
        let tags = mockLogger.lastLogMessage?.tags ?? []
        let file = tags.first(where: { $0.identifier == LogTagIdentifiers.file })?.value
        let function = tags.first(where: { $0.identifier == LogTagIdentifiers.function })?.value

        XCTAssertEqual(file, "SwiftLogSmithBackendTests/LogSmithLogHandlerTests.swift",
                       "file should point at the call site, not inside the bridge")
        XCTAssertNotEqual(function, "log(event:)", "function should not be the bridge's own method")
    }

    //MARK: Handler value semantics

    func testMetadataSubscript_ShouldOnlyAffectItsOwnHandlerCopy() {
        // Arrange — swift-log requires handlers to behave as value types.
        let manager = self.manager!
        var first = Logger(label: "a") { LogSmithLogHandler(label: $0, manager: manager) }
        let second = first

        // Act
        first[metadataKey: "only-on-first"] = "yes"

        // Assert
        XCTAssertEqual(first[metadataKey: "only-on-first"], "yes")
        XCTAssertNil(second[metadataKey: "only-on-first"])
    }
}
