//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import XCTest
@testable import SwiftLogSmith

final class LogTaggerTests: XCTestCase {

    var sut: LogTagger!

    override func setUp() {
        super.setUp()
        sut = LogTagger()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func testAddTag_WithNewIdentifier_ShouldSucceed() {
        let newTag = ExternalTag(identifier: "NewTag", value: "NewValue")

        expectCompletion(description: "addTag should succeed for a new tag") { fulfill in
            sut.addTag(newTag) { success in
                XCTAssertTrue(success, "addTag should return true for a new identifier")
                fulfill()
            }
        }
        
        expectCompletion(description: "Verify the tag was actually added") { fulfill in
            sut.logTags(logType: .undefined) { tags in
                XCTAssertEqual(tags.count, 1)
                XCTAssertTrue(tags.contains(where: { $0.identifier == "NewTag" }))
                fulfill()
            }
        }
    }

    func testAddTag_WithDuplicateIdentifier_ShouldFail() {
        let tag1 = ExternalTag(identifier: "DuplicateTag", value: "Value1")
        let tag2 = ExternalTag(identifier: "DuplicateTag", value: "Value2")

        expectCompletion(description: "First tag should be added successfully") { fulfill in
            sut.addTag(tag1) { success in
                XCTAssertTrue(success)
                fulfill()
            }
        }
        
        expectCompletion(description: "Duplicate tag addition should fail") { fulfill in
            sut.addTag(tag2) { success in
                XCTAssertFalse(success, "addTag should return false for a duplicate identifier")
                fulfill()
            }
        }
        
        expectCompletion(description: "Verify only the first tag remains") { fulfill in
            sut.logTags(logType: .undefined) { tags in
                XCTAssertEqual(tags.count, 1)
                XCTAssertEqual((tags.first as? ExternalTag)?.value, "Value1")
                fulfill()
            }
        }
    }

    func testRemoveTag_WithExistingIdentifier_ShouldSucceed() {
        let tag = ExternalTag(identifier: "TagToRemove", value: "Value")

        expectCompletion(description: "Add tag to be removed") { fulfill in
            sut.addTag(tag) { success in
                XCTAssertTrue(success)
                fulfill()
            }
        }
        
        expectCompletion(description: "removeTag should succeed for an existing tag") { fulfill in
            sut.removeTag(identifier: "TagToRemove") { success in
                XCTAssertTrue(success, "removeTag should return true for an existing identifier")
                fulfill()
            }
        }

        expectCompletion(description: "Verify tag was removed") { fulfill in
            sut.logTags(logType: .undefined) { tags in
                XCTAssertTrue(tags.isEmpty)
                fulfill()
            }
        }
    }
    
    func testRemoveTag_WithNonExistentIdentifier_ShouldFail() {
        expectCompletion(description: "removeTag should fail for a non-existent tag") { fulfill in
            sut.removeTag(identifier: "NonExistentTag") { success in
                XCTAssertFalse(success, "removeTag should return false for a non-existent identifier")
                fulfill()
            }
        }
    }
    
    func testLogTags_ShouldFilterByLogType() {
        let commonTag = ExternalTag(identifier: "Common", value: "v1")
        let infoTag = ExternalTag(identifier: "Info", value: "v2", logType: .info)
        let debugTag = ExternalTag(identifier: "Debug", value: "v3", logType: .debug)

        expectCompletion(description: "Add commonTag") { fulfill in
            sut.addTag(commonTag) { success in XCTAssertTrue(success); fulfill() }
        }
        
        expectCompletion(description: "Add infoTag") { fulfill in
            sut.addTag(infoTag) { success in XCTAssertTrue(success); fulfill() }
        }
        
        expectCompletion(description: "Add debugTag") { fulfill in
            sut.addTag(debugTag) { success in XCTAssertTrue(success); fulfill() }
        }

        expectCompletion(description: "logTags should correctly filter based on LogType") { fulfill in
            sut.logTags(logType: .info) { tags in
                XCTAssertEqual(tags.count, 2, "Should return commonTag and infoTag")
                XCTAssertTrue(tags.contains(where: { $0.identifier == "Common" }))
                XCTAssertTrue(tags.contains(where: { $0.identifier == "Info" }))
                XCTAssertFalse(tags.contains(where: { $0.identifier == "Debug" }))
                fulfill()
            }
        }
    }

    func testExternalTag_InitializationAndProperties() {
        let tag = ExternalTag(identifier: "MyTag", value: "MyValue", logType: .warning)
        XCTAssertEqual(tag.identifier, "MyTag")
        XCTAssertEqual(tag.value, "MyValue")
        XCTAssertEqual(tag.logType, .warning)

        let tagWithValueProvider = ExternalTag(identifier: "DynamicTag", valueProvider: { "DynamicValue" }, logType: .debug)
        XCTAssertEqual(tagWithValueProvider.identifier, "DynamicTag")
        XCTAssertEqual(tagWithValueProvider.value, "DynamicValue")
        XCTAssertEqual(tagWithValueProvider.logType, .debug)
    }

    func testInternalTag_InitializationAndProperties() {
        let fileTag = InternalTag(internalTagType: .file, logType: .trace)
        XCTAssertEqual(fileTag.identifier, "file")
        XCTAssertEqual(fileTag.logType, .trace)
        XCTAssertEqual(fileTag.internalTagType, .file)

        let functionTag = InternalTag(internalTagType: .function, logType: .debug)
        XCTAssertEqual(functionTag.identifier, "function")
        XCTAssertEqual(functionTag.logType, .debug)
        XCTAssertEqual(functionTag.internalTagType, .function)

        let lineTag = InternalTag(internalTagType: .line, logType: .info)
        XCTAssertEqual(lineTag.identifier, "line")
        XCTAssertEqual(lineTag.logType, .info)
        XCTAssertEqual(lineTag.internalTagType, .line)
        
        let threadTag = InternalTag(internalTagType: .threadName, logType: .notice)
        XCTAssertEqual(threadTag.identifier, "threadName")
        XCTAssertEqual(threadTag.logType, .notice)
        XCTAssertEqual(threadTag.internalTagType, .threadName)
    }
}
