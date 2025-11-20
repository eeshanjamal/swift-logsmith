//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objc internal protocol LogTaggerOperations: Sendable {

    @objc func addLogPrefix(logTag: LogTag, completion: (@Sendable(Bool) -> Void)?)
    @objc func removeLogPrefix(identifier: String, completion: (@Sendable(Bool) -> Void)?)
    @objc func addLogPostfix(logTag: LogTag, completion: (@Sendable(Bool) -> Void)?)
    @objc func removeLogPostfix(identifier: String, completion: (@Sendable(Bool) -> Void)?)
}

@objcMembers
final class LogTagger: NSObject, LogTaggerOperations, @unchecked Sendable {
    
    private let logPrefixes: LogTagCollection
    private let logPostfixes: LogTagCollection
    private let queue: DispatchQueue
    
    override init() {
        queue = DispatchQueue(label: "com.swift.logtag.\(NSUUID().uuidString)")
        logPrefixes = LogTagCollection()
        logPostfixes = LogTagCollection()
        super.init()
    }
    
    //MARK: Log Prefix API's
    
    public func addLogPrefix(logTag: LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            let result = self.logPrefixes.addTag(logTag)
            completion?(result)
        }
    }
    
    public func  removeLogPrefix(identifier: String, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            let result = self.logPrefixes.removeTag(identifier)
            completion?(result)
        }
    }
    
    public func logPrefixValue(logType: LogType? = nil, completion: @escaping (@Sendable(String) -> Void)) {
        queue.async {
            var prefixValue = String()
            let noTypePrefixValue = self.logPrefixes.toNoTypeString()
            if !noTypePrefixValue.isEmpty {
                prefixValue.append(" \(noTypePrefixValue)")
            }
            if let logType = logType {
                let typePrefixValue = self.logPrefixes.toTypeString(logType: logType)
                if !typePrefixValue.isEmpty {
                    prefixValue.append(" \(typePrefixValue)")
                }
            }
            completion(prefixValue.isEmpty ? prefixValue : String(prefixValue.dropFirst()))
        }
    }
    
    //MARK: Log Postfix API's
    
    public func addLogPostfix(logTag: LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            let result = self.logPostfixes.addTag(logTag)
            completion?(result)
        }
    }
    
    public func removeLogPostfix(identifier: String, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            let result = self.logPostfixes.removeTag(identifier)
            completion?(result)
        }
    }
    
    public func logPostfixValue(logType: LogType? = nil, completion: @escaping (@Sendable(String) -> Void)) {
        queue.async {
            var postfixValue = String()
            let noTypePostfixValue = self.logPostfixes.toNoTypeString()
            if !noTypePostfixValue.isEmpty {
                postfixValue.append(" \(noTypePostfixValue)")
            }
            if let logType = logType {
                let typePostfixValue = self.logPostfixes.toTypeString(logType: logType)
                if !typePostfixValue.isEmpty {
                    postfixValue.append(" \(typePostfixValue)")
                }
            }
            completion(postfixValue.isEmpty ? postfixValue : String(postfixValue.dropFirst()))
        }
    }
}

@objcMembers
final class LogTag: NSObject, @unchecked Sendable {
    
    let identifier: String
    let logType: LogType?
    let value: String
    
    init(identifier: String, value: String, logType: LogType? = nil){
        self.identifier = identifier
        self.logType = logType
        self.value = value
        super.init()
    }    
}

@objcMembers
private final class LogTagCollection: NSObject, @unchecked Sendable {
    
    private var logTags: Array<LogTag>
    private var values: String
    private var typeValues: [LogType? : String]
    
    override init() {
        self.logTags = []
        self.values = ""
        self.typeValues = Dictionary()
        super.init()
    }
    
    init(_ logTags: Array<LogTag>) {
        self.logTags = Array(logTags)
        self.values = LogTagCollection.toStringValue(logTags: self.logTags)
        self.typeValues = LogTagCollection.toTypeStringValue(logTags: self.logTags)
        super.init()
    }
    
    func toString() -> String {
        return self.values
    }
    
    func toNoTypeString() -> String {
        return self.typeValues[nil, default: ""]
    }
    
    func toTypeString(logType: LogType) -> String {
        return self.typeValues[logType, default: ""]
    }
    
    func addTag(_ logTag: LogTag) -> Bool {
        if self.logTags.first(where: {$0.identifier == logTag.identifier}) != nil {
            return false
        }
        else {
            self.logTags.append(logTag)
            self.values = LogTagCollection.toStringValue(logTags: self.logTags)
            self.typeValues = LogTagCollection.toTypeStringValue(logTags: self.logTags)
            return true
        }
    }
    
    func removeTag(_ identifier: String) -> Bool {
        if let tagIndex = self.logTags.firstIndex(where: {$0.identifier == identifier}) {
            self.logTags.remove(at: tagIndex)
            self.values = LogTagCollection.toStringValue(logTags: self.logTags)
            self.typeValues = LogTagCollection.toTypeStringValue(logTags: self.logTags)
            return true
        }
        else {
            return false
        }
    }
    
    private static func toStringValue(logTags: Array<LogTag>) -> String {
        var valueBuilder = ""
        logTags.forEach { valueBuilder.append(formattedTagValue($0))  }
        return finalValue(inputValue: valueBuilder)
    }
    
    private static func toTypeStringValue(logTags: Array<LogTag>) -> [LogType? : String] {
        var typeValues = [LogType? : String]()
        logTags.forEach { logTag in
            let typeValue = typeValues[logTag.logType, default: ""].appending(formattedTagValue(logTag))
            typeValues.updateValue(typeValue, forKey: logTag.logType)
        }
        typeValues.keys.forEach { logType in
            typeValues.updateValue(finalValue(inputValue: typeValues[logType, default: ""]), forKey: logType)
        }
        return typeValues
    }
    
    private static func formattedTagValue(_ logTag: LogTag) -> String {
        return " [\(logTag.value)]"
    }
    
    private static func finalValue(inputValue: String) -> String {
        return inputValue.isEmpty ? inputValue : String(inputValue.dropFirst())
    }
}

