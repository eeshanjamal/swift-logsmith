//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objc internal protocol LogTaggerOperations: Sendable {

    @objc func addLogPrefix(logTag: any LogTag, completion: (@Sendable(Bool) -> Void)?)
    @objc func removeLogPrefix(identifier: String, completion: (@Sendable(Bool) -> Void)?)
    @objc func addLogPostfix(logTag: any LogTag, completion: (@Sendable(Bool) -> Void)?)
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
    
    public func addLogPrefix(logTag: any LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
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
    
    public func logPrefixTags(logType: LogType, completion: @escaping (@Sendable([any LogTag]) -> Void)) {
        queue.async {
            completion(self.prefixTags(logType: logType))
        }
    }
    
    //MARK: Log Postfix API's
    
    public func addLogPostfix(logTag: any LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
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
    
    public func logPostfixTags(logType: LogType, completion: @escaping (@Sendable([any LogTag]) -> Void)) {
        queue.async {
            completion(self.postfixTags(logType: logType))
        }
    }
    
    //MARK: Other API's
    
    public func logTags(logType: LogType, completion: @escaping (@Sendable([any LogTag], [any LogTag]) -> Void)) {
        queue.async {
            completion(self.prefixTags(logType: logType), self.postfixTags(logType: logType))
        }
    }
    
    private func prefixTags(logType: LogType) -> [any LogTag] {
        return logPrefixes.logTags.filter { $0.logType == .undefined || $0.logType == logType }
    }
    
    private func postfixTags(logType: LogType) -> [any LogTag] {
        return logPostfixes.logTags.filter { $0.logType == .undefined || $0.logType == logType }
    }
}

private final class LogTagCollection: NSObject, @unchecked Sendable {
    
    var logTags: Array<any LogTag>
    
    override init() {
        self.logTags = []
        super.init()
    }
    
    init(_ logTags: Array<any LogTag>) {
        self.logTags = Array(logTags)
        super.init()
    }
    
    func addTag(_ logTag: any LogTag) -> Bool {
        if self.logTags.first(where: {$0.identifier == logTag.identifier}) != nil {
            return false
        }
        else {
            self.logTags.append(logTag)
            return true
        }
    }
    
    func removeTag(_ identifier: String) -> Bool {
        if let tagIndex = self.logTags.firstIndex(where: {$0.identifier == identifier}) {
            self.logTags.remove(at: tagIndex)
            return true
        }
        else {
            return false
        }
    }
    
}

