//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation
import SwiftLogSmith

/// A thread-safe spy ``ILogger`` that records every message it receives.
///
/// Modelled on the spy in `LogSmithTests`; the `NSLock` is required because `LogManager` delivers on its own
/// serial queue rather than the calling thread.
final class BackendMockLogger: ILogger, @unchecked Sendable {

    var tagger: LogTagger?
    var formatter: LogFormatter

    private let lock = NSLock()
    private var logMessages: [LogMessage] = []
    private var onLog: (@Sendable (LogMessage) -> Void)?

    init(tagger: LogTagger? = nil, formatter: LogFormatter = LogFormatter.default) {
        self.tagger = tagger
        self.formatter = formatter
    }

    /// Installs a callback invoked for every message received.
    ///
    /// Tests use this to drive `XCTestExpectation` directly rather than polling ``logCallCount``, which would
    /// otherwise leave background threads spinning past the end of the test.
    func setOnLog(_ handler: (@Sendable (LogMessage) -> Void)?) {
        lock.lock()
        defer { lock.unlock() }
        onLog = handler
    }

    var logCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return logMessages.count
    }

    var messages: [LogMessage] {
        lock.lock()
        defer { lock.unlock() }
        return logMessages
    }

    var lastLogMessage: LogMessage? {
        lock.lock()
        defer { lock.unlock() }
        return logMessages.last
    }

    /// The formatted output of the last recorded message, using this logger's own formatter.
    var lastFormattedMessage: String? {
        guard let message = lastLogMessage else { return nil }
        return formatter.format(message: message)
    }

    func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)?) {
        lock.lock()
        logMessages.append(message)
        let handler = onLog
        lock.unlock()
        handler?(message)
        completion?(true)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        logMessages.removeAll()
    }
}
