//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objc internal protocol LogTaggerOperations: Sendable {

    @objc func addTag(_ logTag: any LogTag, completion: (@Sendable(Bool) -> Void)?)
    @objc func removeTag(_ logTag: any LogTag, completion: (@Sendable(Bool) -> Void)?)
    @objc func removeTag(identifier: String, completion: (@Sendable(Bool) -> Void)?)
}

@objcMembers
final class LogTagger: NSObject, LogTaggerOperations, @unchecked Sendable {
    
    private let logTagCollection: LogTagCollection
    private let queue: DispatchQueue
    
    override init() {
        queue = DispatchQueue(label: "com.swift.logtag.\(NSUUID().uuidString)")
        logTagCollection = LogTagCollection()
        super.init()
    }
    
    //MARK: Log API's
    
    public func addTag(_ logTag: any LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            let result = self.logTagCollection.addTag(logTag)
            completion?(result)
        }
    }
    
    public func removeTag(_ logTag: any LogTag, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            let result = self.logTagCollection.removeTag(logTag.identifier)
            completion?(result)
        }
    }
    
    public func  removeTag(identifier: String, completion: (@Sendable(Bool) -> Void)? = nil) {
        queue.async {
            let result = self.logTagCollection.removeTag(identifier)
            completion?(result)
        }
    }
    
    public func logTags(logType: LogType, completion: @escaping (@Sendable([any LogTag]) -> Void)) {
        queue.async {
            completion(self.logTagCollection.logTags.filter { $0.logType == .undefined || $0.logType == logType })
        }
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

