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
    let completeMessage: String
    
    internal init(message: String, logType: LogType, prefixTags: [Tag], postfixTags: [Tag], metadata: [String: String]) {
        self.message = message
        self.logType = logType
        self.prefixTags = prefixTags
        self.postfixTags = postfixTags
        self.metadata = metadata
        
        //Build complete message
        var msgBuilder = String()
        let prefix = LogMessage.toStringValue(tags: prefixTags)
        let postfix = LogMessage.toStringValue(tags: postfixTags)
        
        if !prefix.isEmpty {
            msgBuilder.append(" \(prefix)")
        }
        
        if !message.isEmpty {
            msgBuilder.append(" \(message)")
        }
        
        if !postfix.isEmpty {
            msgBuilder.append(" \(postfix)")
        }
        
        if !metadata.isEmpty {
            msgBuilder.append(" \(metadata)")
        }
        
        self.completeMessage = msgBuilder.isEmpty ? msgBuilder : String(msgBuilder.dropFirst())
    }
    
    private static func toStringValue(tags: [Tag]) -> String {
        var valueBuilder = ""
        tags.forEach { valueBuilder.append(formattedTagValue($0))  }
        return finalValue(inputValue: valueBuilder)
    }
    
    private static func formattedTagValue(_ tag: Tag) -> String {
        return " [\(tag.value)]"
    }

    private static func finalValue(inputValue: String) -> String {
        return inputValue.isEmpty ? inputValue : String(inputValue.dropFirst())
    }
    
}
