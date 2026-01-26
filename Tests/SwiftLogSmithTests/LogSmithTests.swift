//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import XCTest
import Foundation
@testable import SwiftLogSmith

private final class LogSmithMockLogger: ILogger, @unchecked Sendable {
    var tagger: LogTagger? = nil
    var formatter: LogFormatter = LogFormatter.default
    var lastLogMessage: LogMessage?
    var logCallCount = 0
    
    func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)?) {
        lastLogMessage = message
        logCallCount += 1
        completion?(true)
    }
    
    func reset() {
        lastLogMessage = nil
        logCallCount = 0
    }
}

final class LogSmithTests: XCTestCase {
    
    private var mockLogger: LogSmithMockLogger!
    
    override func setUp() {
        super.setUp()
        mockLogger = LogSmithMockLogger()
        LogSmith.addLogger(newLogger: mockLogger)
    }
    
    override func tearDown() {
        LogSmith.removeLogger(logger: mockLogger)
        // Reset levels to default
        LogSmith.setMinimumLogLevel(.default)
        LogSmith.setMinimumLogType(.none)
        // Cleanup tags that might have been added
        LogSmith.removeTag(identifier: LogTagIdentifiers.date)
        LogSmith.removeTag(identifier: LogTagIdentifiers.file)
        LogSmith.removeTag(identifier: LogTagIdentifiers.function)
        LogSmith.removeTag(identifier: LogTagIdentifiers.line)
        mockLogger = nil
        super.tearDown()
    }
    
    func testLogSmithLog_WithAllStaticMethods_ShouldExecuteSuccessfully() {
        // Arrange
        let logger = mockLogger!
        
        // Date tag
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-mm-dd HH:mm:ss.SSS"
        LogSmith.addTag(ExternalTag(identifier: LogTagIdentifiers.date, valueProvider: { dateFormatter.string(from: Date()) }))
        
        // System tags
        LogSmith.addTag(InternalTag(internalTagType: .file))
        LogSmith.addTag(InternalTag(internalTagType: .function))
        LogSmith.addTag(InternalTag(internalTagType: .line))
        
        let criticalMetadata = ["error": "404", "description": "Page not found"]
        
        // Act & Assert
        // We test all static log methods and verify variety and propagation
        let logCalls: [(type: LogType, call: (@escaping @Sendable (Bool) -> Void) -> Void)] = [
            (.none,     { LogSmith.log("Sample Log", completion: $0) }),
            (.critical, { LogSmith.logC("Sample Log Critical", metadata: criticalMetadata, completion: $0) }),
            (.debug,    { LogSmith.logD("Sample Log Debug", completion: $0) }),
            (.error,    { LogSmith.logE("Sample Log Error", completion: $0) }),
            (.fault,    { LogSmith.logF("Sample Log Fault", completion: $0) }),
            (.info,     { LogSmith.logI("Sample Log Info", completion: $0) }),
            (.notice,   { LogSmith.logN("Sample Log Notice", completion: $0) }),
            (.trace,    { LogSmith.logT("Sample Log Trace", completion: $0) }),
            (.warning,  { LogSmith.logW("Sample Log Warning", completion: $0) })
        ]
        
        expectCompletion(description: "All static log methods should complete", fulfillmentCount: logCalls.count) { fulfill in
            logCalls.forEach { item in
                let type = item.type
                item.call { result in
                    XCTAssertTrue(result)
                    XCTAssertEqual(logger.lastLogMessage?.logType, type)
                    
                    // Specific metadata check for critical log
                    if type == .critical {
                        XCTAssertEqual(logger.lastLogMessage?.metadata, criticalMetadata)
                    }
                    
                    fulfill()
                }
            }
        }
    }
    
    func testLogSmith_ConfigurationAPIs_ShouldPropagateToManager() {
        let logger = mockLogger!
        
        // 1. Test setMinimumLogLevel filtering
        LogSmith.setMinimumLogLevel(.error)
        logger.reset()
        
        expectCompletion(description: "Debug log should be filtered by level") { fulfill in
            LogSmith.logD("Should be filtered") { _ in
                XCTAssertEqual(logger.logCallCount, 0, "Logger should not have been called for a filtered level")
                fulfill()
            }
        }

        // 2. Test addTag / removeTag
        LogSmith.setMinimumLogLevel(.default)
        let tag = ExternalTag(identifier: "TestStaticTag", value: "Value")
        LogSmith.addTag(tag)
        
        expectCompletion(description: "Verify tag presence") { fulfill in
            LogSmith.logI("Tag test") { _ in
                XCTAssertTrue(logger.lastLogMessage?.tags.contains(where: { $0.identifier == "TestStaticTag" }) ?? false)
                fulfill()
            }
        }
        
        LogSmith.removeTag(tag)
        expectCompletion(description: "Verify tag removal") { fulfill in
            LogSmith.logI("Tag test 2") { _ in
                XCTAssertFalse(logger.lastLogMessage?.tags.contains(where: { $0.identifier == "TestStaticTag" }) ?? false)
                fulfill()
            }
        }
        
        LogSmith.removeTag(identifier: "NonExistent") // Coverage for identifier variant
    }
    
    func testLogSmith_SymbolicTags_ShouldBeInitializedForAllTypes() {
        let logger = mockLogger!
        
        // Verifies that LogSmith adds symbolic tags for all relevant log types.
        let typesToTest = LogType.allCases.filter { $0 != .undefined && $0 != .none }
        
        expectCompletion(description: "All symbolic tags should be present", fulfillmentCount: typesToTest.count) { fulfill in
            typesToTest.forEach { type in
                // We use a specific log call for each type to ensure the correct symbolic tag is triggered.
                // Note: Manager filters tags by logType, so logI will only include the "info" symbolic tag.
                sharedLogCall(type: type) { _ in
                    XCTAssertTrue(logger.lastLogMessage?.tags.contains(where: { 
                        $0.identifier == type.stringValue && $0.value == type.symbolicValue 
                    }) ?? false, "Symbolic tag for \(type) missing or incorrect")
                    fulfill()
                }
            }
        }
    }
    
    // Helper to call the correct static method based on type
    private func sharedLogCall(type: LogType, completion: @escaping @Sendable (Bool) -> Void) {
        switch type {
        case .none: LogSmith.log("test", completion: completion)
        case .notice: LogSmith.logN("test", completion: completion)
        case .info: LogSmith.logI("test", completion: completion)
        case .debug: LogSmith.logD("test", completion: completion)
        case .trace: LogSmith.logT("test", completion: completion)
        case .warning: LogSmith.logW("test", completion: completion)
        case .error: LogSmith.logE("test", completion: completion)
        case .fault: LogSmith.logF("test", completion: completion)
        case .critical: LogSmith.logC("test", completion: completion)
        case .undefined: completion(false)
        }
    }
}
