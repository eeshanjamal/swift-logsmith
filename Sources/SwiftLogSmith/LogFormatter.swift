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
        return Builder()
            .addTagsPart(filter: { $0.identifier == LogTagIdentifiers.date })
            .addSeparator()
            .addTagsPart(filter: { $0.tagType == .external }, format: {"\($0.identifier): \($0.value)"}, separator: ", ", prefix: "[", suffix: "]")
            .addSeparator()
            .addTagsPart(filter: { logTypeValues.contains($0.identifier) }, prefix: "[", suffix: "]")
            .addSeparator()
            .addMessagePart()
            .addSeparator()
            .addMetadataPart()
            .build()
    }

    private init(parts: [any LogPart]) {
        self.parts = parts
    }

    public func format(message: LogMessage) -> String {
        let state = FormattingState(tags: message.tags)
        return parts.map { $0.format(message: message, state: state) }.joined()
    }
    
    // MARK: - Nested Builder Class
    
    @objcMembers
    final class Builder: NSObject, @unchecked Sendable {
        
        private var parts: [any LogPart] = []
        
        @discardableResult
        public func addMessagePart(format: @escaping (String) -> String = { $0 }) -> Self {
            self.parts.append(MessagePart(format: format))
            return self
        }
        
        @discardableResult
        public func addMetadataPart(format: @escaping ([String: String]) -> String = { "\($0)" }) -> Self {
            self.parts.append(MetadataPart(format: format))
            return self
        }

        @discardableResult
        public func addSeparator(with separator: String = " ") -> Self {
            self.parts.append(SeparatorPart(separator: separator))
            return self
        }

        @discardableResult
        public func addTagsPart(
            filter: @escaping (Tag) -> Bool = { _ in true },
            format: @escaping (Tag) -> String = { $0.value },
            separator: String = " ",
            prefix: String = "",
            suffix: String = ""
        ) -> Self {
            let tagPart = LogTagPart(
                filter: filter,
                format: format,
                separator: separator,
                prefix: prefix,
                suffix: suffix
            )
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
    
    func format(message: LogMessage, state: FormattingState) -> String
}

@objcMembers
private final class MessagePart: NSObject, LogPart, @unchecked Sendable {
    
    private let format: (String) -> String
    
    init(format: @escaping (String) -> String = { $0 }) {
        self.format = format
    }
    
    func format(message: LogMessage, state: FormattingState) -> String {
        return format(message.message)
    }
}

@objcMembers
private final class MetadataPart: NSObject, LogPart, @unchecked Sendable {
    
    private let format: ([String: String]) -> String
    
    init(format: @escaping ([String : String]) -> String = { "\($0)" }) {
        self.format = format
    }
    
    func format(message: LogMessage, state: FormattingState) -> String {
        if !message.metadata.isEmpty {
            return format(message.metadata)
        }
        return ""
    }
}

@objcMembers
private final class SeparatorPart: NSObject, LogPart, @unchecked Sendable {
    
    private let separator: String

    public init(separator: String = " ") {
        self.separator = separator
    }

    func format(message: LogMessage, state: FormattingState) -> String {
        return separator
    }
}

@objcMembers
private final class LogTagPart: NSObject, LogPart, @unchecked Sendable {
    
    private let filter: (Tag) -> Bool
    private let format: (Tag) -> String
    private let separator: String
    private let prefix: String
    private let suffix: String

    init(filter: @escaping (Tag) -> Bool = { _ in true },
         format: @escaping (Tag) -> String = { $0.value },
         separator: String = " ",
         prefix: String = "",
         suffix: String = ""
    ) {
        self.filter = filter
        self.format = format
        self.separator = separator
        self.prefix = prefix
        self.suffix = suffix
    }

    func format(message: LogMessage, state: FormattingState) -> String {
        
        let filteredTags = state.unformattedTags.filter(filter)
        guard !filteredTags.isEmpty else { return "" }
        
        state.unformattedTags.removeAll(where: { originalTag in
            filteredTags.contains(where: { $0 === originalTag })
        })

        let content = filteredTags.map(format).joined(separator: separator)
        return "\(prefix)\(content)\(suffix)"
    }
}
