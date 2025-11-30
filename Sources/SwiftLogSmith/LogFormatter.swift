
import Foundation

@objc protocol LogFormatter: Sendable {
    func format(message: LogMessage) -> String
}

@objcMembers
final class DefaultLogFormatter: NSObject, LogFormatter, @unchecked Sendable {
    
    public var parts: [any LogPart]

    public init(parts: [any LogPart]) {
        self.parts = parts
    }

    public convenience override init() {
        self.init(parts: [
            LogTagPart(sources: [.prefix], filter: {$0.key == LogTagIdentifiers.date}),
            SeparatorPart(),
            LogTagPart(sources: [.prefix], filter: { tag in
                tag.key == SystemTagType.file.stringValue || tag.key == SystemTagType.function.stringValue || tag.key == SystemTagType.line.stringValue
            }, prefix: "<", suffix: ">", separator: " | "),
            SeparatorPart(),
            LogTagPart(sources: [.prefix], filter: {LogType.allCases.map{$0.stringValue}.contains($0.key)}, prefix: "[", suffix: "]"),
            SeparatorPart(),
            MessagePart(),
            SeparatorPart(),
            MetadataPart(),
            SeparatorPart(),
            LogTagPart(sources: [.postfix])
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
    
    private let sources: [TagSource]
    private let filter: (Tag) -> Bool
    private let enclosureStart: String
    private let enclosureEnd: String
    private let separator: String
    private let prefix: String
    private let suffix: String

    convenience init(
        sources: [TagSource] = [.prefix, .postfix],
        filter: @escaping (Tag) -> Bool = { _ in true },
        prefix: String = "",
        suffix: String = "",
        enclosureStart: String = "",
        enclosureEnd: String = "",
        separator: String = " "
    ) {
        self.init(sources: sources, enclosureStart: enclosureStart, enclosureEnd: enclosureEnd, separator: separator, prefix: prefix, suffix: suffix, filter: filter)
    }
    
    init(
        sources: [TagSource] = [.prefix, .postfix],
        enclosureStart: String,
        enclosureEnd: String,
        separator: String,
        prefix: String,
        suffix: String,
        filter: @escaping (Tag) -> Bool
    ) {
        self.sources = sources
        self.filter = filter
        self.enclosureStart = enclosureStart
        self.enclosureEnd = enclosureEnd
        self.separator = separator
        self.prefix = prefix
        self.suffix = suffix
    }

    func format(message: LogMessage) -> String {
        var tagsToConsider: [Tag] = []
        if sources.contains(.prefix) {
            tagsToConsider.append(contentsOf: message.prefixTags)
        }
        if sources.contains(.postfix) {
            tagsToConsider.append(contentsOf: message.postfixTags)
        }
        
        let filteredTags = tagsToConsider.filter(filter)
        
        guard !filteredTags.isEmpty else { return "" }
        
        let content = filteredTags.map { "\(enclosureStart)\($0.value)\(enclosureEnd)" }.joined(separator: separator)
        
        return "\(prefix)\(content)\(suffix)"
    }
}
