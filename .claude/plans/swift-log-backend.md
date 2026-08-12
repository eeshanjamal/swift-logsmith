# swift-log backend — design record

Durable record for the `SwiftLogSmithBackend` module. Written before implementation; the
"Deviations found during execution" section is filled in as work proceeds.

**Goal:** make SwiftLogSmith usable as a backend for `apple/swift-log`, so that after a one-line
`LoggingSystem.bootstrap`, any `Logger(label:)` in the process — including from third-party
dependencies — routes into SwiftLogSmith's `LogManager` and lands in the same destinations,
filters and tags as first-party `LogSmith` calls.

Direction is one-way by design: swift-log → LogSmith.

---

## Decisions and rationale

Recorded so they are not silently re-litigated later.

### Confirmed

| Decision | Rationale |
|---|---|
| **Direction: swift-log → LogSmith only** | This is what captures logs from libraries you depend on. The reverse (`SwiftLogDestination: ILogger`, forwarding `LogSmith.logE` out into a swift-log `Logger`) was considered and dropped — see Deferred. |
| **Separate product/target, not folded into the core** | `LogHandler` conformers must be structs trafficking in `Logger.Level`/`Message`/`Metadata`, none of which are ObjC-representable, so the bridge cannot live in the `@objc`-uniform core. Keeping it separate also means existing consumers pull in zero new dependencies. Matches CocoaLumberjack's `CocoaLumberjackSwiftLogBackend`. |
| **Bridge requires Swift 6.2+; core keeps building on 6.0** | swift-log 1.11.0 (first version with the modern `log(event:)` API) declares `swift-tools-version:6.2`, so older toolchains cannot resolve it at all. |
| **Preserve swift-log's structured metadata** | `Logger.Metadata` is a tree (`.dictionary`/`.array`/`.stringConvertible`); flattening it to `[String: String]` and discarding the original loses information that downstream destinations may want. |
| **Do not weaken the existing queue discipline** | No synchronous readers of queue-guarded state, and no second path into `LogManager` that bypasses `LogSmith`'s queue hop. Rules out both public min-level getters and exposing the default manager — see below. |

### Assumed defaults

| Decision | Rationale |
|---|---|
| **`LogPayload` marker protocol** | Rather than de-`final`ing `LogMessage` or changing `ILogger` to take `any ILogMessage`. See "Why a payload protocol". |
| **Populate both payload and flat metadata** | Structured data rides in the payload; a flattened rendering also lands in `LogMessage.metadata` so `LogFormatter.default` renders bridged messages with zero configuration. |
| **Rich core metadata deferred** | See Deferred. |

### Why a payload protocol rather than a subclass

CocoaLumberjack attaches structure by subclassing `DDLogMessage` (→ `SwiftLogMessage`) and
exposing it via downcast. That route costs three things here:

- `LogMessage` (`Core/LogMessage.swift`) is `final`; dropping that forces `@unchecked Sendable`,
  because a non-final class cannot get *checked* `Sendable` conformance.
- `@unchecked` is **inherited by subclasses**, so the guarantee stops being compiler-verified for
  everything downstream.
- Its `init` is `internal` and would have to be promoted.

None of it is necessary, because **the bridge never constructs a `LogMessage`** — `LogManager`
does. Threading an opaque payload through `LogManager.log` keeps `LogMessage` `final` and
checked-Sendable, keeps its init internal, and breaks no existing `ILogger` or `LogFormatter`
signature.

### Why the default `LogManager` stays private

Exposing it would create a genuine ordering hazard. `LogSmith`'s API crosses **two** queues
(`LogSmith.queue` → `LogManager.queue`); direct manager access crosses **one**. Mixing the paths
loses relative ordering even for sequential calls on a single thread:

```swift
LogSmith.setMinimumLogLevel(.error)   // two hops
manager.log(...)                       // one hop — can land first
```

Instead the bridge routes through a single new `LogSmith` static, so every operation stays behind
the same hop. A user-owned `LogManager` remains available as opt-in isolation.

### Why no `minimumLogLevel` / `minimumLogType` getters

They are mutated only inside `queue.async`, and because `LogManager` is `@unchecked Sendable` a
synchronous getter would be an **unflagged** data race. A safe version would have to be
completion-based (like `LogTagger.logTags(logType:completion:)`) or move storage behind an
`NSLock` (like `LogTagCollection`). Not needed — the handler defaults its `logLevel` to `.trace`
and lets LogSmith's own filters govern.

---

## Level mapping

Clean 1:1, no collapsing. CocoaLumberjack must merge `info`+`notice` and `error`+`critical`
because `DDLogFlag` has only five flags; `LogType`'s nine cases don't force that.

| `Logger.Level` | `LogType` |
|---|---|
| `.trace` | `.trace` |
| `.debug` | `.debug` |
| `.info` | `.info` |
| `.notice` | `.notice` |
| `.warning` | `.warning` |
| `.error` | `.error` |
| `.critical` | `.critical` |

### Known sharp edge: LogType ordering inversion

`LogType`'s raw values order `notice(1) < info(2) < debug(3) < trace(4)` — the **reverse** of
swift-log's `trace < debug < info < notice`. Since `LogManager` filters with
`logType.rawValue >= minimum`, calling `setMinimumLogType(.info)` silently drops swift-log
`.notice` messages.

Mitigation: the handler defaults `logLevel` to `.trace` so swift-log's own (correctly ordered)
comparison does the gating. **Filtering for bridged loggers belongs on `logger.logLevel` or
`bootstrapWithLogSmith(defaultLogLevel:)`**, with LogSmith's own minimums left at their permissive
defaults. Not fixing the ordering itself — that would be a breaking change.

---

## Implementation checklist

### Core (`Sources/SwiftLogSmith/`) — additive, non-breaking

- [x] `Core/LogMessage.swift`: add `@objc public protocol LogPayload: Sendable {}`
- [x] `Core/LogMessage.swift`: add `public let payload: (any LogPayload)?`, extend internal init
- [x] `Core/LogManager.swift`: replace `fileId`/`function` with `String`, add `payload:` param
- [x] `Core/LogManager.swift`: refactor `extractTags` / `LogTagsExtractor.extract` to `String`
- [x] `LogSmith.swift`: keep `StaticString` on all nine `log*` statics
- [x] `LogSmith.swift`: add one forwarding static with `payload` + `String` source location
- [x] Confirm `LogMessage` still has **checked** `Sendable` (no `@unchecked` crept in)

### Manifests

- [x] `Package.swift`: swift-log dep, product, target, test target
- [x] `Package@swift-6.2.swift`: same
- [x] `Package@swift-6.0.swift` and `Package@swift-6.1.swift`: **unchanged**
- [x] `Package.resolved` regenerated by SwiftPM, not hand-edited

### Backend (`Sources/SwiftLogSmithBackend/`)

- [x] `LogSmithLogHandler.swift` — struct, implements `log(event:)`
- [x] Shared mode (default) → routes via the new `LogSmith` static
- [x] Isolated mode (opt-in) → user-owned `LogManager`
- [x] Metadata precedence: handler `metadata` < `metadataProvider` < per-call `event.metadata`
- [x] `subscript(metadataKey:)`, `metadata`, `logLevel`, `metadataProvider`
- [x] `SwiftLogPayload.swift` — final, checked Sendable, holds `label`/`source`/`LogEvent`
- [x] `LogLevelMapping.swift`
- [x] `Bootstrap.swift` — `bootstrapWithLogSmith(...)`
- [x] `public import Logging` (required: `InternalImportsByDefault` is on)

### Tests (`Tests/SwiftLogSmithBackendTests/`)

- [x] Level mapping, all seven cases
- [x] Metadata precedence
- [x] Payload round-trip via downcast
- [x] Flattened metadata renders through `LogFormatter.default`
- [x] `file`/`function`/`line` reach `InternalTag`s and point at the call site
- [x] `logLevel` filtering
- [x] Concurrency: interleave `LogSmith.log*` and bridged `Logger(label:)` from several threads
- [x] No `LoggingSystem.bootstrap` in tests (traps on second call) — use `Logger(label:factory:)`

### Docs

- [x] README: Key Features bullet, usage section, mermaid node, installation snippet, 6.2+ note
- [x] CLAUDE.md: "single library product/target" is now wrong
- [x] CLAUDE.md: four-manifest sync rule needs a swift-log carve-out
- [x] CLAUDE.md: DocC command hardcoded to `--target SwiftLogSmith`
- [ ] `docs/` regenerated — **deliberately not run**, see deviations

---

## Verification checklist

Local toolchain at time of writing: Swift 6.3.2 / Xcode 26.5.

- [x] `swift build` — new target compiles under `.swiftLanguageMode(.v6)`, `.strictMemorySafety()`,
      `ExistentialAny`
- [x] `swift test` — the existing 39 tests pass **unchanged** (the evidence that core changes were
      additive)
- [x] The documented wrapper pattern still compiles:
      ```swift
      func myLog(_ m: String, fileId: StaticString = #fileID,
                 function: StaticString = #function, line: UInt = #line) {
          LogSmith.logD(m, fileId: fileId, function: function, line: line)
      }
      ```
- [x] `swift test --filter SwiftLogSmithBackendTests`
- [x] End-to-end smoke test with a **real** bootstrap:
      ```swift
      LoggingSystem.bootstrapWithLogSmith()
      LogSmith.addLogger(newLogger: FileLogger())
      Logger(label: "com.demo.net").error("Request failed", metadata: ["user": ["id": "7"]])
      ```
      Confirm: appears via `OSLogger` **and** on disk via `FileLogger`; nested metadata rendered;
      `file`/`function`/`line` point at the call site, not inside the bridge.
- [x] `Package@swift-6.0.swift` still resolves with no swift-log — bridge absent, not broken
- [x] `Package.resolved` pulls no unexpected transitive dependencies

---

## Deliberately deferred

Decisions, not omissions.

| Item | Why deferred |
|---|---|
| **Synchronous / flush logging** | CocoaLumberjack's `loggingSynchronousAsOf: .error` logs at or above a threshold synchronously so errors reach disk before a crash. SwiftLogSmith has no synchronous path at all — `FileLoggerManager.write` is fire-and-forget with no flush API. A real gap, but orthogonal to swift-log and a larger change to the core. |
| **Rich core metadata** (`[String: String]` → structured) | Would break dictionary-literal ergonomics: swift-log keeps `["k": "v"]` compiling because `MetadataValue` is an *enum* conforming to `ExpressibleByStringLiteral`, which isn't ObjC-representable. An existential `any LogMetadataValue` cannot be expressed by a literal, so every call site would regress. Also breaks all nine `LogSmith.log*` statics plus `LogFormatter.addMetadataPart`'s closure type. Legitimate as its own major version, decided on core-library merit — not as a prerequisite for the bridge. |
| **`SwiftLogDestination: ILogger`** (LogSmith → swift-log) | The reverse direction. Would let `LogSmith.logE` reach existing swift-log handlers, but does not capture logs from libraries using swift-log, which is the actual goal here. |
| **Fixing the `LogType` ordering inversion** | Breaking change to public raw values. Documented and mitigated instead — see above. |

---

## Deviations found during execution

### `LogManager.log` keeps `#fileID`/`#function`/`#line` defaults

The plan specified the new `String`-based parameters should have **no defaults**, so that calls
omitting them would unambiguously resolve to the `StaticString` variant. That reasoning was an
artifact of an earlier overload-based design that was abandoned in favour of straight replacement.

With only one `log` method there is nothing to disambiguate, and `#fileID`/`#function` work as
`String` defaults just as well as `StaticString` ones. Dropping the defaults would have broken
~20 existing `LogManagerTests` call sites and every direct `LogManager` user, for no benefit.

Kept the defaults. Result: **all 39 existing tests pass with no test-file changes at all**, which
is stronger evidence of additivity than the plan anticipated.

### Symbolic `[E]`/`[I]` tags only appear on the shared pipeline

``LogSmith``'s initialiser registers one `ExternalTag` per `LogType` (mapping e.g. `.error` to `"E"`)
on **its own** manager. A `LogManager` you construct yourself has no such tags, so bridged messages
sent to an isolated manager render without the `[E]` prefix.

This is correct behaviour, not a bug, but it surprised the first version of the formatter test. Both
paths are now covered explicitly: `LogSmithLogHandlerTests` asserts the tag is *absent* on an isolated
manager, `SharedPipelineConcurrencyTests` asserts it is *present* on the shared one.

### Tests use a spy callback rather than polling

The first version of the suite polled `logCallCount` from a background queue. Those loops outlived
their tests and crashed in `tearDown` once the spy was nilled. `BackendMockLogger.setOnLog(_:)` now
drives `XCTestExpectation` directly, which also removed the non-Sendable `self`-capture warnings.

---

## Pre-existing bug found during verification (NOT introduced here, NOT fixed here)

**The first log file of every session is spuriously archived.**

`SessionRollingFrequency.shouldRoll` reads `LogSmith.sessionLaunchTime`, but only *after* an early
`guard let createdAt = logFile.createdAt else { return false }`. On the very first write the file does
not exist on disk yet, so `createdAt` is `nil` and the guard returns before ever touching
`sessionLaunchTime`. The static therefore initialises lazily during the **second** write — by which
point file #1 already predates it, so it is judged stale and rolled.

Reproduced with three sequential `LogSmith.logI` calls against a default `FileLoggerManager`:

```
file count: 2
--- SLS_20260805153436816.log ---
[I] message-2
[I] message-3
--- SLS_20260805153436505.log.zip ---   <- message-1, archived immediately
```

Impact: every process run leaves a stray single-entry zip and burns one slot against
`maximumArchiveFiles`. No data is lost. Entirely independent of the swift-log work — `FileLogger.swift`
and `sessionLaunchTime` were not touched by this change.

Likely fix (deliberately out of scope): initialise `sessionLaunchTime` eagerly at process start, or
read it in `shouldRoll` before the `createdAt` guard.

---

### `docs/` deliberately not regenerated

The correct invocation was verified against a scratch directory and produces **0 DocC warnings**,
generating both `documentation/swiftlogsmith` (existing published URL preserved) and
`documentation/swiftlogsmithbackend`:

```
swift package --allow-writing-to-directory ./docs generate-documentation \
  --target SwiftLogSmith --target SwiftLogSmithBackend \
  --enable-experimental-combined-documentation \
  --disable-indexing --transform-for-static-hosting \
  --hosting-base-path swift-logsmith --output-path ./docs
```

Not run against `./docs` here, because it rewrites ~500 generated files and would bury the actual
code change in an unreviewable diff. **Run it as its own commit.**

Reaching 0 warnings required one source change: cross-module DocC symbol links in the backend
(`` ``SwiftLogSmith/LogMessage`` ``) resolve relative to `SwiftLogSmithBackend` and always fail.
They are now plain code spans (`` `LogMessage` ``), which also keeps single-target generation clean.
Recorded in `CLAUDE.md`.

---

## Note on this file's location

`.claude/` is **untracked** in git as of this change. The file is not gitignored, so `git add .claude/`
will commit it — but it will not be picked up by an unqualified `git add -u`.
