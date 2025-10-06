//
//  SwiftLogSmith - Swift Logging Library
//
//  SPDX-FileCopyrightText: 2025 Eeshan Jamal
//
//  SPDX-License-Identifier: MIT
//

import Testing
import Foundation
@testable import SwiftLogSmith

@Test func logSmithLog() async throws {
    LogSmith.log("Sample Log")
    LogSmith.logC("Sample Log Critical")
    LogSmith.logD("Sample Log Debug")
    LogSmith.logE("Sample Log Error")
    LogSmith.logF("Sample Log Fault")
    LogSmith.logI("Sample Log Info")
    LogSmith.logN("Sample Log Notice")
    LogSmith.logT("Sample Log Trace")
    LogSmith.logW("Sample Log Warning")
}

    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
}
