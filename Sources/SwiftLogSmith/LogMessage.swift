//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objc public enum TagType: Int {
    
    case `internal`
    case external
}

@objcMembers
final class Tag: NSObject, @unchecked Sendable {
    
    let identifier: String
    let value: String
    let tagType: TagType
    
    internal init(identifier: String, value: String, tagType: TagType) {
        self.identifier = identifier
        self.value = value
        self.tagType = tagType
    }
}

@objcMembers
final class LogMessage: NSObject, @unchecked Sendable {
    
    let message: String
    let logType: LogType
    let tags: [Tag]
    let metadata: [String: String]
    
    internal init(message: String, logType: LogType, tags: [Tag], metadata: [String: String]) {
        self.message = message
        self.logType = logType
        self.tags = tags
        self.metadata = metadata
    }
}

