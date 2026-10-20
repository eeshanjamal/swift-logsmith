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

    func testResolveMetadata_WithOnlyBaselineMetadata_ShouldReturnBaseline() {
        // Arrange & Act
        let resolved = LogSmithLogHandler.resolveMetadata(base: ["base": "value"],
                                                          provider: nil,
                                                          explicit: nil,
                                                          error: nil)

        // Assert — a statement with nothing of its own must still carry the handler's baseline.
        XCTAssertEqual(resolved, ["base": "value"])
    }

    func testResolveMetadata_WithNoMetadataAtAll_ShouldReturnEmpty() {
        // Arrange & Act
        let resolved = LogSmithLogHandler.resolveMetadata(base: [:],
                                                          provider: nil,
                                                          explicit: nil,
                                                          error: nil)

        // Assert
        XCTAssertTrue(resolved.isEmpty)
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
        XCTAssertEqual(resolved["key"], "explicit")
        XCTAssertEqual(resolved["fromBase"], "yes")
        XCTAssertEqual(resolved["fromProvider"], "yes")
        XCTAssertEqual(resolved["fromExplicit"], "yes")
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
        XCTAssertNotNil(resolved["error.message"])
        XCTAssertTrue("\(resolved["error.type"] ?? "")".contains("SampleError"))
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

        // Assert — nested values are written in the default formatter's style: no quotes, dictionaries sorted by key.
        XCTAssertEqual(flattened["plain"], "value")
        XCTAssertEqual(flattened["nested"], "[id=7]")
        XCTAssertEqual(flattened["list"], "[a, b]")
    }

    func testFlatten_ShouldKeepEveryTopLevelKeyAndCollapseOnlyNestedValues() {
        // Arrange
        let metadata: Logger.Metadata = [
            "code": "404",
            "tags": ["a", "b"],
            "user": ["id": "7", "name": "Ann", "role": "admin", "address": ["zip": "1", "city": "X"]]
        ]

        // Act
        let flattened = LogSmithLogHandler.flatten(metadata)

        // Assert — the top level is still key/value, as core metadata supports it; only the nested values become strings.
        XCTAssertEqual(flattened, [
            "code": "404",
            "tags": "[a, b]",
            "user": "[address=[city=X, zip=1], id=7, name=Ann, role=admin]"
        ])
    }

    func testFlatten_WithSecondLevelNesting_ShouldSortEveryLevelWithoutEscaping() {
        // Arrange — three levels of dictionaries, each with its keys out of order.
        let metadata: Logger.Metadata = [
            "user": ["id": "7", "name": "Ann", "address": ["zip": "1", "city": "X", "geo": ["lng": "2", "lat": "1"]]]
        ]

        // Act
        let flattened = LogSmithLogHandler.flatten(metadata)

        // Assert — no backslashes at any depth, and every level sorted.
        XCTAssertEqual(flattened["user"], "[address=[city=X, geo=[lat=1, lng=2], zip=1], id=7, name=Ann]")
    }

    func testFlatten_WithArraysAndDictionariesInsideEachOther_ShouldRenderEveryLevelTheSameWay() {
        // Arrange
        let metadata: Logger.Metadata = [
            "mixed": .array([.dictionary(["b": "2", "a": "1"]), .string("x"), .array([.string("y"), .string("z")])]),
            "box": .dictionary(["tags": .array([.string("t2"), .string("t1")]), "id": "7"])
        ]

        // Act
        let flattened = LogSmithLogHandler.flatten(metadata)

        // Assert — dictionaries are sorted by key, arrays keep their own order.
        XCTAssertEqual(flattened["mixed"], "[[a=1, b=2], x, [y, z]]")
        XCTAssertEqual(flattened["box"], "[id=7, tags=[t2, t1]]")
    }

    func testFlatten_WithEmptyContainersAndConvertibleValues_ShouldRenderThem() {
        // Arrange
        let metadata: Logger.Metadata = [
            "emptyDictionary": .dictionary([:]),
            "emptyArray": .array([]),
            "number": .stringConvertible(42),
            "inside": .dictionary(["ratio": .stringConvertible(1.5)])
        ]

        // Act
        let flattened = LogSmithLogHandler.flatten(metadata)

        // Assert
        XCTAssertEqual(flattened["emptyDictionary"], "[]")
        XCTAssertEqual(flattened["emptyArray"], "[]")
        XCTAssertEqual(flattened["number"], "42")
        XCTAssertEqual(flattened["inside"], "[ratio=1.5]")
    }

    func testFlatten_WithNestedEntriesInsertedInDifferentOrders_ShouldRenderTheSame() {
        // Arrange — the same entries added in opposite orders, which a plain dictionary may iterate differently.
        let keys = (0..<30).map { "key\($0)" }
        func nested(insertingIn order: [String]) -> Logger.Metadata {
            var inner: Logger.Metadata = [:]
            order.forEach { inner[$0] = .dictionary([$0: .string($0.uppercased())]) }
            return ["outer": .dictionary(inner)]
        }
        let expected = "[" + keys.sorted().map { "\($0)=[\($0)=\($0.uppercased())]" }.joined(separator: ", ") + "]"

        // Act & Assert
        XCTAssertEqual(LogSmithLogHandler.flatten(nested(insertingIn: keys))["outer"], expected)
        XCTAssertEqual(LogSmithLogHandler.flatten(nested(insertingIn: keys.reversed()))["outer"], expected)
    }

    func testLog_WithNestedMetadata_ShouldPopulateFlatMetadataOnLogMessage() {
        // Arrange & Act
        logAndWait { logger in
            logger.error("Request failed", metadata: ["user": .dictionary(["id": "7"])])
        }

        // Assert
        XCTAssertEqual(mockLogger.lastLogMessage?.metadata["user"], "[id=7]")
    }

    func testLog_WithHandlerMetadataAndNoPerStatementMetadata_ShouldDeliverHandlerMetadata() {
        // Arrange — the `logger[metadataKey:]` idiom, as used for request-scoped context.
        var logger = makeLogger()
        logger[metadataKey: "request-id"] = "abc-123"

        // Act
        logAndWait(logger: logger) { logger in
            logger.info("no per-statement metadata")
        }

        // Assert
        let message = mockLogger.lastLogMessage
        XCTAssertEqual(message?.metadata["request-id"], "abc-123")
        let payload = message?.payload as? SwiftLogPayload
        XCTAssertEqual(payload?.resolvedMetadata["request-id"], "abc-123")
    }

    func testLog_WithHandlerMetadataAndPerStatementMetadata_ShouldMergeBothWithStatementWinning() {
        // Arrange
        let logger = makeLogger(metadata: ["request-id": "abc-123", "shared": "handler"])

        // Act
        logAndWait(logger: logger) { logger in
            logger.info("with per-statement metadata", metadata: ["shared": "statement", "extra": "1"])
        }

        // Assert
        let flat = mockLogger.lastLogMessage?.metadata
        XCTAssertEqual(flat?["request-id"], "abc-123")
        XCTAssertEqual(flat?["extra"], "1")
        XCTAssertEqual(flat?["shared"], "statement", "per-statement metadata should override handler metadata")
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

    func testLog_WithNestedMetadata_ShouldRenderTheReadmeExampleThroughDefaultFormatter() {
        // Arrange & Act — the logger call from the README's swift-log section. An isolated manager adds no tags,
        // so the whole formatted line can be compared.
        logAndWait { logger in
            logger.error("Request failed", metadata: ["user": ["id": "7"], "code": "404"], source: "MyApp")
        }

        // Assert — keys sorted, the nested value kept as one string.
        XCTAssertEqual(mockLogger.lastFormattedMessage,
                       #"Request failed ["code": "404", "label": "com.swiftlogsmith.tests", "source": "MyApp", "user": "[id=7]"]"#)
    }

    func testLog_WithCustomMetadataFormat_ShouldFormatEveryTopLevelEntryAndSeeANestedValueAsOneString() {
        // Arrange — a metadata format that restyles every entry it is given.
        mockLogger.formatter = LogFormatter.Builder()
            .addMessagePart()
            .addMetadataPart(prefix: " ", format: { metadata in
                metadata.sorted { $0.key < $1.key }.map { "\($0.key.uppercased()):\($0.value)" }.joined(separator: "; ")
            })
            .build()

        // Act
        logAndWait(logger: makeLogger(includesContext: false)) { logger in
            logger.error("Request failed",
                         metadata: ["code": "404", "tags": ["a", "b"], "user": ["id": "7", "address": ["zip": "1", "city": "X"]]])
        }

        // Assert — each top-level key is restyled; a nested value reaches the format as the one string it was collapsed into.
        XCTAssertEqual(mockLogger.lastFormattedMessage, "Request failed CODE:404; TAGS:[a, b]; USER:[address=[city=X, zip=1], id=7]")
    }

    func testLog_WithSecondLevelNesting_ShouldRenderOneSortedLineWithoutBackslashes() {
        // Arrange & Act
        logAndWait { logger in
            logger.error("Request failed",
                         metadata: ["user": ["id": "7", "name": "Ann", "address": ["zip": "1", "city": "X"]], "tags": ["a", "b"]],
                         source: "MyApp")
        }

        // Assert — the second level is sorted too, and nothing in the line is escaped.
        let formatted = mockLogger.lastFormattedMessage ?? ""
        XCTAssertEqual(formatted,
                       #"Request failed ["label": "com.swiftlogsmith.tests", "source": "MyApp", "tags": "[a, b]", "user": "[address=[city=X, zip=1], id=7, name=Ann]"]"#)
        XCTAssertFalse(formatted.contains("\\"), formatted)
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
        XCTAssertEqual(payload?.resolvedMetadata["user"], .dictionary(["id": "7"]))
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
