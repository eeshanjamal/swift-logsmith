//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2026 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Foundation

/// A `DateFormatter` that can be shared across threads.
///
/// Creating a `DateFormatter` costs far more than formatting with an existing one, so the library keeps a few shared instances.
/// `DateFormatter` isn't `Sendable`, so each instance serialises access with a lock, like the other `NSLock`-guarded stores in the library.
///
/// Every instance uses the `en_US_POSIX` locale, so its pattern is applied literally whatever the device's calendar, numbering system or 12/24-hour setting.
internal final class LockedDateFormatter: @unchecked Sendable {

    private let formatter: DateFormatter
    private let lock = NSLock()

    /// Creates a formatter for a fixed pattern and time zone.
    /// - Parameters:
    ///   - format: The `DateFormatter` pattern.
    ///   - timeZone: The time zone the date is written in.
    init(format: String, timeZone: TimeZone) {
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
    }

    /// Formats a date with the pattern and time zone given at creation.
    func string(from date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: date)
    }
}
