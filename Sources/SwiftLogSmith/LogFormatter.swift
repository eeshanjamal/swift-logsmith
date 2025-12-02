
import Foundation

@objc protocol LogFormatter: Sendable {
    func format(message: LogMessage) -> String
}

@objcMembers
final class DefaultLogFormatter: NSObject, LogFormatter, @unchecked Sendable {
    
    public var parts: [any LogPart]
    private static let logTypeValues = LogType.allCases.map{$0.stringValue}

    public init(parts: [any LogPart]) {
        self.parts = parts
    }

    public convenience override init() {
        self.init(parts: [
            LogTagPart(filter: { $0.identifier == LogTagIdentifiers.date }),
            SeparatorPart(),
            LogTagPart(filter: { $0.tagType == .external }, format: {"\($0.identifier): \($0.value)"},separator: ", ", prefix: "[", suffix: "]"),
            SeparatorPart(),
            LogTagPart(filter: { DefaultLogFormatter.logTypeValues.contains($0.identifier) }, prefix: "[", suffix: "]"),
            SeparatorPart(),
            MessagePart(),
            SeparatorPart(),
            MetadataPart()
        ])
    }

    public func format(message: LogMessage) -> String {
        return parts.map { $0.format(message: message) }.joined()
    }
}


@objc protocol LogPart: Sendable {
    
    func format(message: LogMessage) -> String
}

@objcMembers
final class MessagePart: NSObject, LogPart, @unchecked Sendable {
    
    private let format: (String) -> String
    
    init(format: @escaping (String) -> String = { message in message }) {
        self.format = format
    }
    
    func format(message: LogMessage) -> String {
        return format(message.message)
    }
}

@objcMembers
final class MetadataPart: NSObject, LogPart, @unchecked Sendable {
    
    private let format: ([String: String]) -> String
    
    init(format: @escaping ([String : String]) -> String = { metadata in "\(metadata)" }) {
        self.format = format
    }
    
    func format(message: LogMessage) -> String {
        if !message.metadata.isEmpty {
            return format(message.metadata)
        }
        return ""
    }
}

@objcMembers
final class SeparatorPart: NSObject, LogPart, @unchecked Sendable {
    
    private let separator: String

    public init(separator: String = " ") {
        self.separator = separator
    }

    func format(message: LogMessage) -> String {
        return separator
    }
}

@objcMembers
final class LogTagPart: NSObject, LogPart, @unchecked Sendable {
    
    public enum TagSource: Int {
        case prefix, postfix
    }
    
    private let filter: (Tag) -> Bool
    private let format: (Tag) -> String
    private let separator: String
    private let prefix: String
    private let suffix: String

    init(filter: @escaping (Tag) -> Bool = { _ in true },
         format: @escaping (Tag) -> String = { tag in tag.value },
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

    func format(message: LogMessage) -> String {
        
        let filteredTags = message.tags.filter(filter)
        guard !filteredTags.isEmpty else { return "" }
        
        let content = message.tags.filter(filter).map(format).joined(separator: separator)
        return "\(prefix)\(content)\(suffix)"
    }
}
