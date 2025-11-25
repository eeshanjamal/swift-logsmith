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

@objc public enum SystemTagType: Int {
    
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
    
    func visit(logInternalTag: LogInternalTag)
    func visit(logExternalTag: LogExternalTag)
}

@objcMembers
final class LogInternalTag: NSObject, LogTag, @unchecked Sendable {
    
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
        logTagVisitor.visit(logInternalTag: self)
    }
}

@objcMembers
final class LogExternalTag: NSObject, LogTag, @unchecked Sendable {
    
    let identifier: String
    let logType: LogType
    let systemTagType: SystemTagType
    
    init(systemTagType: SystemTagType, logType: LogType = .undefined) {
        self.identifier = systemTagType.stringValue
        self.logType = logType
        self.systemTagType = systemTagType
    }
    
    func visit(logTagVisitor: any LogTagVisitor) {
        logTagVisitor.visit(logExternalTag: self)
    }
}


