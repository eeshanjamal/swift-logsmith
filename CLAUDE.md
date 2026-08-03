# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

SwiftLogSmith is a Swift Package Manager library providing a lightweight, thread-safe, zero-config logging facade for Apple platforms (macOS 11+, iOS 14+, tvOS 14+, watchOS 7+, visionOS 1+), with Objective-C interop and Swift 6 strict concurrency support. Single library product/target: `SwiftLogSmith`.

## Commands

Build:
```
swift build
```

Run all tests:
```
swift test
```

Run a single test class or method (XCTest; `--filter` takes `Target.TestClass[/testMethod]`):
```
swift test --filter SwiftLogSmithTests.LogManagerTests
swift test --filter SwiftLogSmithTests.LogManagerTests/testAddLogger_WithNewLogger_ShouldSucceed
```

Preview the DocC documentation locally (use this first, before regenerating the static site):
```
swift package --disable-sandbox preview-documentation --target SwiftLogSmith
```

Regenerate the DocC static site checked into `docs/` (published to GitHub Pages via the `swift-docc-plugin` dependency):
```
swift package --allow-writing-to-directory ./docs generate-documentation --target SwiftLogSmith --disable-indexing --transform-for-static-hosting --hosting-base-path swift-logsmith --output-path ./docs
```

## Package manifests

The package is declared across **four manifest files**, using SwiftPM's version-specific manifest mechanism: `Package.swift` (default, tools-version 6.3) plus `Package@swift-6.0.swift`, `Package@swift-6.1.swift`, `Package@swift-6.2.swift`. SwiftPM automatically picks the highest-versioned manifest that is `<=` the active toolchain — there's no manual selection step. Each pins a progressively smaller set of `swiftSettings` upcoming-feature flags for older toolchains (e.g. `.strictMemorySafety()` and `ImmutableWeakCaptures`/`InferIsolatedConformances`/`NonisolatedNonsendingByDefault` only appear on the 6.2/6.3 manifests). **When changing dependencies, platforms, or targets, keep all four files in sync** — only the `swiftSettings` upcoming-feature list is expected to differ between them.

## Architecture

Logging flows through four layers:

```
LogSmith (public @objc singleton facade — LogSmith.swift)
  -> LogManager (Core/LogManager.swift — filtering + fan-out orchestrator)
       -> LoggerItem wrapper (per-logger min LogLevel/LogType override)
            -> ILogger conformer (Core/ILogger.swift is the contract)
                 - OSLogger (Destinations/OSLogger.swift) — wraps os.Logger, the shipped default
                 - FileLogger (Destinations/FileLogger.swift) — delegates disk I/O to FileLoggerManager
                      (rolling/archiving/purging via ZIPFoundation, pluggable RollingFrequency strategies)
```

- **Entry point**: `LogSmith` (`LogSmith.swift`) is a `@objcMembers` singleton (`LogSmith.shared`) wrapping one internal `LogManager`. Its `log`/`logT`/`logD`/`logN`/`logI`/`logW`/`logE`/`logC`/`logF` calls all dispatch asynchronously onto a private serial queue — there's intentionally no `async`/`await` in the public API, to preserve Objective-C interop.
- **Two-tier severity model**: fine-grained `LogType` (9 cases, each with a single-letter `symbolicValue` tag like `"E"`/`"D"`) rolls up into a coarser `LogLevel` (5 cases) via `LogType.logLevel`. Both a manager-global and a per-logger threshold — of *both* enums — gate whether a message reaches a given `ILogger`; see the filtering logic in `LogManager.log(message:logType:metadata:...)`.
- **Destinations are pluggable**: anything conforming to `ILogger` (`tagger`, `formatter`, `log(message:completion:)`) can be registered via `LogSmith.addLogger`/`LogManager.addLogger`, alongside or instead of the built-in `OSLogger`/`FileLogger`.
- **Tags** (`Core/LogTagger.swift`) are cross-cutting context attached to messages, split into auto-captured `InternalTag` (file/function/line/thread) and user-defined `ExternalTag` (static value or a dynamic `valueProvider` closure). Both a manager-level and a per-logger `LogTagger` can hold tags; they're resolved into flat `Tag` values on the outgoing `LogMessage` through the `LogTagVisitor` visitor-pattern protocol.
- **Formatting** (`Core/LogFormatter.swift`) is a declarative pipeline built with `LogFormatter.Builder` (`addMessagePart`/`addMetadataPart`/`addTagsPart`), letting each `ILogger` own an independent output layout while reusing the same `LogMessage`. `FormattingState` ensures a given tag identifier is consumed by at most one part.
- **Concurrency predates full actor adoption**: thread safety comes from a private serial `DispatchQueue` per `LogSmith`/`LogManager`/`LogTagger`/`FileLoggerManager`, plus `NSLock`-guarded backing stores (e.g. `LogTagCollection`), with async completions aggregated via `DispatchGroup`. Follow this existing lock/queue convention rather than introducing actors, to stay consistent with the rest of the codebase.
- **Objective-C interop is a first-class constraint**: nearly all public types are `@objc`/`@objcMembers` and `final class ... : NSObject`. New public API should preserve this — e.g. enums need to stay `@objc`-compatible (no associated values), and protocols with generics or associated types can't be exposed the same way.

## Source layout

- `Sources/SwiftLogSmith/LogSmith.swift` — public facade + `LogType`/`LogLevel` enums
- `Sources/SwiftLogSmith/Core/` — `ILogger` (protocol), `LogManager` (orchestrator), `LogMessage`/`Tag` (data model), `LogTagger` (tagging), `LogFormatter` (formatting)
- `Sources/SwiftLogSmith/Destinations/` — `OSLogger`, `FileLogger` (+ `FileLoggerManager`, `LogFile`, `RollingFrequency` strategies)
- `Sources/SwiftLogSmith/Extensions/` — small `DispatchQueue` helper
- `Tests/SwiftLogSmithTests/` — one XCTest file per major type; test method names follow `test<Action>_<Condition>_Should<Outcome>()`
