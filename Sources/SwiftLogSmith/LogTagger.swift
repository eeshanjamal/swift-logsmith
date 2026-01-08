//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objc protocol LogTag: Sendable {
    
    var identifier: String {get}
    var logType: LogType {get}
    
    func visit(logTagVisitor: any LogTagVisitor)
}

@objcMembers
final class LogTagIdentifiers: NSObject, @unchecked Sendable {
    static let date = "Date"
}

@objc public enum InternalTagType: Int {
    
    case file
    case function
    case line
    case threadName
    
    var stringValue: String {
        switch self {
        case .file:
            return "file"
        case .function:
            return "function"
        case .line:
            return "line"
        case .threadName:
            return "threadName"
        }
    }
}

@objc protocol LogTagVisitor: Sendable {
    
    func visit(internalTag: InternalTag)
    func visit(externalTag: ExternalTag)
}

@objcMembers
final class ExternalTag: NSObject, LogTag, @unchecked Sendable {
    
    let identifier: String
    let logType: LogType
    var value: String {
        return valueProvider()
    }
    
    private let valueProvider: () -> String
    
    init(identifier: String, value: String, logType: LogType = .undefined){
        self.identifier = identifier
        self.logType = logType
        self.valueProvider = {value}
    }
    
    init(identifier: String, valueProvider: @escaping() -> String, logType: LogType = .undefined){
        self.identifier = identifier
        self.logType = logType
        self.valueProvider = valueProvider
    }
    
    func visit(logTagVisitor: any LogTagVisitor) {
        logTagVisitor.visit(externalTag: self)
    }
}

@objcMembers
final class InternalTag: NSObject, LogTag, @unchecked Sendable {
    
    let identifier: String
    let logType: LogType
    let internalTagType: InternalTagType
    
    init(internalTagType: InternalTagType, logType: LogType = .undefined) {
        self.identifier = internalTagType.stringValue
        self.logType = logType
        self.internalTagType = internalTagType
    }
    
    func visit(logTagVisitor: any LogTagVisitor) {
        logTagVisitor.visit(internalTag: self)
    }
}

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

