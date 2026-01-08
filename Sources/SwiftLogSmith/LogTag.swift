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


