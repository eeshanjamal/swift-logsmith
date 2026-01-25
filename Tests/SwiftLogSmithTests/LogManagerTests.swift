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
    var expectation: XCTestExpectation?

    init(tagger: LogTagger? = nil, formatter: LogFormatter = LogFormatter.default) {
        self.tagger = tagger
        self.formatter = formatter
    }

    func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)?) {
        lastLoggedMessage = message
        logCallCount += 1
        completion?(true)
        expectation?.fulfill()
    }
    
    func reset() {
        lastLoggedMessage = nil
        logCallCount = 0
        expectation = nil
    }
}

final class SecondMockLogger: ILogger, @unchecked Sendable {
    var tagger: LogTagger?
    var formatter: LogFormatter
    var lastLoggedMessage: LogMessage?
    var logCallCount = 0
    var expectation: XCTestExpectation?

    init(tagger: LogTagger? = nil, formatter: LogFormatter = LogFormatter.default) {
        self.tagger = tagger
        self.formatter = formatter
    }

    func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)?) {
        lastLoggedMessage = message
        logCallCount += 1
        completion?(true)
        expectation?.fulfill()
    }
    
    func reset() {
        lastLoggedMessage = nil
        logCallCount = 0
        expectation = nil
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
        let expectation = XCTestExpectation(description: "Default logger should receive log")
        mockDefaultLogger.expectation = expectation
        
        sut.log(message: "test", logType: .info)
        
        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(mockDefaultLogger.logCallCount, 1)
    }

    func testAddLogger_WithNewLogger_ShouldSucceed() {
        let newLogger = SecondMockLogger()
        expectCompletion(description: "Add new logger") { fulfill in
            sut.addLogger(newLogger: newLogger) { success in
                XCTAssertTrue(success); fulfill()
            }
        }
    
        // Verify both loggers receive the message
        let logExpectation = XCTestExpectation(description: "Both loggers should receive the log")
        logExpectation.expectedFulfillmentCount = 2
        mockDefaultLogger.expectation = logExpectation
        newLogger.expectation = logExpectation
        
        sut.log(message: "test", logType: .info)
        
        wait(for: [logExpectation], timeout: 1.0)
        XCTAssertEqual(mockDefaultLogger.logCallCount, 1)
        XCTAssertEqual(newLogger.logCallCount, 1)
    }

    func testLogLevelFiltering_ManagerLevel() {
        sut.setMinimumLogLevel(.error)
        
        let expectation = XCTestExpectation(description: "Info log should be filtered")
        expectation.isInverted = true
        mockDefaultLogger.expectation = expectation

        // This log is below the manager's minimum level and should be dropped
        sut.log(message: "info log", logType: .info)

        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(mockDefaultLogger.logCallCount, 0, "Info log should have been filtered")
        mockDefaultLogger.reset()

        let expectation2 = XCTestExpectation(description: "Error log should pass")
        mockDefaultLogger.expectation = expectation2
        sut.log(message: "error log", logType: .error)
        wait(for: [expectation2], timeout: 1.0)
        XCTAssertEqual(mockDefaultLogger.logCallCount, 1, "Error log should have been processed")
    }

    func testLogLevelFiltering_LoggerItemLevel() {
        let strictLogger = SecondMockLogger()
        expectCompletion(description: "Add strict logger") { fulfill in
            sut.addLogger(newLogger: strictLogger, minLogLevel: .error) { success in
                XCTAssertTrue(success); fulfill()
            }
        }
        
        let logExpectation = XCTestExpectation(description: "Default logger receives, strict logger filters")
        mockDefaultLogger.expectation = logExpectation
        let logExpectation2 = XCTestExpectation(description: "Strict logger should not receive the log")
        logExpectation2.isInverted = true
        strictLogger.expectation = logExpectation2
        
        sut.log(message: "info log", logType: .info)
        
        wait(for: [logExpectation, logExpectation2], timeout: 1.0)
        XCTAssertEqual(mockDefaultLogger.logCallCount, 1)
        XCTAssertEqual(strictLogger.logCallCount, 0)
    }

    func testLogTypeFiltering_ManagerLevel() {
        sut.setMinimumLogType(.warning)
        
        let expectation = XCTestExpectation(description: "Info log should be filtered by type")
        expectation.isInverted = true
        mockDefaultLogger.expectation = expectation
        sut.log(message: "info log", logType: .info)
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(mockDefaultLogger.logCallCount, 0, "Info log should have been filtered")
        mockDefaultLogger.reset()

        let expectation2 = XCTestExpectation(description: "Warning log should pass")
        mockDefaultLogger.expectation = expectation2
        sut.log(message: "warning log", logType: .warning)
        wait(for: [expectation2], timeout: 1.0)
        XCTAssertEqual(mockDefaultLogger.logCallCount, 1, "Warning log should have been processed")
    }

    func testLogTypeFiltering_LoggerItemLevel() {
        let strictLogger = SecondMockLogger()
        expectCompletion(description: "Add strict logger") { fulfill in
            sut.addLogger(newLogger: strictLogger, minLogType: .warning) { success in
                XCTAssertTrue(success); fulfill()
            }
        }
        
        let logExpectation = XCTestExpectation(description: "Default logger receives, strict logger filters by type")
        mockDefaultLogger.expectation = logExpectation
        let logExpectation2 = XCTestExpectation(description: "Strict logger should not receive the log")
        logExpectation2.isInverted = true
        strictLogger.expectation = logExpectation2

        sut.log(message: "info log", logType: .info)
        
        wait(for: [logExpectation, logExpectation2], timeout: 1.0)

        XCTAssertEqual(mockDefaultLogger.logCallCount, 1, "Default logger should have received the info log")
        XCTAssertEqual(strictLogger.logCallCount, 0, "Strict logger should have filtered the info log by type")
    }

    func testCombinedFiltering_ManagerLevel() {
        sut.setMinimumLogLevel(.error)   // min level rawValue = 3
        sut.setMinimumLogType(.critical) // min type rawValue = 8
        
        // Scenario 1: Fails Level filter
        let expectation1 = XCTestExpectation(description: "Log should be filtered by level")
        expectation1.isInverted = true
        mockDefaultLogger.expectation = expectation1
        sut.log(message: "info log", logType: .info) // Fails level (level .info(1) < .error(3))
        wait(for: [expectation1], timeout: 1.0)
        XCTAssertEqual(mockDefaultLogger.logCallCount, 0, "Info log should be filtered by level")
        mockDefaultLogger.reset()
        
        // Scenario 2: Fails Type filter
        let expectation2 = XCTestExpectation(description: "Log should be filtered by type")
        expectation2.isInverted = true
        mockDefaultLogger.expectation = expectation2
        sut.log(message: "error log", logType: .error) // Passes level (.error(3) >= .error(3)), Fails type (.error(6) < .critical(8))
        wait(for: [expectation2], timeout: 1.0)
        XCTAssertEqual(mockDefaultLogger.logCallCount, 0, "Error log should be filtered by type")
        mockDefaultLogger.reset()
        
        // Scenario 3: Passes both filters
        let expectation3 = XCTestExpectation(description: "Log should pass both filters")
        mockDefaultLogger.expectation = expectation3
        sut.log(message: "critical log", logType: .critical) // Passes both (level .fault(4) >= .error(3) AND type .critical(8) >= .critical(8))
        wait(for: [expectation3], timeout: 1.0)
        XCTAssertEqual(mockDefaultLogger.logCallCount, 1, "Critical log should pass both filters")
    }
    
    func testCombinedFiltering_LoggerItemLevel() {
        let strictLogger = SecondMockLogger()
        sut.setMinimumLogLevel(.default)
        sut.setMinimumLogType(.none)

        expectCompletion(description: "Add strict logger with combined filters") { fulfill in
            sut.addLogger(newLogger: strictLogger, minLogLevel: .error, minLogType: .error) { success in
                XCTAssertTrue(success); fulfill()
            }
        }
        
        let logExpectation = XCTestExpectation(description: "Combined filter test")
        mockDefaultLogger.expectation = logExpectation
        let strictExpectation = XCTestExpectation(description: "Strict logger should not receive the log")
        strictExpectation.isInverted = true
        strictLogger.expectation = strictExpectation
        
        sut.log(message: "warning log", logType: .warning) // Level is .error, Type is .warning. Should pass default but fail strict.
        
        wait(for: [logExpectation, strictExpectation], timeout: 1.0)
        XCTAssertEqual(mockDefaultLogger.logCallCount, 1)
        XCTAssertEqual(strictLogger.logCallCount, 0)
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

        let defaultLoggerExpectation = XCTestExpectation(description: "Default logger should receive log")
        let specificLoggerExpectation = XCTestExpectation(description: "Specific logger should receive log")
        mockDefaultLogger.expectation = defaultLoggerExpectation
        loggerSpecificLogger.expectation = specificLoggerExpectation
        
        sut.log(message: "tag test", logType: .info)
        
        wait(for: [defaultLoggerExpectation, specificLoggerExpectation], timeout: 1.0)
        
        let defaultMsg = mockDefaultLogger.lastLoggedMessage
        XCTAssertNotNil(defaultMsg)
        XCTAssertTrue(defaultMsg?.tags.contains(where: { $0.identifier == "ManagerTag" }) ?? false)
        XCTAssertFalse(defaultMsg?.tags.contains(where: { $0.identifier == "LoggerTag" }) ?? false)
        
        let specificMsg = loggerSpecificLogger.lastLoggedMessage
        XCTAssertNotNil(specificMsg)
        XCTAssertTrue(specificMsg?.tags.contains(where: { $0.identifier == "ManagerTag" }) ?? false)
        XCTAssertTrue(specificMsg?.tags.contains(where: { $0.identifier == "LoggerTag" }) ?? false)
    }
}
