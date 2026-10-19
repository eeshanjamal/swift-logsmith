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

/// Shows how the bridge's `logLevel` and SwiftLogSmith's own minimums combine, however each of them is configured.
///
/// A bridged message is delivered only if it passes, in order: the handler's `logLevel` (which `swift-log` checks
/// before it calls the handler), the manager's minimum log type and minimum log level, and the minimums of the
/// destination logger. Both sides order severity the same way, so what gets through is whatever both sides admit,
/// that is, the stricter of the two.
///
/// Every test runs against both places a bridged logger can deliver to: an isolated `LogManager` (as with
/// `bootstrapWithLogSmith(manager:)`) and the shared `LogSmith` pipeline (as with `bootstrapWithLogSmith()`).
/// Loggers are built from `logSmithHandlerFactory`, the factory both bootstrap functions install, because
/// `LoggingSystem.bootstrap` itself traps on a second call.
///
/// The severity orders and the mappings are written out by hand below rather than derived from the code under test.
final class BridgeThresholdTests: XCTestCase {

    private static let label = "com.swiftlogsmith.thresholds"

    /// The `swift-log` levels, lowest severity first, with the `LogType` and `LogLevel` each one is delivered as.
    private static let swiftLogLevels: [(level: Logger.Level, type: LogType, rolledUpLevel: LogLevel)] = [
        (.trace, .trace, .debug),
        (.debug, .debug, .debug),
        (.info, .info, .info),
        (.notice, .notice, .info),
        (.warning, .warning, .error),
        (.error, .error, .error),
        (.critical, .critical, .fault)
    ]
    /// Every `LogType`, lowest severity first.
    private static let typesBySeverity: [LogType] = [.undefined, .none, .trace, .debug, .info, .notice, .warning, .error, .fault, .critical]
    /// Every `LogLevel`, lowest severity first.
    private static let levelsBySeverity: [LogLevel] = [.all, .debug, .info, .error, .fault]
    private static let allSwiftLogLevels: [Logger.Level] = swiftLogLevels.map { $0.level }

    /// One place a bridged logger can deliver to, with the spy that sees what comes out of it.
    private struct Pipeline {
        let name: String
        /// What the bootstrap is given: the isolated manager, or `nil` for the shared pipeline.
        let manager: LogManager?
        let receiver: BackendMockLogger
        let setMinimumLogType: (LogType) -> Void
        let setMinimumLogLevel: (LogLevel) -> Void
    }

    private var isolatedLogger: BackendMockLogger!
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
        LogSmith.setMinimumLogLevel(.all)
        LogSmith.setMinimumLogType(.none)
        manager = nil
        sharedLogger = nil
        isolatedLogger = nil
        super.tearDown()
    }

    //MARK: Helpers

    private var pipelines: [Pipeline] {
        let manager: LogManager = self.manager
        return [
            Pipeline(name: "isolated manager",
                     manager: manager,
                     receiver: isolatedLogger,
                     setMinimumLogType: { manager.setMinimumLogType($0) },
                     setMinimumLogLevel: { manager.setMinimumLogLevel($0) }),
            Pipeline(name: "shared pipeline",
                     manager: nil,
                     receiver: sharedLogger,
                     setMinimumLogType: { LogSmith.setMinimumLogType($0) },
                     setMinimumLogLevel: { LogSmith.setMinimumLogLevel($0) })
        ]
    }

    /// A logger as `bootstrapWithLogSmith` would hand it out, starting at `bridgeLevel`.
    private func makeBridgedLogger(for pipeline: Pipeline, bridgeLevel: Logger.Level) -> Logger {
        let factory = LoggingSystem.logSmithHandlerFactory(manager: pipeline.manager,
                                                           defaultLogLevel: bridgeLevel,
                                                           includesSwiftLogContextInMetadata: true)
        return Logger(label: Self.label, factory: factory)
    }

    /// Logs one message at every `swift-log` level through `logger`, followed by a critical one that always passes,
    /// and returns the levels that reached the pipeline, in order.
    private func deliveredLevels(from logger: Logger, through pipeline: Pipeline) -> [Logger.Level] {
        pipeline.receiver.reset()
        expectCompletion(description: "all messages processed", timeout: 5.0) { fulfill in
            pipeline.receiver.setOnLog { message in
                if message.message == "sentinel" { fulfill() }
            }
            for level in Self.allSwiftLogLevels {
                logger.log(level: level, "\(level.rawValue)")
            }
            logger.critical("sentinel")
        }
        return pipeline.receiver.messages.compactMap { Logger.Level(rawValue: $0.message) }
    }

    /// Applies the given minimums to `pipeline`, builds a logger at `bridgeLevel` and returns what it delivers.
    private func delivered(through pipeline: Pipeline,
                           bridgeLevel: Logger.Level,
                           minimumType: LogType = .none,
                           minimumLevel: LogLevel = .all) -> [Logger.Level] {
        pipeline.setMinimumLogType(minimumType)
        pipeline.setMinimumLogLevel(minimumLevel)
        return deliveredLevels(from: makeBridgedLogger(for: pipeline, bridgeLevel: bridgeLevel), through: pipeline)
    }

    /// What should be delivered for the given configuration: the `swift-log` levels that the bridge level, the
    /// minimum type and the minimum level all admit, lowest severity first.
    private func expectedLevels(bridgeLevel: Logger.Level, minimumType: LogType = .none, minimumLevel: LogLevel = .all) -> [Logger.Level] {
        let bridgeRank = Self.allSwiftLogLevels.firstIndex(of: bridgeLevel)!
        let minimumTypeRank = Self.typesBySeverity.firstIndex(of: minimumType)!
        let minimumLevelRank = Self.levelsBySeverity.firstIndex(of: minimumLevel)!

        return Self.swiftLogLevels.enumerated().filter { rank, entry in
            rank >= bridgeRank
                && Self.typesBySeverity.firstIndex(of: entry.type)! >= minimumTypeRank
                && Self.levelsBySeverity.firstIndex(of: entry.rolledUpLevel)! >= minimumLevelRank
        }.map { $0.element.level }
    }

    //MARK: Every combination

    func testEffectiveThreshold_WithEveryBridgeLevelAndMinimumLogType_ShouldAdmitWhatBothAdmit() {
        for pipeline in pipelines {
            for bridgeLevel in Self.allSwiftLogLevels {
                for minimumType in Self.typesBySeverity {
                    XCTAssertEqual(delivered(through: pipeline, bridgeLevel: bridgeLevel, minimumType: minimumType),
                                   expectedLevels(bridgeLevel: bridgeLevel, minimumType: minimumType),
                                   "\(pipeline.name): bridge level \(bridgeLevel), minimum type \(minimumType)")
                }
            }
        }
    }

    func testEffectiveThreshold_WithEveryBridgeLevelAndMinimumLogLevel_ShouldAdmitWhatBothAdmit() {
        for pipeline in pipelines {
            for bridgeLevel in Self.allSwiftLogLevels {
                for minimumLevel in Self.levelsBySeverity {
                    XCTAssertEqual(delivered(through: pipeline, bridgeLevel: bridgeLevel, minimumLevel: minimumLevel),
                                   expectedLevels(bridgeLevel: bridgeLevel, minimumLevel: minimumLevel),
                                   "\(pipeline.name): bridge level \(bridgeLevel), minimum level \(minimumLevel)")
                }
            }
        }
    }

    //MARK: Named configurations

    func testEffectiveThreshold_WithBridgeAndFirstPartyPullingInOppositeDirections_ShouldDeliverWhatBothAdmit() {
        // Arrange — what the table below is saying, in words: whichever side is stricter wins, and a minimum
        // type or level admits that severity and everything above it.
        let all: [Logger.Level] = [.trace, .debug, .info, .notice, .warning, .error, .critical]
        let scenarios: [(name: String, bridgeLevel: Logger.Level, minimumType: LogType, minimumLevel: LogLevel, delivered: [Logger.Level])] = [
            ("neither side filters", .trace, .none, .all, all),
            ("bridge stricter than the type minimum", .error, .trace, .all, [.error, .critical]),
            ("type minimum stricter than the bridge", .trace, .error, .all, [.error, .critical]),
            ("bridge at notice, type minimum info", .notice, .info, .all, [.notice, .warning, .error, .critical]),
            ("bridge at info, type minimum notice", .info, .notice, .all, [.notice, .warning, .error, .critical]),
            ("type minimum info keeps notice", .trace, .info, .all, [.info, .notice, .warning, .error, .critical]),
            ("type minimum trace keeps everything", .trace, .trace, .all, all),
            ("bridge at warning, level minimum info", .warning, .none, .info, [.warning, .error, .critical]),
            ("bridge at debug, level minimum error", .debug, .none, .error, [.warning, .error, .critical]),
            ("bridge at trace, level minimum fault", .trace, .none, .fault, [.critical]),
            ("bridge at critical, level minimum debug", .critical, .none, .debug, [.critical]),
            ("bridge at debug, type minimum fault, level minimum info", .debug, .fault, .info, [.critical])
        ]

        for pipeline in pipelines {
            for scenario in scenarios {
                // Act
                let actual = delivered(through: pipeline,
                                       bridgeLevel: scenario.bridgeLevel,
                                       minimumType: scenario.minimumType,
                                       minimumLevel: scenario.minimumLevel)

                // Assert
                XCTAssertEqual(actual, scenario.delivered, "\(pipeline.name): \(scenario.name)")
            }
        }
    }

    //MARK: Changing a threshold after bootstrap

    func testBridgeLogLevel_ChangedAfterBootstrap_ShouldApplyToThatLoggerOnly() {
        let all = Self.allSwiftLogLevels

        for pipeline in pipelines {
            // Arrange — a logger that starts at the bootstrap level, and a copy that is changed later.
            let logger = makeBridgedLogger(for: pipeline, bridgeLevel: .trace)
            var changed = logger
            XCTAssertEqual(deliveredLevels(from: changed, through: pipeline), all, "\(pipeline.name): at bootstrap")

            // Act & Assert — raising and lowering the level applies from the next message on.
            changed.logLevel = .error
            XCTAssertEqual(deliveredLevels(from: changed, through: pipeline), [.error, .critical], "\(pipeline.name): raised to error")
            changed.logLevel = .notice
            XCTAssertEqual(deliveredLevels(from: changed, through: pipeline), [.notice, .warning, .error, .critical], "\(pipeline.name): lowered to notice")
            changed.logLevel = .trace
            XCTAssertEqual(deliveredLevels(from: changed, through: pipeline), all, "\(pipeline.name): lowered to trace")

            // `Logger` is a value: changing the copy never touched the logger it came from.
            changed.logLevel = .critical
            XCTAssertEqual(deliveredLevels(from: changed, through: pipeline), [.critical], "\(pipeline.name): the copy")
            XCTAssertEqual(deliveredLevels(from: logger, through: pipeline), all, "\(pipeline.name): the original")
        }
    }

    func testFirstPartyMinimums_ChangedAfterBootstrap_ShouldApplyToLoggersThatAlreadyExist() {
        for pipeline in pipelines {
            // Arrange
            let logger = makeBridgedLogger(for: pipeline, bridgeLevel: .trace)
            XCTAssertEqual(deliveredLevels(from: logger, through: pipeline), Self.allSwiftLogLevels, "\(pipeline.name): at bootstrap")

            // Act & Assert — every change applies to the same logger, from the next message on.
            pipeline.setMinimumLogType(.notice)
            XCTAssertEqual(deliveredLevels(from: logger, through: pipeline), [.notice, .warning, .error, .critical], "\(pipeline.name): type minimum notice")
            pipeline.setMinimumLogLevel(.error)
            XCTAssertEqual(deliveredLevels(from: logger, through: pipeline), [.warning, .error, .critical], "\(pipeline.name): and level minimum error")
            pipeline.setMinimumLogType(.none)
            XCTAssertEqual(deliveredLevels(from: logger, through: pipeline), [.warning, .error, .critical], "\(pipeline.name): type minimum lifted, level minimum remains")
            pipeline.setMinimumLogLevel(.all)
            XCTAssertEqual(deliveredLevels(from: logger, through: pipeline), Self.allSwiftLogLevels, "\(pipeline.name): both lifted")
        }
    }

    func testBridgeAndFirstPartyThresholds_ChangedInOppositeDirections_ShouldFollowTheStricterEachTime() {
        for pipeline in pipelines {
            // Arrange — the bridge is the stricter side, the first-party minimum is permissive.
            var logger = makeBridgedLogger(for: pipeline, bridgeLevel: .warning)
            pipeline.setMinimumLogType(.trace)
            XCTAssertEqual(deliveredLevels(from: logger, through: pipeline), [.warning, .error, .critical], "\(pipeline.name): bridge governs")

            // Act & Assert — loosen the bridge while tightening the first-party minimum, so the roles swap.
            logger.logLevel = .trace
            pipeline.setMinimumLogType(.error)
            XCTAssertEqual(deliveredLevels(from: logger, through: pipeline), [.error, .critical], "\(pipeline.name): first party governs")

            // And back again, further out.
            logger.logLevel = .critical
            pipeline.setMinimumLogType(.none)
            XCTAssertEqual(deliveredLevels(from: logger, through: pipeline), [.critical], "\(pipeline.name): bridge governs again")

            // Both loosened.
            logger.logLevel = .trace
            XCTAssertEqual(deliveredLevels(from: logger, through: pipeline), Self.allSwiftLogLevels, "\(pipeline.name): neither governs")
        }
    }

    //MARK: Destinations

    func testDestinationMinimum_WithBridgeAtInfo_ShouldFilterOnlyThatDestination() {
        // Arrange — the manager's default logger takes everything the bridge lets through; the second one only warnings and above.
        let strict = BackendMockLogger()
        let added = expectation(description: "destination added")
        manager.addLogger(newLogger: strict, minLogType: .warning) { _ in added.fulfill() }
        wait(for: [added], timeout: 2)
        let pipeline = pipelines[0]
        let logger = makeBridgedLogger(for: pipeline, bridgeLevel: .info)

        // Act
        let permissiveDelivered = deliveredLevels(from: logger, through: pipeline)
        let strictDelivered = strict.messages.compactMap { Logger.Level(rawValue: $0.message) }

        // Assert
        XCTAssertEqual(permissiveDelivered, [.info, .notice, .warning, .error, .critical])
        XCTAssertEqual(strictDelivered, [.warning, .error, .critical])
    }

    func testManagerMinimum_WithPermissiveDestinations_ShouldStillBindEveryDestination() {
        // Arrange — destinations can narrow what the manager admits, never widen it.
        let second = BackendMockLogger()
        let added = expectation(description: "destination added")
        manager.addLogger(newLogger: second, minLogType: .trace) { _ in added.fulfill() }
        wait(for: [added], timeout: 2)
        let pipeline = pipelines[0]
        pipeline.setMinimumLogType(.error)
        let logger = makeBridgedLogger(for: pipeline, bridgeLevel: .trace)

        // Act
        let firstDelivered = deliveredLevels(from: logger, through: pipeline)
        let secondDelivered = second.messages.compactMap { Logger.Level(rawValue: $0.message) }

        // Assert
        XCTAssertEqual(firstDelivered, [.error, .critical])
        XCTAssertEqual(secondDelivered, [.error, .critical])
    }
}
