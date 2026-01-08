//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

@objcMembers
final class LogFormatter: NSObject, @unchecked Sendable {
    
    private let parts: [any LogPart]
    private static let logTypeValues = LogType.allCases.map { $0.stringValue }
    
    public static var `default`: LogFormatter {
            Builder()
            .addTagsPart(suffix: " ", filter: { $0.identifier == LogTagIdentifiers.date })
            .addTagsPart(prefix: "[", format: {"\($0.identifier): \($0.value)"}, separator: ", ", suffix: "] ", filter: { $0.tagType == .internal })
            .addTagsPart(prefix: "[", suffix: "] ", filter: { logTypeValues.contains($0.identifier) })
            .addMessagePart()
            .addMetadataPart(prefix: " ")
            .build()
    }

    private init(parts: [any LogPart]) {
        self.parts = parts
    }

    public func format(message: LogMessage) -> String {
        let state = FormattingState(tags: message.tags)
        return parts.map { $0.format(logMessage: message, formattingState: state) }.joined()
    }
    
    // MARK: - Nested Builder Class
    
    @objcMembers
    final class Builder: NSObject, @unchecked Sendable {
        
        private var parts: [any LogPart] = []
        
        @discardableResult
        public func addMessagePart(prefix: String = "", format: @escaping (String) -> String = { $0 }, suffix: String = "") -> Self {
            self.parts.append(MessagePart(prefix: prefix, format: format, suffix: suffix))
            return self
        }
        
        @discardableResult
        public func addMetadataPart(prefix: String = "", format: @escaping ([String: String]) -> String = { "\($0)" }, suffix: String = "") -> Self {
            self.parts.append(MetadataPart(prefix: prefix, format: format, suffix: suffix))
            return self
        }

        @discardableResult
        public func addTagsPart(prefix: String = "", format: @escaping (Tag) -> String = { $0.value }, separator: String = " ",
                                suffix: String = "", filter: @escaping (Tag) -> Bool = { _ in true }) -> Self {
            let tagPart = LogTagPart(prefix: prefix, format: format, separator: separator, suffix: suffix, filter: filter)
            self.parts.append(tagPart)
            return self
        }

        public func build() -> LogFormatter {
            return LogFormatter(parts: self.parts)
        }
    }
}

@objcMembers
internal final class FormattingState: NSObject, @unchecked Sendable {
    var unformattedTags: [Tag]
      
    init(tags: [Tag]) {
      self.unformattedTags = tags
    }
}

@objc internal protocol LogPart: Sendable {
    
    func format(logMessage: LogMessage, formattingState: FormattingState) -> String
}

@objcMembers
private class BaseLogPart: NSObject, @unchecked Sendable {
    
    let prefix: String
    let suffix: String
    
    init(prefix: String, suffix: String) {
        self.prefix = prefix
        self.suffix = suffix
    }
}

@objcMembers
private final class MessagePart: BaseLogPart, LogPart, @unchecked Sendable {
    
    private let format: (String) -> String
    
    init(prefix: String = "", format: @escaping (String) -> String = { $0 }, suffix: String = "") {
        self.format = format
        super.init(prefix: prefix, suffix: suffix)
    }
    
    func format(logMessage: LogMessage, formattingState: FormattingState) -> String {
        guard !logMessage.message.isEmpty else { return "" }
        let content = format(logMessage.message)
        return "\(prefix)\(content)\(suffix)"
    }
}

@objcMembers
private final class MetadataPart: BaseLogPart, LogPart, @unchecked Sendable {
    
    private let format: ([String: String]) -> String
    
    init(prefix: String = "", format: @escaping ([String : String]) -> String = { "\($0)" }, suffix: String = "") {
        self.format = format
        super.init(prefix: prefix, suffix: suffix)
    }
    
    func format(logMessage: LogMessage, formattingState: FormattingState) -> String {
        guard !logMessage.metadata.isEmpty else { return "" }
        let content = format(logMessage.metadata)
        return "\(prefix)\(content)\(suffix)"
    }
}

@objcMembers
private final class LogTagPart: BaseLogPart, LogPart, @unchecked Sendable {
    
    private let filter: (Tag) -> Bool
    private let format: (Tag) -> String
    private let separator: String

    init(prefix: String = "", format: @escaping (Tag) -> String = { $0.value }, separator: String = " ", suffix: String = "", filter: @escaping (Tag) -> Bool = { _ in true }) {
        self.format = format
        self.filter = filter
        self.separator = separator
        super.init(prefix: prefix, suffix: suffix)
    }

    func format(logMessage: LogMessage, formattingState: FormattingState) -> String {
        let tagsToProcess = formattingState.unformattedTags.filter(filter)
        guard !tagsToProcess.isEmpty else { return "" }
        
        formattingState.unformattedTags.removeAll(where: { originalTag in
            tagsToProcess.contains(where: { $0 === originalTag })
        })

        let content = tagsToProcess.map(format).joined(separator: separator)
        return "\(prefix)\(content)\(suffix)"
    }
}
