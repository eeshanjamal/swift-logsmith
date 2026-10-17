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

/// Exercises the shared pipeline, where bridged `swift-log` messages and first-party ``LogSmith`` calls
/// converge on the same ``LogManager``.
///
/// This is the regression test for the reason the default manager is *not* exposed publicly: routing the
/// bridge through `LogSmith`'s own static keeps every operation behind the same queue hop, so the two entry
/// points cannot interleave inconsistently.
final class SharedPipelineConcurrencyTests: XCTestCase {

    private var mockLogger: BackendMockLogger!

    override func setUp() {
        super.setUp()
        mockLogger = BackendMockLogger()
        expectCompletion(description: "logger registered") { fulfill in
            LogSmith.addLogger(newLogger: mockLogger) { _ in fulfill() }
        }
    }

    override func tearDown() {
        mockLogger.setOnLog(nil)
        expectCompletion(description: "logger removed") { fulfill in
            LogSmith.removeLogger(logger: mockLogger) { _ in fulfill() }
        }
        LogSmith.setMinimumLogLevel(.default)
        LogSmith.setMinimumLogType(.none)
        mockLogger = nil
        super.tearDown()
    }

    func testInterleavedLogging_FromBothEntryPoints_ShouldDeliverEveryMessageExactlyOnce() {
        // Arrange
        let iterations = 100
        let threads = 4
        let expectedTotal = iterations * threads * 2
        let bridged = Logger(label: "com.swiftlogsmith.concurrency") { label in
            LogSmithLogHandler(label: label)
        }

        // Act — hammer both entry points from several threads at once.
        expectCompletion(description: "all messages delivered", fulfillmentCount: expectedTotal, timeout: 30.0) { fulfill in
            mockLogger.setOnLog { _ in fulfill() }
            DispatchQueue.concurrentPerform(iterations: threads) { thread in
                for index in 0..<iterations {
                    bridged.info("bridged-\(thread)-\(index)")
                    LogSmith.logI("firstParty-\(thread)-\(index)")
                }
            }
        }

        // Assert — nothing lost, nothing duplicated.
        let received = mockLogger.messages.map { $0.message }
        XCTAssertEqual(received.count, expectedTotal)
        XCTAssertEqual(Set(received).count, expectedTotal, "every message should appear exactly once")
    }

    func testBridgedLogging_ShouldReceiveLogSmithSymbolicTags() {
        // Arrange — LogSmith's initialiser registers a symbolic tag per LogType on its own manager.
        // Bridged messages go through that same manager, so they pick the tags up too.
        let bridged = Logger(label: "com.swiftlogsmith.tags") { label in
            LogSmithLogHandler(label: label)
        }

        // Act
        expectCompletion(description: "message delivered") { fulfill in
            mockLogger.setOnLog { _ in fulfill() }
            bridged.error("Request failed", metadata: ["code": "404"])
        }

        // Assert
        let formatted = mockLogger.lastFormattedMessage ?? ""
        XCTAssertTrue(formatted.contains("[E]"), formatted)
        XCTAssertTrue(formatted.contains("Request failed"), formatted)
        XCTAssertTrue(formatted.contains("404"), formatted)
    }

    func testBridgedLogging_ShouldRespectLogSmithMinimumLogLevel() {
        // Arrange — the shared pipeline's filters must govern bridged traffic too.
        let bridged = Logger(label: "com.swiftlogsmith.filtered") { label in
            LogSmithLogHandler(label: label)
        }

        LogSmith.setMinimumLogLevel(.error)
        // setMinimumLogLevel is asynchronous; sequence behind it on the same queue before asserting.
        expectCompletion(description: "level applied") { fulfill in
            LogSmith.logE("barrier") { _ in fulfill() }
        }
        mockLogger.reset()

        // Act
        expectCompletion(description: "error delivered", timeout: 2.0) { fulfill in
            mockLogger.setOnLog { _ in fulfill() }
            bridged.info("below threshold, should be dropped")
            bridged.error("at threshold, should arrive")
        }

        // Assert
        XCTAssertEqual(mockLogger.messages.map { $0.message }, ["at threshold, should arrive"])
    }
}
