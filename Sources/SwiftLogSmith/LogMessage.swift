//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objcMembers
final class Tag: NSObject, @unchecked Sendable {
    
    let key: String
    let value: String
    
    internal init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

@objcMembers
final class LogMessage: NSObject, @unchecked Sendable {
    
    let message: String
    let logType: LogType
    let prefixTags: [Tag]
    let postfixTags: [Tag]
    let metadata: [String: String]
    
    internal init(message: String, logType: LogType, prefixTags: [Tag], postfixTags: [Tag], metadata: [String: String]) {
        self.message = message
        self.logType = logType
        self.prefixTags = prefixTags
        self.postfixTags = postfixTags
        self.metadata = metadata
    }
}

