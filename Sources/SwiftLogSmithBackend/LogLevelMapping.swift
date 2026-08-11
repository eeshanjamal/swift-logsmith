//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

public import Logging
public import SwiftLogSmith

extension LogType {

    /// Creates the `LogType` corresponding to a `swift-log` severity.
    ///
    /// The mapping is one-to-one and lossless — every `Logger.Level` has an exact `LogType`
    /// counterpart, so no severity information is discarded when a `swift-log` message enters SwiftLogSmith:
    ///
    /// | `Logger.Level` | `LogType` |
    /// | --- | --- |
    /// | `.trace` | `LogType.trace` |
    /// | `.debug` | `LogType.debug` |
    /// | `.info` | `LogType.info` |
    /// | `.notice` | `LogType.notice` |
    /// | `.warning` | `LogType.warning` |
    /// | `.error` | `LogType.error` |
    /// | `.critical` | `LogType.critical` |
    ///
    /// `LogType.none`, `LogType.undefined` and `LogType.fault`
    /// have no `swift-log` equivalent and are never produced by this initialiser.
    ///
    /// - Parameter level: The `swift-log` severity to translate.
    public init(swiftLogLevel level: Logger.Level) {
        switch level {
        case .trace:
            self = .trace
        case .debug:
            self = .debug
        case .info:
            self = .info
        case .notice:
            self = .notice
        case .warning:
            self = .warning
        case .error:
            self = .error
        case .critical:
            self = .critical
        }
    }
}
