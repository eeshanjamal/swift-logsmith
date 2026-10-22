//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import SwiftLogSmith

/// Records the type of every message it receives, in order. The message "sentinel" only marks the end of a run and is not recorded.
private final class ThresholdCollectingLogger: ILogger, @unchecked Sendable {
    var tagger: LogTagger?
    var formatter: LogFormatter = LogFormatter.default
    private let lock = NSLock()
    private var recorded: [LogType] = []

    var types: [LogType] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)?) {
        if message.message != "sentinel" {
            lock.lock()
            recorded.append(message.logType)
            lock.unlock()
        }
        completion?(true)
    }
}

/// Pins how the minimum log level and minimum log type filter, and that both are ordered by severity.
///
/// The orders below are written out by hand rather than derived from the raw values, so these tests fail if the
/// raw values and the intended order ever drift apart.
final class LogThresholdTests: XCTestCase {

    /// Every `LogType`, lowest severity first.
    private static let typesBySeverity: [LogType] = [.undefined, .none, .trace, .debug, .info, .notice, .warning, .error, .fault, .critical]
    /// Every `LogLevel`, lowest severity first.
    private static let levelsBySeverity: [LogLevel] = [.all, .debug, .info, .error, .fault]
    /// The types a default manager delivers: everything except `undefined`, which has its own tests.
    private static let deliverableTypes: [LogType] = Array(typesBySeverity.dropFirst())

    //MARK: Helpers

    /// Sends one message of each of `types` through `manager`, in order, and waits until all of them have been processed.
    private func send(_ types: [LogType], through manager: LogManager) {
        let processed = expectation(description: "messages processed")
        for type in types {
            manager.log(message: "\(type)", logType: type)
        }
        manager.log(message: "sentinel", logType: .critical) { _ in processed.fulfill() }
        wait(for: [processed], timeout: 5)
    }

    /// The types that pass the given minimums, in severity order, according to the hand-written orders above.
    private func expectedTypes(minimumLevel: LogLevel = .all, minimumType: LogType = .none) -> [LogType] {
        let minimumLevelIndex = Self.levelsBySeverity.firstIndex(of: minimumLevel)!
        let minimumTypeIndex = Self.typesBySeverity.firstIndex(of: minimumType)!
        return Self.typesBySeverity.filter { type in
            Self.levelsBySeverity.firstIndex(of: type.logLevel)! >= minimumLevelIndex
                && Self.typesBySeverity.firstIndex(of: type)! >= minimumTypeIndex
        }
    }

    /// Delivers every deliverable type through a fresh manager configured with the given manager-wide minimums.
    private func deliveredTypes(minimumLevel: LogLevel? = nil, minimumType: LogType? = nil) -> [LogType] {
        let logger = ThresholdCollectingLogger()
        let manager = LogManager(identifier: UUID().uuidString, defaultLogger: logger)
        if let minimumLevel { manager.setMinimumLogLevel(minimumLevel) }
        if let minimumType { manager.setMinimumLogType(minimumType) }
        send(Self.deliverableTypes, through: manager)
        return logger.types
    }

    //MARK: Raw values and mapping

    func testLogTypeRawValues_ShouldIncreaseWithSeverity() {
        XCTAssertEqual(Self.typesBySeverity.map(\.rawValue), [-1, 0, 1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(LogType.allCases, Self.typesBySeverity, "allCases should list the types in severity order")
    }

    func testLogLevelRawValues_ShouldIncreaseWithSeverity() {
        XCTAssertEqual(Self.levelsBySeverity.map(\.rawValue), [0, 1, 2, 3, 4])
        XCTAssertEqual(LogLevel.allCases, Self.levelsBySeverity, "allCases should list the levels in severity order")
    }

    func testLogLevel_OfEachLogType_ShouldMatchTheDocumentedMapping() {
        let expected: [(LogType, LogLevel)] = [
            (.undefined, .all), (.none, .all),
            (.trace, .debug), (.debug, .debug),
            (.info, .info), (.notice, .info),
            (.warning, .error), (.error, .error),
            (.fault, .fault), (.critical, .fault)
        ]

        for (type, level) in expected {
            XCTAssertEqual(type.logLevel, level, "\(type) should map to \(level)")
        }
    }

    func testLogLevel_AsSeverityRises_ShouldNeverGoDown() {
        for (lower, higher) in zip(Self.typesBySeverity, Self.typesBySeverity.dropFirst()) {
            XCTAssertLessThanOrEqual(lower.logLevel.rawValue, higher.logLevel.rawValue, "\(lower) -> \(higher)")
        }
    }

    //MARK: Manager-wide minimums

    func testDefaultMinimums_ShouldAdmitEveryTypeButUndefined() {
        XCTAssertEqual(deliveredTypes(), Self.deliverableTypes)
    }

    func testMinimumLogType_ShouldAdmitOnlyTypesAtLeastAsSevere() {
        for minimum in Self.deliverableTypes {
            XCTAssertEqual(deliveredTypes(minimumType: minimum), expectedTypes(minimumType: minimum), "minimum type \(minimum)")
        }
    }

    func testMinimumLogLevel_ShouldAdmitOnlyLevelsAtLeastAsSevere() {
        for minimum in Self.levelsBySeverity {
            XCTAssertEqual(deliveredTypes(minimumLevel: minimum), expectedTypes(minimumLevel: minimum), "minimum level \(minimum)")
        }
    }

    func testMatchingLevelAndTypeMinimums_ShouldAdmitTheSameTypes() {
        let matchingCuts: [(LogLevel, LogType)] = [(.all, .none), (.debug, .trace), (.info, .info), (.error, .warning), (.fault, .fault)]

        for (level, type) in matchingCuts {
            XCTAssertEqual(deliveredTypes(minimumLevel: level), deliveredTypes(minimumType: type), "level \(level) vs type \(type)")
        }
    }

    //MARK: Undefined

    func testUndefinedType_WithDefaultMinimums_ShouldBeDropped() {
        // Arrange
        let logger = ThresholdCollectingLogger()
        let manager = LogManager(identifier: UUID().uuidString, defaultLogger: logger)

        // Act
        send([.undefined], through: manager)

        // Assert
        XCTAssertEqual(logger.types, [])
    }

    func testUndefinedType_WithOnlyTheTypeMinimumsLowered_ShouldBeDelivered() {
        // Arrange — the manager's and the default logger's type minimums both have to admit `undefined`.
        // The level minimums can stay at their defaults, because `undefined` maps to `LogLevel.all`.
        let logger = ThresholdCollectingLogger()
        let manager = LogManager(identifier: UUID().uuidString, defaultLogger: logger, minLogType: .undefined)
        manager.setMinimumLogType(.undefined)

        // Act
        send([.undefined], through: manager)

        // Assert
        XCTAssertEqual(logger.types, [.undefined])
    }

    //MARK: Per-logger minimums

    func testAddLogger_WithMinimums_ShouldAdmitOnlyTypesPassingBothMinimums() {
        // Arrange — one logger where the level is the stricter cut, one where the type is.
        let defaultLogger = ThresholdCollectingLogger()
        let levelStricter = ThresholdCollectingLogger()
        let typeStricter = ThresholdCollectingLogger()
        let manager = LogManager(identifier: UUID().uuidString, defaultLogger: defaultLogger)
        let added = expectation(description: "loggers added")
        added.expectedFulfillmentCount = 2
        manager.addLogger(newLogger: levelStricter, minLogLevel: .error, minLogType: .debug) { _ in added.fulfill() }
        manager.addLogger(newLogger: typeStricter, minLogLevel: .info, minLogType: .warning) { _ in added.fulfill() }
        wait(for: [added], timeout: 2)

        // Act
        send(Self.deliverableTypes, through: manager)

        // Assert
        XCTAssertEqual(defaultLogger.types, Self.deliverableTypes)
        XCTAssertEqual(levelStricter.types, expectedTypes(minimumLevel: .error, minimumType: .debug))
        XCTAssertEqual(levelStricter.types, [.warning, .error, .fault, .critical])
        XCTAssertEqual(typeStricter.types, expectedTypes(minimumLevel: .info, minimumType: .warning))
        XCTAssertEqual(typeStricter.types, [.warning, .error, .fault, .critical])
    }

    //MARK: UserDefaults overrides

    func testMinimumLogType_WithValidOverride_ShouldUseTheOverride() {
        // Arrange — the raw value is the identity of the case, so an override of `LogType.info.rawValue` means "info".
        let identifier = UUID().uuidString
        let key = "\(identifier).\(LogManager.defaults.minimumLogType.rawValue)"
        UserDefaults.standard.set(LogType.info.rawValue, forKey: key)
        addTeardownBlock { UserDefaults.standard.removeObject(forKey: key) }
        let logger = ThresholdCollectingLogger()
        let manager = LogManager(identifier: identifier, defaultLogger: logger)

        // Act
        send(Self.deliverableTypes, through: manager)

        // Assert
        XCTAssertEqual(logger.types, expectedTypes(minimumType: .info))
    }

    func testMinimumLogType_WithInvalidOverride_ShouldBeIgnored() {
        // Arrange
        let identifier = UUID().uuidString
        let key = "\(identifier).\(LogManager.defaults.minimumLogType.rawValue)"
        UserDefaults.standard.set(99, forKey: key)
        addTeardownBlock { UserDefaults.standard.removeObject(forKey: key) }
        let logger = ThresholdCollectingLogger()
        let manager = LogManager(identifier: identifier, defaultLogger: logger)
        manager.setMinimumLogType(.warning)

        // Act
        send(Self.deliverableTypes, through: manager)

        // Assert — the configured minimum applies, and nothing traps.
        XCTAssertEqual(logger.types, expectedTypes(minimumType: .warning))
    }

    func testMinimumLogLevel_WithInvalidOverride_ShouldBeIgnored() {
        // Arrange — -1 was `LogLevel.undefined` before that case was removed, so a leftover override can still hold it.
        let identifier = UUID().uuidString
        let key = "\(identifier).\(LogManager.defaults.minimumLogLevel.rawValue)"
        UserDefaults.standard.set(-1, forKey: key)
        addTeardownBlock { UserDefaults.standard.removeObject(forKey: key) }
        let logger = ThresholdCollectingLogger()
        let manager = LogManager(identifier: identifier, defaultLogger: logger)
        manager.setMinimumLogLevel(.error)

        // Act
        send(Self.deliverableTypes, through: manager)

        // Assert
        XCTAssertEqual(logger.types, expectedTypes(minimumLevel: .error))
    }

    func testLoggerMinimums_WithInvalidOverrides_ShouldBeIgnored() {
        // Arrange — per-logger overrides are keyed by the manager identifier and the logger's type name.
        let identifier = UUID().uuidString
        let loggerName = String(describing: ThresholdCollectingLogger.self)
        let levelKey = "\(identifier).\(loggerName).\(LogManager.defaults.minimumLogLevel.rawValue)"
        let typeKey = "\(identifier).\(loggerName).\(LogManager.defaults.minimumLogType.rawValue)"
        UserDefaults.standard.set(-1, forKey: levelKey)
        UserDefaults.standard.set(99, forKey: typeKey)
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: levelKey)
            UserDefaults.standard.removeObject(forKey: typeKey)
        }
        let logger = ThresholdCollectingLogger()
        let manager = LogManager(identifier: identifier, defaultLogger: logger, minLogLevel: .info, minLogType: .notice)

        // Act
        send(Self.deliverableTypes, through: manager)

        // Assert — the logger's configured minimums apply.
        XCTAssertEqual(logger.types, expectedTypes(minimumLevel: .info, minimumType: .notice))
    }
}
