
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
            LogTagPart(filter: { $0.tagType == .external }, prefix: "<", suffix: ">", separator: " | "),
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
    
    func format(message: LogMessage) -> String {
        return message.message
    }
}

@objcMembers
final class MetadataPart: NSObject, LogPart, @unchecked Sendable {
    
    func format(message: LogMessage) -> String {
        if !message.metadata.isEmpty {
            return "metadata: \(message.metadata)"
        }
        return ""
    }
}

@objcMembers
final class SeparatorPart: NSObject, LogPart, @unchecked Sendable {
    
    private let separator: String

    @objc public init(separator: String = " ") {
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
    private let enclosureStart: String
    private let enclosureEnd: String
    private let separator: String
    private let prefix: String
    private let suffix: String

    convenience init(
        filter: @escaping (Tag) -> Bool = { _ in true },
        prefix: String = "",
        suffix: String = "",
        enclosureStart: String = "",
        enclosureEnd: String = "",
        separator: String = " "
    ) {
        self.init(enclosureStart: enclosureStart, enclosureEnd: enclosureEnd, separator: separator, prefix: prefix, suffix: suffix, filter: filter)
    }
    
    init(
        enclosureStart: String,
        enclosureEnd: String,
        separator: String,
        prefix: String,
        suffix: String,
        filter: @escaping (Tag) -> Bool
    ) {
        self.filter = filter
        self.enclosureStart = enclosureStart
        self.enclosureEnd = enclosureEnd
        self.separator = separator
        self.prefix = prefix
        self.suffix = suffix
    }

    func format(message: LogMessage) -> String {
        
        let filteredTags = message.tags.filter(filter)
        
        guard !filteredTags.isEmpty else { return "" }
        
        let content = filteredTags.map { "\(enclosureStart)\($0.value)\(enclosureEnd)" }.joined(separator: separator)
        
        return "\(prefix)\(content)\(suffix)"
    }
}
