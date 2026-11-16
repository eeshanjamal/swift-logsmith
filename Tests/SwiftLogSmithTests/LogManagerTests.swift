//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import SwiftLogSmith

final class FirstMockLogger: ILogger, @unchecked Sendable {
    var tagger: LogTagger?
    var formatter: LogFormatter
    var lastLoggedMessage: LogMessage?
    var logCallCount = 0

    init(tagger: LogTagger? = nil, formatter: LogFormatter = LogFormatter.default) {
        self.tagger = tagger
        self.formatter = formatter
    }

    func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)?) {
        lastLoggedMessage = message
        logCallCount += 1
        completion?(true)
    }
    
    func reset() {
        lastLoggedMessage = nil
        logCallCount = 0
    }
}

final class SecondMockLogger: ILogger, @unchecked Sendable {
    var tagger: LogTagger?
    var formatter: LogFormatter
    var lastLoggedMessage: LogMessage?
    var logCallCount = 0

    init(tagger: LogTagger? = nil, formatter: LogFormatter = LogFormatter.default) {
        self.tagger = tagger
        self.formatter = formatter
    }

    func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)?) {
        lastLoggedMessage = message
        logCallCount += 1
        completion?(true)
    }
    
    func reset() {
        lastLoggedMessage = nil
        logCallCount = 0
    }
}

/// A minimal `LogPayload`, used to verify that a payload travels through the pipeline untouched.
final class TestLogPayload: NSObject, LogPayload {
    let id: Int

    init(id: Int) {
        self.id = id
        super.init()
    }
}

final class LogManagerTests: XCTestCase {

    var sut: LogManager!
    var mockDefaultLogger: FirstMockLogger!

    override func setUp() {
        super.setUp()
        mockDefaultLogger = FirstMockLogger()
        sut = LogManager(identifier: "TestManager", defaultLogger: mockDefaultLogger)
    }

    override func tearDown() {
        sut = nil
        mockDefaultLogger = nil
        super.tearDown()
    }

    func testInitialization_ShouldContainDefaultLogger() {
        let logger = mockDefaultLogger
        expectCompletion(description: "Default logger should receive log") { fulfill in
            sut.log(message: "test", logType: .info) { _ in
                XCTAssertEqual(logger?.logCallCount, 1)
                fulfill()
            }
        }
    }

    func testAddLogger_WithNewLogger_ShouldSucceed() {
        let newLogger = SecondMockLogger()
        expectCompletion(description: "Add new logger") { fulfill in
            sut.addLogger(newLogger: newLogger) { success in
                XCTAssertTrue(success); fulfill()
            }
        }
    
        // Verify both loggers receive the message
        let logger = mockDefaultLogger
        expectCompletion(description: "Both loggers should receive the log") { fulfill in
            sut.log(message: "test", logType: .info) { _ in
                XCTAssertEqual(logger?.logCallCount, 1)
                XCTAssertEqual(newLogger.logCallCount, 1)
                fulfill()
            }
        }
    }

    func testAddLogger_WithMultipleInstancesOfSameType_ShouldSucceed() {
        let logger1 = SecondMockLogger()
        let logger2 = SecondMockLogger()
        
        expectCompletion(description: "Add first logger") { fulfill in
            sut.addLogger(newLogger: logger1) { success in
                XCTAssertTrue(success)
                fulfill()
            }
        }
        
        expectCompletion(description: "Add second logger of same type") { fulfill in
            sut.addLogger(newLogger: logger2) { success in
                XCTAssertTrue(success, "Should allow adding a second instance of the same logger type")
                fulfill()
            }
        }
        
        expectCompletion(description: "Both loggers should receive log") { fulfill in
            sut.log(message: "test", logType: .info) { _ in
                XCTAssertEqual(logger1.logCallCount, 1)
                XCTAssertEqual(logger2.logCallCount, 1)
                fulfill()
            }
        }
        
        // Verify removing one doesn't remove the other
        expectCompletion(description: "Remove first logger") { fulfill in
            sut.removeLogger(logger: logger1) { success in
                XCTAssertTrue(success)
                fulfill()
            }
        }
        
        logger1.reset()
        logger2.reset()
        
        expectCompletion(description: "Only second logger should receive log") { fulfill in
            sut.log(message: "test 2", logType: .info) { _ in
                XCTAssertEqual(logger1.logCallCount, 0)
                XCTAssertEqual(logger2.logCallCount, 1)
                fulfill()
            }
        }
    }
    
    func testReplaceDefaultLogger_ShouldReplaceAndUseNewConfig() {
        let newDefaultLogger = FirstMockLogger()
        let oldDefaultLogger = mockDefaultLogger
        
        expectCompletion(description: "Replace default logger with strict config") { fulfill in
            // Set new logger to only accept .error level
            sut.replaceDefaultLogger(with: newDefaultLogger, minLogLevel: .error) { success in
                XCTAssertTrue(success)
                fulfill()
            }
        }
        
        expectCompletion(description: "Info log should be filtered by new config") { fulfill in
            sut.log(message: "info log", logType: .info) { _ in
                XCTAssertEqual(newDefaultLogger.logCallCount, 0, "New default logger should filter info log based on new config")
                XCTAssertEqual(oldDefaultLogger?.logCallCount, 0, "Old default logger should be removed")
                fulfill()
            }
        }
        
        expectCompletion(description: "Error log should be accepted") { fulfill in
            sut.log(message: "error log", logType: .error) { _ in
                XCTAssertEqual(newDefaultLogger.logCallCount, 1, "New default logger should accept error log")
                fulfill()
            }
        }
    }

    func testLogLevelFiltering_ManagerLevel() {
        sut.setMinimumLogLevel(.error)
        
        let logger = mockDefaultLogger
        // This log is below the manager's minimum level and should be dropped
        expectCompletion(description: "Info log should be filtered") { fulfill in
            sut.log(message: "info log", logType: .info) { _ in
                XCTAssertEqual(logger?.logCallCount, 0, "Info log should have been filtered")
                fulfill()
            }
        }
        
        mockDefaultLogger.reset()

        expectCompletion(description: "Error log should pass") { fulfill in
            sut.log(message: "error log", logType: .error) { _ in
                XCTAssertEqual(logger?.logCallCount, 1, "Error log should have been processed")
                fulfill()
            }
        }
    }

    func testLogLevelFiltering_LoggerItemLevel() {
        let strictLogger = SecondMockLogger()
        expectCompletion(description: "Add strict logger") { fulfill in
            sut.addLogger(newLogger: strictLogger, minLogLevel: .error) { success in
                XCTAssertTrue(success); fulfill()
            }
        }
        
        let logger = mockDefaultLogger
        expectCompletion(description: "Default logger receives, strict logger filters") { fulfill in
            sut.log(message: "info log", logType: .info) { _ in
                XCTAssertEqual(logger?.logCallCount, 1)
                XCTAssertEqual(strictLogger.logCallCount, 0)
                fulfill()
            }
        }
    }

    func testLogTypeFiltering_ManagerLevel() {
        sut.setMinimumLogType(.warning)
        
        let logger = mockDefaultLogger
        expectCompletion(description: "Info log should be filtered by type") { fulfill in
            sut.log(message: "info log", logType: .info) { _ in
                XCTAssertEqual(logger?.logCallCount, 0, "Info log should have been filtered")
                fulfill()
            }
        }
        
        mockDefaultLogger.reset()

        expectCompletion(description: "Warning log should pass") { fulfill in
            sut.log(message: "warning log", logType: .warning) { _ in
                XCTAssertEqual(logger?.logCallCount, 1, "Warning log should have been processed")
                fulfill()
            }
        }
    }

    func testLogTypeFiltering_LoggerItemLevel() {
        let strictLogger = SecondMockLogger()
        expectCompletion(description: "Add strict logger") { fulfill in
            sut.addLogger(newLogger: strictLogger, minLogType: .warning) { success in
                XCTAssertTrue(success); fulfill()
            }
        }
        
        let logger = mockDefaultLogger
        expectCompletion(description: "Default logger receives, strict logger filters by type") { fulfill in
            sut.log(message: "info log", logType: .info) { _ in
                XCTAssertEqual(logger?.logCallCount, 1, "Default logger should have received the info log")
                XCTAssertEqual(strictLogger.logCallCount, 0, "Strict logger should have filtered the info log by type")
                fulfill()
            }
        }
    }

    func testCombinedFiltering_ManagerLevel() {
        sut.setMinimumLogLevel(.error)   // min level rawValue = 3
        sut.setMinimumLogType(.critical) // min type rawValue = 8
        
        let logger = mockDefaultLogger
        // Scenario 1: Fails Level filter
        expectCompletion(description: "Log should be filtered by level") { fulfill in
            sut.log(message: "info log", logType: .info) { _ in
                XCTAssertEqual(logger?.logCallCount, 0, "Info log should have been filtered by level")
                fulfill()
            }
        }
        
        mockDefaultLogger.reset()
        
        // Scenario 2: Fails Type filter
        expectCompletion(description: "Log should be filtered by type") { fulfill in
            sut.log(message: "error log", logType: .error) { _ in
                XCTAssertEqual(logger?.logCallCount, 0, "Error log should be filtered by type")
                fulfill()
            }
        }
        
        mockDefaultLogger.reset()
        
        // Scenario 3: Passes both filters
        expectCompletion(description: "Log should pass both filters") { fulfill in
            sut.log(message: "critical log", logType: .critical) { _ in
                XCTAssertEqual(logger?.logCallCount, 1, "Critical log should pass both filters")
                fulfill()
            }
        }
    }
    
    func testCombinedFiltering_LoggerItemLevel() {
        let strictLogger = SecondMockLogger()
        sut.setMinimumLogLevel(.all)
        sut.setMinimumLogType(.none)

        expectCompletion(description: "Add strict logger with combined filters") { fulfill in
            sut.addLogger(newLogger: strictLogger, minLogLevel: .error, minLogType: .error) { success in
                XCTAssertTrue(success); fulfill()
            }
        }
        
        let logger = mockDefaultLogger
        expectCompletion(description: "Combined filter test") { fulfill in
            sut.log(message: "warning log", logType: .warning) { _ in
                XCTAssertEqual(logger?.logCallCount, 1)
                XCTAssertEqual(strictLogger.logCallCount, 0)
                fulfill()
            }
        }
    }

    func testTagIntegration_ManagerAndLoggerLevels() {
        let loggerTagger = LogTagger()
        let loggerSpecificLogger = SecondMockLogger(tagger: loggerTagger)
        sut.addLogger(newLogger: loggerSpecificLogger, completion: nil)

        let managerTag = ExternalTag(identifier: "ManagerTag", value: "ManagerValue")
        let loggerTag = ExternalTag(identifier: "LoggerTag", value: "LoggerValue")
        
        expectCompletion(description: "Add manager tag") { fulfill in
            sut.addTag(managerTag) { _ in fulfill() }
        }
        expectCompletion(description: "Add logger-specific tag") { fulfill in
            loggerTagger.addTag(loggerTag) { _ in fulfill() }
        }

        let logger = mockDefaultLogger
        expectCompletion(description: "All loggers should receive log with correct tags") { fulfill in
            sut.log(message: "tag test", logType: .info) { _ in
                let defaultMsg = logger?.lastLoggedMessage
                XCTAssertNotNil(defaultMsg)
                XCTAssertTrue(defaultMsg?.tags.contains(where: { $0.identifier == "ManagerTag" }) ?? false)
                XCTAssertFalse(defaultMsg?.tags.contains(where: { $0.identifier == "LoggerTag" }) ?? false)
                
                let specificMsg = loggerSpecificLogger.lastLoggedMessage
                XCTAssertNotNil(specificMsg)
                XCTAssertTrue(specificMsg?.tags.contains(where: { $0.identifier == "ManagerTag" }) ?? false)
                XCTAssertTrue(specificMsg?.tags.contains(where: { $0.identifier == "LoggerTag" }) ?? false)
                fulfill()
            }
        }
    }

    func testLog_WithPayload_ShouldAttachSamePayloadInstanceToLogMessage() {
        // Arrange
        let payload = TestLogPayload(id: 7)
        let logger = mockDefaultLogger

        // Act & Assert
        expectCompletion(description: "Logger should receive the payload") { fulfill in
            sut.log(message: "payload test", logType: .info, payload: payload) { _ in
                let received = logger?.lastLoggedMessage?.payload
                XCTAssertTrue(received === payload, "The payload should arrive as the same instance")
                XCTAssertEqual((received as? TestLogPayload)?.id, 7)
                fulfill()
            }
        }
    }

    func testLog_WithoutPayload_ShouldLeavePayloadNil() {
        // Arrange
        let logger = mockDefaultLogger

        // Act & Assert
        expectCompletion(description: "Logger should receive the log") { fulfill in
            sut.log(message: "no payload", logType: .info) { _ in
                XCTAssertNotNil(logger?.lastLoggedMessage)
                XCTAssertNil(logger?.lastLoggedMessage?.payload)
                fulfill()
            }
        }
    }

    func testLog_WithExplicitSourceLocation_ShouldPopulateInternalTags() {
        // Arrange — a facade only has runtime strings, never compile-time literals, so build them at runtime.
        let fileId = ["Module", "File.swift"].joined(separator: "/")
        let function = "doWork" + "()"
        let logger = mockDefaultLogger

        expectCompletion(description: "Add internal tags", fulfillmentCount: 3) { fulfill in
            sut.addTag(InternalTag(internalTagType: .file)) { _ in fulfill() }
            sut.addTag(InternalTag(internalTagType: .function)) { _ in fulfill() }
            sut.addTag(InternalTag(internalTagType: .line)) { _ in fulfill() }
        }

        // Act & Assert
        expectCompletion(description: "Tags should carry the explicit source location") { fulfill in
            sut.log(message: "located", logType: .info, fileId: fileId, function: function, line: 42) { _ in
                let tags = logger?.lastLoggedMessage?.tags ?? []
                XCTAssertEqual(tags.first(where: { $0.identifier == LogTagIdentifiers.file })?.value, "Module/File.swift")
                XCTAssertEqual(tags.first(where: { $0.identifier == LogTagIdentifiers.function })?.value, "doWork()")
                XCTAssertEqual(tags.first(where: { $0.identifier == LogTagIdentifiers.line })?.value, "42")
                fulfill()
            }
        }
    }

    func testLog_WithTimestampTags_ShouldShareOneMomentAcrossLoggersAndTagLevels() {
        // Arrange — a manager-level timestamp tag, plus one on a second logger's own tagger.
        let loggerTagger = LogTagger()
        let secondLogger = SecondMockLogger(tagger: loggerTagger)
        expectCompletion(description: "Register tags and logger", fulfillmentCount: 3) { fulfill in
            sut.addTag(InternalTag(internalTagType: .timestamp)) { _ in fulfill() }
            loggerTagger.addTag(InternalTag(internalTagType: .timestamp)) { _ in fulfill() }
            sut.addLogger(newLogger: secondLogger) { _ in fulfill() }
        }
        let firstLogger = mockDefaultLogger

        // Act & Assert
        expectCompletion(description: "Both loggers should receive the log") { fulfill in
            sut.log(message: "shared moment", logType: .info) { _ in
                let first = firstLogger?.lastLoggedMessage
                let second = secondLogger.lastLoggedMessage
                XCTAssertNotNil(first?.timestamp)
                XCTAssertEqual(first?.timestamp, second?.timestamp, "Every logger should get the same timestamp")

                let values = (first?.tags ?? []).filter { $0.identifier == LogTagIdentifiers.timestamp }.map(\.value)
                    + (second?.tags ?? []).filter { $0.identifier == LogTagIdentifiers.timestamp }.map(\.value)
                XCTAssertEqual(values.count, 3, "One manager-level tag per logger, plus the second logger's own tag")
                XCTAssertEqual(Set(values).count, 1, "Every timestamp tag should carry the same value: \(values)")

                let parsed = values.first.flatMap { ISO8601DateFormatter.withFractionalSeconds.date(from: $0) }
                XCTAssertLessThan(abs((parsed ?? .distantPast).timeIntervalSince(first?.timestamp ?? .distantFuture)), 0.001)
                fulfill()
            }
        }
    }

    func testLog_WithBusyQueue_ShouldTimestampTheCallNotTheProcessing() {
        // Arrange — the completion runs on the manager's queue, so sleeping in it holds back the log below.
        sut.addLogger(newLogger: SecondMockLogger()) { _ in Thread.sleep(forTimeInterval: 0.3) }
        let logger = mockDefaultLogger

        // Act
        let before = Date()
        expectCompletion(description: "The log should be processed after the queue frees up") { fulfill in
            sut.log(message: "called early", logType: .info) { _ in
                let processedAt = Date()
                let timestamp = logger?.lastLoggedMessage?.timestamp ?? .distantPast

                // Assert
                XCTAssertGreaterThanOrEqual(timestamp, before)
                XCTAssertLessThan(timestamp.timeIntervalSince(before), 0.1, "The timestamp should be the moment of the call")
                XCTAssertGreaterThan(processedAt.timeIntervalSince(timestamp), 0.2, "The log should have waited for the busy queue")
                fulfill()
            }
        }
    }

    //MARK: Caller and manager tags

    private func addCallerTags(to manager: LogManager) {
        let types: [InternalTagType] = [.callerThreadName, .callerQueueLabel, .callerName, .managerQueueLabel]
        expectCompletion(description: "Register caller tags", fulfillmentCount: types.count) { fulfill in
            types.forEach { manager.addTag(InternalTag(internalTagType: $0)) { _ in fulfill() } }
        }
    }

    private static func value(of identifier: String, in message: LogMessage?) -> String? {
        message?.tags.first(where: { $0.identifier == identifier })?.value
    }

    private static func currentThreadID() -> String {
        var threadID: UInt64 = 0
        pthread_threadid_np(nil, &threadID)
        return "0x" + String(threadID, radix: 16)
    }

    func testLog_FromNamedThread_ShouldReportTheThreadName() {
        addCallerTags(to: sut)
        let logger = mockDefaultLogger
        let manager = sut!

        expectCompletion(description: "Log from a named thread") { fulfill in
            let thread = Thread {
                manager.log(message: "from a thread", logType: .info) { _ in
                    let message = logger?.lastLoggedMessage
                    XCTAssertEqual(Self.value(of: LogTagIdentifiers.callerThreadName, in: message), "LogSmithWorker")
                    XCTAssertEqual(Self.value(of: LogTagIdentifiers.callerName, in: message), "LogSmithWorker")
                    XCTAssertFalse(Self.value(of: LogTagIdentifiers.callerQueueLabel, in: message)?.isEmpty ?? true)
                    fulfill()
                }
            }
            thread.name = "LogSmithWorker"
            thread.start()
        }
    }

    func testLog_FromQueue_ShouldReportTheQueueLabelAndThreadID() {
        addCallerTags(to: sut)
        let logger = mockDefaultLogger
        let manager = sut!
        let queue = DispatchQueue(label: "com.swiftlogsmith.tests.caller")

        expectCompletion(description: "Log from a dispatch queue") { fulfill in
            queue.async {
                let expectedThreadID = Self.currentThreadID()
                manager.log(message: "from a queue", logType: .info) { _ in
                    let message = logger?.lastLoggedMessage
                    XCTAssertEqual(Self.value(of: LogTagIdentifiers.callerQueueLabel, in: message), "com.swiftlogsmith.tests.caller")
                    XCTAssertEqual(Self.value(of: LogTagIdentifiers.callerName, in: message), "com.swiftlogsmith.tests.caller")
                    XCTAssertEqual(Self.value(of: LogTagIdentifiers.callerThreadName, in: message), expectedThreadID,
                                   "A queue's thread has no name, so the thread ID should be reported")
                    fulfill()
                }
            }
        }
    }

    func testLog_FromMainThread_ShouldReportMain() {
        addCallerTags(to: sut)
        let logger = mockDefaultLogger
        let expectedThreadName = Thread.main.name.flatMap { $0.isEmpty ? nil : $0 } ?? "main"

        expectCompletion(description: "Log from the main thread") { fulfill in
            XCTAssertTrue(Thread.isMainThread)
            sut.log(message: "from main", logType: .info) { _ in
                let message = logger?.lastLoggedMessage
                XCTAssertEqual(Self.value(of: LogTagIdentifiers.callerThreadName, in: message), expectedThreadName)
                XCTAssertEqual(Self.value(of: LogTagIdentifiers.callerQueueLabel, in: message), "com.apple.main-thread")
                fulfill()
            }
        }
    }

    func testLog_WithManagerQueueLabelTag_ShouldIdentifyTheManager() {
        // Arrange — the tag on the manager and on a logger's own tagger, plus a second manager for comparison.
        let loggerTagger = LogTagger()
        let secondLogger = SecondMockLogger(tagger: loggerTagger)
        let otherLogger = SecondMockLogger()
        let otherManager = LogManager(identifier: "OtherManager", defaultLogger: otherLogger)
        expectCompletion(description: "Register tags and logger", fulfillmentCount: 4) { fulfill in
            sut.addTag(InternalTag(internalTagType: .managerQueueLabel)) { _ in fulfill() }
            loggerTagger.addTag(InternalTag(internalTagType: .managerQueueLabel)) { _ in fulfill() }
            sut.addLogger(newLogger: secondLogger) { _ in fulfill() }
            otherManager.addTag(InternalTag(internalTagType: .managerQueueLabel)) { _ in fulfill() }
        }
        let firstLogger = mockDefaultLogger

        // Act
        expectCompletion(description: "Both managers log", fulfillmentCount: 2) { fulfill in
            sut.log(message: "first manager", logType: .info) { _ in fulfill() }
            otherManager.log(message: "second manager", logType: .info) { _ in fulfill() }
        }

        // Assert
        let labels = (secondLogger.lastLoggedMessage?.tags ?? []).filter { $0.identifier == LogTagIdentifiers.managerQueueLabel }.map(\.value)
        let firstLabel = Self.value(of: LogTagIdentifiers.managerQueueLabel, in: firstLogger?.lastLoggedMessage)
        let otherLabel = Self.value(of: LogTagIdentifiers.managerQueueLabel, in: otherLogger.lastLoggedMessage)
        XCTAssertEqual(labels.count, 2, "One manager-level tag and the logger's own tag")
        XCTAssertEqual(Set(labels + [firstLabel ?? ""]).count, 1, "Every tag from one manager should carry the same label")
        XCTAssertTrue(firstLabel?.hasPrefix("com.swift.logsmith.logman.") ?? false)
        XCTAssertNotNil(otherLabel)
        XCTAssertNotEqual(firstLabel, otherLabel, "Each manager should report its own label")
    }

    /// Marked deprecated so that it can exercise the deprecated `threadName` without warnings.
    @available(*, deprecated)
    func testLog_WithDeprecatedThreadNameTag_ShouldReportTheCallerName() {
        let logger = mockDefaultLogger
        let manager = sut!
        expectCompletion(description: "Register tags", fulfillmentCount: 2) { fulfill in
            manager.addTag(InternalTag(internalTagType: .threadName)) { _ in fulfill() }
            manager.addTag(InternalTag(internalTagType: .callerName)) { _ in fulfill() }
        }

        expectCompletion(description: "Log from a named thread") { fulfill in
            let thread = Thread {
                manager.log(message: "legacy", logType: .info) { _ in
                    let message = logger?.lastLoggedMessage
                    XCTAssertEqual(Self.value(of: LogTagIdentifiers.threadName, in: message), "LegacyWorker")
                    XCTAssertEqual(Self.value(of: LogTagIdentifiers.threadName, in: message),
                                   Self.value(of: LogTagIdentifiers.callerName, in: message))
                    fulfill()
                }
            }
            thread.name = "LegacyWorker"
            thread.start()
        }
    }
}
