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

/// Tests what the `bootstrapWithLogSmith` options do to the handlers they create.
///
/// > Note: `LoggingSystem.bootstrap` traps on a second call per process, so the bootstrap functions cannot run
/// here. Each is one call to `logSmithHandlerFactory`, which is exercised through `Logger(label:factory:)` instead.
final class BootstrapHandlerFactoryTests: XCTestCase {

    private static let label = "com.swiftlogsmith.bootstrap"

    /// Receives what is delivered to the isolated manager.
    private var isolatedLogger: BackendMockLogger!
    /// Receives what is delivered to the shared `LogSmith` pipeline.
    private var sharedLogger: BackendMockLogger!
    private var manager: LogManager!

    override func setUp() {
        super.setUp()
        isolatedLogger = BackendMockLogger()
        sharedLogger = BackendMockLogger()
        manager = LogManager(identifier: "SwiftLogSmithBackendTests.\(UUID().uuidString)", defaultLogger: isolatedLogger)
        expectCompletion(description: "shared logger registered") { fulfill in
            LogSmith.addLogger(newLogger: sharedLogger) { _ in fulfill() }
        }
    }

    override func tearDown() {
        isolatedLogger.setOnLog(nil)
        sharedLogger.setOnLog(nil)
        expectCompletion(description: "shared logger removed") { fulfill in
            LogSmith.removeLogger(logger: sharedLogger) { _ in fulfill() }
        }
        manager = nil
        sharedLogger = nil
        isolatedLogger = nil
        super.tearDown()
    }

    /// Runs `operation` on `logger` and waits until `target` has received a message.
    private func send(through logger: Logger, to target: BackendMockLogger, _ operation: (Logger) -> Void) {
        expectCompletion(description: "message delivered") { fulfill in
            target.setOnLog { _ in fulfill() }
            operation(logger)
        }
    }

    /// Runs `check` once for the isolated manager and once for the shared pipeline, with the spy that sees what arrives at each.
    private func forEachDestination(_ check: (_ manager: LogManager?, _ receiver: BackendMockLogger, _ destination: String) -> Void) {
        check(manager, isolatedLogger, "isolated manager")
        check(nil, sharedLogger, "shared pipeline")
    }

    //MARK: defaultLogLevel

    func testFactory_WithDefaultLogLevel_ShouldCreateEveryHandlerAtThatLevel() {
        // Arrange
        let levels: [Logger.Level] = [.trace, .debug, .info, .notice, .warning, .error, .critical]
        let destinations: [LogManager?] = [manager, nil]

        // Act & Assert — the same for the isolated and the shared pipeline.
        for destination in destinations {
            for level in levels {
                let factory = LoggingSystem.logSmithHandlerFactory(manager: destination,
                                                                   defaultLogLevel: level,
                                                                   includesSwiftLogContextInMetadata: true)
                XCTAssertEqual(Logger(label: "first", factory: factory).logLevel, level)
                XCTAssertEqual(Logger(label: "second", factory: factory).logLevel, level, "every handler should start at the level")
            }
        }
    }

    //MARK: metadataProvider

    func testFactory_WithMetadataProvider_ShouldHaveTheHandlerConsultIt() {
        // Arrange — `LoggingSystem.bootstrap` hands its metadata provider to the factory along with each label.
        let provider = Logger.MetadataProvider { ["request-id": "r-42"] }

        forEachDestination { manager, receiver, destination in
            let factory = LoggingSystem.logSmithHandlerFactory(manager: manager, defaultLogLevel: .trace, includesSwiftLogContextInMetadata: true)
            let logger = Logger(label: Self.label) { label in factory(label, provider) }

            // Act
            send(through: logger, to: receiver) { $0.info("with provider") }

            // Assert
            XCTAssertEqual(receiver.lastLogMessage?.metadata["request-id"], "r-42", destination)
        }
    }

    func testFactory_WithoutMetadataProvider_ShouldAddNoProvidedMetadata() {
        forEachDestination { manager, receiver, destination in
            // Arrange
            let factory = LoggingSystem.logSmithHandlerFactory(manager: manager, defaultLogLevel: .trace, includesSwiftLogContextInMetadata: true)
            let logger = Logger(label: Self.label) { label in factory(label, nil) }

            // Act
            send(through: logger, to: receiver) { $0.info("without provider") }

            // Assert — only the label and source that the handler adds itself.
            let keys = Set(receiver.lastLogMessage?.metadata.keys.map { $0 } ?? [])
            XCTAssertEqual(keys, [LogSmithLogHandler.labelMetadataKey, LogSmithLogHandler.sourceMetadataKey], destination)
        }
    }

    //MARK: includesSwiftLogContextInMetadata

    func testFactory_WithContextIncluded_ShouldAddLabelAndSourceToTheFlatMetadata() {
        forEachDestination { manager, receiver, destination in
            // Arrange
            let factory = LoggingSystem.logSmithHandlerFactory(manager: manager, defaultLogLevel: .trace, includesSwiftLogContextInMetadata: true)
            let logger = Logger(label: Self.label, factory: factory)

            // Act
            send(through: logger, to: receiver) { $0.info("with context", source: "TestSource") }

            // Assert
            let metadata = receiver.lastLogMessage?.metadata
            XCTAssertEqual(metadata?[LogSmithLogHandler.labelMetadataKey], Self.label, destination)
            XCTAssertEqual(metadata?[LogSmithLogHandler.sourceMetadataKey], "TestSource", destination)
        }
    }

    func testFactory_WithContextExcluded_ShouldKeepLabelAndSourceOutOfTheFlatMetadataButOnThePayload() {
        forEachDestination { manager, receiver, destination in
            // Arrange
            let factory = LoggingSystem.logSmithHandlerFactory(manager: manager, defaultLogLevel: .trace, includesSwiftLogContextInMetadata: false)
            let logger = Logger(label: Self.label, factory: factory)

            // Act
            send(through: logger, to: receiver) { $0.info("without context", source: "TestSource") }

            // Assert
            let message = receiver.lastLogMessage
            XCTAssertEqual(message?.metadata, [:], destination)
            let payload = message?.payload as? SwiftLogPayload
            XCTAssertEqual(payload?.label, Self.label, destination)
            XCTAssertEqual(payload?.event.source, "TestSource", destination)
        }
    }

    //MARK: manager

    func testFactory_WithManager_ShouldDeliverToThatManagerAndNotToTheSharedPipeline() {
        // Arrange
        let factory = LoggingSystem.logSmithHandlerFactory(manager: manager, defaultLogLevel: .trace, includesSwiftLogContextInMetadata: true)
        let logger = Logger(label: Self.label, factory: factory)

        // Act
        send(through: logger, to: isolatedLogger) { $0.info("to the manager") }
        // A bridged message that had gone to the shared pipeline would already be queued ahead of this one.
        expectCompletion(description: "shared pipeline drained") { fulfill in
            LogSmith.logE("barrier") { _ in fulfill() }
        }

        // Assert
        XCTAssertEqual(isolatedLogger.messages.map { $0.message }, ["to the manager"])
        XCTAssertEqual(sharedLogger.messages.map { $0.message }, ["barrier"])
    }

    func testFactory_WithoutManager_ShouldDeliverToTheSharedPipeline() {
        // Arrange
        let factory = LoggingSystem.logSmithHandlerFactory(manager: nil, defaultLogLevel: .trace, includesSwiftLogContextInMetadata: true)
        let logger = Logger(label: Self.label, factory: factory)

        // Act
        send(through: logger, to: sharedLogger) { $0.info("to the shared pipeline") }

        // Assert
        XCTAssertEqual(sharedLogger.messages.map { $0.message }, ["to the shared pipeline"])
        XCTAssertEqual(isolatedLogger.logCallCount, 0)
    }
}
