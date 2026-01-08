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
    
    //Date tag
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-mm-dd HH:mm:ss.SSS"
    LogSmith.addTag(ExternalTag(identifier: LogTagIdentifiers.date, valueProvider: { dateFormatter.string(from: Date()) }))
    
    //System tags
    LogSmith.addTag(InternalTag(internalTagType: .file))
    LogSmith.addTag(InternalTag(internalTagType: .function))
    LogSmith.addTag(InternalTag(internalTagType: .line))
    
    LogSmith.log("Sample Log")
    LogSmith.logC("Sample Log Critical", metadata: ["error": "404", "description": "Page not found"])
    LogSmith.logD("Sample Log Debug")
    LogSmith.logE("Sample Log Error")
    LogSmith.logF("Sample Log Fault")
    LogSmith.logI("Sample Log Info")
    LogSmith.logN("Sample Log Notice")
    LogSmith.logT("Sample Log Trace")
    LogSmith.logW("Sample Log Warning")

    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
}
