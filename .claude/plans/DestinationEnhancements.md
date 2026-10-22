# Enhancing SwiftLogSmith's Destinations: Four New Loggers

## Context

SwiftLogSmith ships exactly two destinations — `OSLogger` (default) and `FileLogger` — despite `ILogger`
being designed as the library's main extension point (`Core/ILogger.swift:41`, whose doc comment explicitly
names "console, file, or a remote server" as intended targets at `:55`). That leaves real gaps:

- **No plain console output.** `OSLogger` interpolates a non-literal `String` (`OSLogger.swift:71-93`), so
  os_log's default privacy rules redact the payload as `<private>` in Console.app and on device. In CLI
  tools, server-side Swift, and CI/`swift test` output, os_log is effectively invisible. The README
  advertises system logging, but there is no way to simply see a log line on stdout.
- **No in-memory destination.** In-app log viewers, "attach recent logs to a bug report" flows, and crash
  breadcrumbs all need a bounded recent-history buffer. There is none. As a symptom, the test suite
  hand-rolls four near-identical `ILogger` mocks (`LogManagerTests.swift:12` and `:35`,
  `LogFormatterTests.swift:13`, `LogSmithTests.swift:13`).
- **No cheap bridge to third-party sinks.** Sending logs to Crashlytics/Sentry/DataDog today requires
  authoring a full `NSObject`-rooted `@objc` class.
- **No remote destination**, and none of the batching/retry primitives one would need to build one.

The intended outcome is four new destinations that make the pluggable-destination story real, all strictly
source-compatible with v1.1.0. Separately identified breaking changes are recorded at the end as a 2.0 track
rather than folded in.

**Scope decisions (from the user):** new destinations only — hardening `FileLogger`, `OSLogger` privacy
controls, and `ILogger` contract changes are explicitly out of scope for this plan. Additive API only.
`RemoteLogger` uses Foundation's `URLSession` and adds no package dependencies; the transport is behind a
protocol so a third-party dependency can be swapped in later without an API break.

**Baseline and delivery:** this plan builds on `main` *after*
[eeshanjamal/swift-logsmith#1](https://github.com/eeshanjamal/swift-logsmith/pull/1) (the
`SwiftLogSmithBackend` swift-log product) merges. That PR adds `LogMessage.payload` (`any LogPayload`), changes
`LogManager.log` to take `payload:` and `String` `fileId`/`function`, and adds lines to `LogManager.swift`,
`LogSmith.swift`, `LogMessage.swift` and `README.md` — so the line numbers cited here, taken from `main` at
`6ae88a6`, will shift in those files; re-derive them by symbol. `main` only takes changes through pull
requests: work on a feature branch (e.g. `feat/destination-enhancements`) with one pull request per phase.

## Constraints to honor

From `CLAUDE.md` and the existing code:

- **Obj-C interop is load-bearing.** Every new public type must be `@objcMembers public final class X: NSObject`,
  every new enum `@objc public enum ... : Int, Sendable` (no associated values), every new protocol
  `@objc public protocol ... : Sendable` (no generics or associated types). Also mark each member meant for
  Obj-C with an explicit `@objc`: `@objcMembers` silently skips anything it cannot represent (on `main`, none
  of the `LogSmith.log*` methods reach the generated header, because of their `StaticString` parameters),
  whereas an explicit `@objc` turns that into a compile error.
- **No actors.** Thread safety uses a private serial `DispatchQueue` plus `NSLock`-guarded storage, with
  `@unchecked Sendable` on types holding mutable state — follow `FileLoggerManager.swift:108`/`:162` and
  `FormattingState` (`LogFormatter.swift:161`).
- **Swift 6 language mode + `.strictMemorySafety()`** on the 6.2/6.3 manifests. C-interop calls whose
  signatures involve pointers (e.g. `getenv`, `__dispatch_queue_get_label`) need the `#if swift(>=6.2)` /
  `unsafe` treatment used at `Extensions/DispatchQueueX.swift:11`. `isatty` takes and returns `Int32`, so it
  needs none — marking it `unsafe` produces a "no unsafe operations occur within 'unsafe' expression"
  warning. Read environment variables through `ProcessInfo.processInfo.environment`, not `getenv`.
- **File conventions.** `InternalImportsByDefault` is on in every manifest, so a file whose public API
  exposes Foundation types needs `public import Foundation` (as at `OSLogger.swift:9`). Every file starts
  with the SPDX header block.
- **No manifest changes needed** — `URLSession` is Foundation. If a dependency is ever added, all four of
  `Package.swift`, `Package@swift-6.0.swift`, `Package@swift-6.1.swift`, `Package@swift-6.2.swift` must be
  updated in lockstep.
- **Never block the logging pipeline.** `LogManager.log` hands each message to the manager's `LogTagger`
  (`Core/LogManager.swift:201`), and the fan-out to destinations runs inline on that tagger's serial queue
  (`:214`) — or on the logger's own tagger queue, if it has one. This is by design: it keeps log statements
  sequential, and moving the fan-out onto `LogManager`'s own queue would break that. Completions are
  collected with a `DispatchGroup` observed via `notify`. A destination that blocks stalls all logging; a
  destination that drops its completion silently strands the caller's; a destination that calls its
  completion twice traps on `group.leave()`. Every new destination must invoke its completion
  **exactly once**.
- **`.undefined` is accepted.** `OSLogger` returns `false` for it (`OSLogger.swift:74-75`) only because there
  is no `OSLogType` to map it to. `FileLogger` writes it (`FileLogger.swift:91-95`), and `LogType.undefined`
  is documented as a valid "no specified severity" type (`LogSmith.swift:351`). The new destinations follow
  `FileLogger`: treat `.undefined` as the lowest severity and complete with `true`.

## Phase 1 — `ConsoleLogger` and `MemoryLogger`

### `Sources/SwiftLogSmith/Destinations/ConsoleLogger.swift`

```swift
@objc public enum ConsoleStream: Int, Sendable {
    case standardOutput      // everything to stdout (default)
    case standardError       // everything to stderr
    case splitBySeverity     // .warning/.error/.fault/.critical -> stderr, rest -> stdout
}

@objc public enum ConsoleColorMode: Int, Sendable {
    case automatic           // color a stream only when it is an interactive terminal (default)
    case always
    case never
}

@objcMembers public final class ConsoleLogger: NSObject, ILogger {
    public let formatter: LogFormatter
    public let tagger: LogTagger?
    public let stream: ConsoleStream
    public let colorMode: ConsoleColorMode

    @objc public convenience init(stream: ConsoleStream = .standardOutput,
                                  colorMode: ConsoleColorMode = .automatic,
                                  logFormatter: LogFormatter = LogFormatter.default,
                                  logTagger: LogTagger? = nil)

    /// Test seam: tests pass `Pipe().fileHandleForWriting` handles and read the other ends.
    internal init(stream: ConsoleStream, colorMode: ConsoleColorMode,
                  logFormatter: LogFormatter, logTagger: LogTagger?,
                  standardOutput: FileHandle, standardError: FileHandle)

    public func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)? = nil)
}
```

- Writes `formatter.format(message:) + "\n"` as UTF-8 to the injected handles (the public init passes
  `FileHandle.standardOutput` / `.standardError`) on one `private static let` serial
  `DispatchQueue(label: "com.swift.logsmith.console")` shared by every instance: stdout and stderr are
  process-wide, so per-instance queues would not stop two loggers interleaving. Completion fires after the
  write, `false` if `write(contentsOf:)` throws. `FileHandle` is `Sendable`, so no `@unchecked Sendable` is
  needed.
- Severity routing for `.splitBySeverity` derives from `message.logType.logLevel` (`LogSmith.swift:423`) —
  the `.error` and `.fault` levels go to stderr — so it stays in sync with the two-tier model rather than
  re-listing cases. `.standardOutput` is the default; the note below explains why.
- ANSI coloring maps `LogType` → SGR codes, wrapping the formatted string. Not `LogLevel`: warnings and
  errors both map to `.error` (`LogSmith.swift:433-434`) and would share a color. `.automatic` is resolved
  once per target stream at init: color only when `NO_COLOR` is unset, `TERM` is set and not `dumb`, and
  `isatty(handle.fileDescriptor) != 0`. `isatty` alone is not enough — Xcode's debug console is typically a
  pseudo-terminal that does not render escape codes — so confirm the `TERM` check in Xcode during
  implementation.
- Document that adding a `ConsoleLogger` alongside the default `OSLogger` prints every line twice in Xcode's
  console, which shows both; for CLI tools and tests, show `LogSmith.replaceDefaultLogger(with: ConsoleLogger())`.

#### Note: why the default stream is `.standardOutput`

Splitting by severity only works while stdout and stderr end up in the same place. On a terminal and in
Xcode's console they do, so `.standardOutput` and `.splitBySeverity` look identical there. Once output is
redirected or piped, the error lines are separated from the rest — and that is usually when someone is
saving or filtering logs.

Example, from a small program that routes five lines the way `.splitBySeverity` would (the error line to
stderr, the rest to stdout), using the same unbuffered `FileHandle` writes as `ConsoleLogger`. On a terminal
it looks fine:

```text
[I] Connecting to api.example.com
[D] GET /users/42
[E] GET /users/42 failed: 503 Service Unavailable
[I] Retrying in 2s
[I] GET /users/42 succeeded
```

**Saving to files** (`./tool > out.log 2> err.log`) puts the error apart from what led up to it:

```text
--- out.log
[I] Connecting to api.example.com
[D] GET /users/42
[I] Retrying in 2s
[I] GET /users/42 succeeded
--- err.log
[E] GET /users/42 failed: 503 Service Unavailable
```

`out.log` reads like a run that went fine, and `err.log` has a failure with nothing around it to say which
request failed or what happened next.

**Saving with `tee`** (`./tool | tee run.log`): `run.log` gets the same four lines as `out.log` and misses the
error — the one line the log was kept for. The error goes to the screen instead.

**Filtering with `grep`** (`./tool | grep users`): grep receives only `[D] GET /users/42` and
`[I] GET /users/42 succeeded`. The error line contains "users" too, but it never goes through the filter; it
prints straight to the screen, unfiltered.

**With one stream**, `./tool > all.log` captures all five lines in order, and `tee` and `grep` see everything.

Splitting is still useful for collecting only the errors (`2> errors.log`) or keeping errors on screen while
stdout goes to a file, so `.splitBySeverity` stays available as an option; it just isn't the default.

Which single stream to default to is a closer call. stdout matches this plan's motivation (seeing log lines
on stdout), and plain `>`, `|` and `tee` capture it without `2>&1`. stderr is the usual Unix convention for
diagnostics, and it is the better default for command-line tools whose stdout is their actual output (JSON, a
file listing): any log line on stdout corrupts that output, and splitting doesn't help there because info
and debug lines still go to stdout. If such tools turn out to be the main audience, switch the default to
`.standardError`.

### `Sources/SwiftLogSmith/Core/LogEntry.swift`

```swift
@objcMembers public final class LogEntry: NSObject, Sendable {
    public let message: LogMessage
    public let formattedMessage: String
    public let timestamp: Date
}
```

- Shared by `MemoryLogger` (below) and `RemoteLogger` (Phase 3), so it lives in `Core/` under a neutral
  name. It appears in the public `RemoteLogPayloadEncoder` protocol, so a destination-specific name such as
  `MemoryLogEntry` could not be changed after release without a break. Its initializer is `internal`.
- `timestamp` is captured when the destination receives the message — a few queue hops after the call site
  — and is documented as such. This is where a real `Date` lands **without** touching `LogMessage` — today,
  time only reaches a destination as a stringly-typed `Tag` (`LogMessage.swift:47-63` has no timestamp
  field). Keeping it on the entry keeps this plan additive; if `LogMessage` later gains a native timestamp,
  `timestamp` can forward to it without an API change.

### `Sources/SwiftLogSmith/Destinations/MemoryLogger.swift`

```swift
@objcMembers public final class MemoryLogger: NSObject, ILogger, @unchecked Sendable {
    public static let defaultCapacity: Int   // platform-tiered, see below
    public let capacity: Int
    public let formatter: LogFormatter
    public let tagger: LogTagger?

    public init(capacity: Int = MemoryLogger.defaultCapacity,
                logFormatter: LogFormatter = LogFormatter.default,
                logTagger: LogTagger? = nil)

    public var count: Int                          // NSLock-guarded
    public func entries() -> [LogEntry]            // oldest -> newest snapshot
    public func formattedEntries() -> [String]
    public func export() -> String                 // entries joined by "\n", for bug reports
    public func drain() -> [LogEntry]              // snapshot + clear, atomically
    public func clear()

    public func log(message: LogMessage, completion: (@Sendable (Bool) -> Void)? = nil)
}
```

- Fixed-capacity ring buffer over `[LogEntry]`, guarded by a single `NSLock` — the same pattern as
  `FormattingState` (`LogFormatter.swift:161-195`) and `ResultTracker` (`LogManager.swift:278`). Appending
  past `capacity` evicts the oldest. `capacity <= 0` is clamped to `1`.
- `defaultCapacity` follows the platform-tiering precedent at `FileLoggerManager.swift:134-149`
  (`#if os(watchOS)` / `#elseif os(tvOS)` / `#else`) — suggest 100 / 200 / 500.
- Logging is asynchronous, so `entries()`, `export()` and `drain()` only reflect messages whose log
  completion has already fired; a message logged just before `export()` may not be in the buffer yet.
  Document this, since "attach recent logs to a bug report" is the headline use.
- Entries retain the full `LogMessage`, including #1's `payload`.

**Test-suite consolidation** (a separate, final step once the new suites are green, so a `MemoryLogger`
regression cannot be mistaken for a failure in the suites it replaces): `MemoryLogger` replaces the ad-hoc
mocks in `LogFormatterTests.swift:13` and `LogSmithTests.swift:13`. It is not a drop-in swap:
`LogFormatterTests` reassigns `logger.formatter` in each test (`LogFormatterTests.swift:43`, `:89`, `:130`,
`:171`, `:213`), but `MemoryLogger.formatter` is a `let`, so each test builds and registers its own
`MemoryLogger` with the formatter it needs. Leave `FirstMockLogger`/`SecondMockLogger`
(`LogManagerTests.swift:12`, `:35`) in place — they exist as two distinct class names specifically because
`LoggerItem`'s `UserDefaults` override keys are derived from `String(describing: type(of: logger))`
(`LogManager.swift:372-374`), so two instances of `MemoryLogger` could not be tuned independently.

## Phase 2 — `ClosureLogger`

### `Sources/SwiftLogSmith/Destinations/ClosureLogger.swift`

```swift
@objcMembers public final class ClosureLogger: NSObject, ILogger {
    public let formatter: LogFormatter
    public let tagger: LogTagger?

    /// Synchronous handler; completion reports `true` once the handler returns.
    @objc public init(logFormatter: LogFormatter = LogFormatter.default,
                      logTagger: LogTagger? = nil,
                      handler: @escaping @Sendable (LogMessage, String) -> Void)

    /// Asynchronous handler; the handler reports its own success.
    @objc public init(logFormatter: LogFormatter = LogFormatter.default,
                      logTagger: LogTagger? = nil,
                      asyncHandler: @escaping @Sendable (LogMessage, String, @escaping @Sendable (Bool) -> Void) -> Void)
}
```

- Passes both the raw `LogMessage` (for structured sinks that want `tags`/`metadata`) and the formatted
  string (for sinks that want a line). This is the one-liner bridge to Crashlytics/Sentry/DataDog and is
  also ideal for SwiftUI previews and unit tests.
- Handlers run on the logger's own private serial `DispatchQueue`, not inline. `log` is called on the
  pipeline's tagger queue (see Constraints), so a slow or blocking user closure would otherwise stall every
  destination; the queue is serial, so handlers still see messages in order.
- The completion handed to `asyncHandler` is wrapped in an `NSLock`-guarded once-only guard before it
  reaches user code: a second call is ignored instead of reaching `group.leave()` twice and trapping
  (`LogManager.swift:216`). A handler that never calls it strands the caller's completion, so the DocC
  comment must say it has to be called on every path.
- Closures bridge to Obj-C as blocks. The two initializers export with distinct selectors,
  `initWithLogFormatter:logTagger:handler:` and `initWithLogFormatter:logTagger:asyncHandler:` (checked
  against a typechecked sketch; `ExternalTag` already does the same at `LogTagger.swift:138`/`:149`), so no
  custom `@objc(...)` selector is needed.
- `LoggerItem`'s `UserDefaults` override keys use the type name (`LogManager.swift:372-374`), so all
  `ClosureLogger` instances share one override. The `minLogLevel`/`minLogType` passed to `addLogger` stay
  per instance; document the limitation.

## Phase 3 — `RemoteLogger`

Three new files under `Sources/SwiftLogSmith/Destinations/`, kept separate so the transport can be
replaced later without an API break. Both protocols are public and fixed once released, so they carry what
any later transport or encoder needs: the payload's content type, and whether a failure is worth retrying.

### `RemoteLogTransport.swift`

```swift
@objc public enum RemoteLogSendResult: Int, Sendable {
    case delivered      // accepted by the server
    case retryable      // transient failure: keep the entries and try again later
    case rejected       // permanent failure: retrying cannot help, drop the batch
}

@objc public protocol RemoteLogTransport: Sendable {
    @objc func send(payload: Data, contentType: String,
                    completion: @escaping @Sendable (RemoteLogSendResult, NSError?) -> Void)
}

@objcMembers public final class URLSessionRemoteLogTransport: NSObject, RemoteLogTransport {
    public static let errorDomain: String   // HTTP-status failures; the code is the status
    public init(endpoint: URL,
                httpMethod: String = "POST",
                additionalHeaders: [String: String] = [:],
                session: URLSession = .shared)
}
```

- Sets `Content-Type` from the `contentType` argument; `additionalHeaders` are for auth and routing. Without
  it, `URLSession` labels a POST body `application/x-www-form-urlencoded` (confirmed with a loopback
  request), which ingestion endpoints reject or misparse.
- Maps the outcome: 2xx → `.delivered`; a transport error, 408, 429 or 5xx → `.retryable`; any other status
  → `.rejected`. A `dataTask` that receives HTTP 500 reports no error, so the status code must be checked.
- Calls its completion exactly once, on every path.

Injecting `URLSession` is what makes this testable — tests register a `URLProtocol` stub (or supply a
trivial in-test `RemoteLogTransport`) so **no test ever touches the network**. CI (`build-and-test.yml`)
has no server.

### `RemoteLogPayloadEncoder.swift`

```swift
@objc public protocol RemoteLogPayloadEncoder: Sendable {
    @objc var contentType: String { get }
    @objc func encode(entries: [LogEntry]) -> Data?     // nil drops the batch (counted)
}

@objc public enum JSONPayloadStyle: Int, Sendable { case jsonArray, newlineDelimited }

@objcMembers public final class JSONRemoteLogPayloadEncoder: NSObject, RemoteLogPayloadEncoder {
    public init(style: JSONPayloadStyle = .jsonArray)
    public var contentType: String   // "application/json" or "application/x-ndjson"
}
```

Each entry encodes to `{ "timestamp", "message", "formattedMessage", "logType", "tags", "metadata" }`:

- `timestamp` — epoch milliseconds (`Int64`): locale-proof, and it avoids storing an `ISO8601DateFormatter`,
  which is not `Sendable`.
- `logType` — `logType.stringValue` (`LogSmith.swift:386`), except `"none"` and `"undefined"` for the two
  cases where `stringValue` is an empty string.
- `tags` — `Tag` (`LogMessage.swift:25`) flattened to `identifier`/`value`/`tagType`, with `tagType` as
  `"internal"` or `"external"`.
- `metadata` — the flat `[String: String]` as is.
- Keys are sorted (`JSONSerialization`'s `.sortedKeys`) so output is deterministic for tests.
- #1's `LogMessage.payload` is not encoded, since the core module cannot know its concrete type. Custom
  encoders can downcast it (e.g. to `SwiftLogPayload`); the backend already flattens swift-log metadata into
  `metadata`.

Keeping the encoder pluggable means the wire format is not opinionated — users targeting Datadog/Loki/Splunk
supply their own.

### `RemoteLogger.swift`

```swift
@objc public enum RemoteLogOverflowPolicy: Int, Sendable { case dropOldest, dropNewest }

@objcMembers public final class RemoteLogger: NSObject, ILogger, @unchecked Sendable {
    public init(transport: any RemoteLogTransport,
                encoder: any RemoteLogPayloadEncoder = JSONRemoteLogPayloadEncoder(),
                batchSize: Int = 50,
                flushInterval: TimeInterval = 30,
                maximumBufferedEntries: Int = 1000,
                overflowPolicy: RemoteLogOverflowPolicy = .dropOldest,
                maximumRetryAttempts: Int = 3,
                logFormatter: LogFormatter = LogFormatter.default,
                logTagger: LogTagger? = nil)

    public var bufferedEntryCount: Int { get }   // entries waiting to be sent
    public var droppedEntryCount: Int { get }    // overflow + rejected + unencodable, since init

    public func flush(completion: (@Sendable (Bool) -> Void)? = nil)
}
```

Behavior:

- `log(message:completion:)` **enqueues and returns immediately**, calling `completion(true)` on successful
  buffering — *not* on successful delivery. This is non-negotiable given `LogManager`'s inline serial fan-out
  (`LogManager.swift:214`); blocking on a network round-trip would stall every other destination. Document
  this semantic prominently in the DocC comment, since it differs from `FileLogger`'s. If `dropNewest`
  discards the new entry, the completion is `false`.
- **One batch in flight.** A private serial queue owns the buffer and the send state. At most one batch is
  sent at a time, which preserves order; flush triggers that arrive meanwhile coalesce.
- **Triggers.** A flush starts when `batchSize` entries are buffered, when the timer fires, or when
  `flush(completion:)` is called. The timer is a one-shot `DispatchSourceTimer` on the private queue, armed
  when the buffer goes from empty to non-empty (so an idle logger never wakes the process), with a
  `[weak self]` handler, and cancelled in `deinit`.
- **Results.** `.delivered` removes the batch. `.rejected` drops it and adds to `droppedEntryCount`.
  `.retryable` retries with exponential backoff up to `maximumRetryAttempts` times; if those run out, the
  batch goes back to the **front** of the buffer and waits for the next flush — it is not dropped. An outage
  therefore costs buffer space, not data, until the buffer fills. An encoder that returns `nil` drops the
  batch and adds to `droppedEntryCount`.
- **Overflow.** When the buffer hits `maximumBufferedEntries`, `overflowPolicy` decides which end to discard,
  counted in `droppedEntryCount`. Together with `.rejected` results and unencodable batches, this is the
  only way an entry is lost while the process runs.
- **`flush(completion:)`** sends everything buffered at call time, in `batchSize` chunks, joining a send
  already in flight; its completion is `true` only if all of it was delivered, and `true` immediately for an
  empty buffer. It is a public method on `RemoteLogger` — **not** added to `ILogger`, which keeps this phase
  additive. Call it from `applicationDidEnterBackground`/`willTerminate`; on iOS, hold a background task
  (`beginBackgroundTask` or `ProcessInfo.performExpiringActivity`) around it, or the process may be
  suspended mid-send. It only covers entries already in the buffer: logging is asynchronous, so a message
  logged just before the call may miss it.
- **Parameter clamping.** `batchSize` ≥ 1, `maximumBufferedEntries` ≥ `batchSize`, `maximumRetryAttempts` ≥ 0;
  `flushInterval <= 0` disables the timer, leaving `batchSize` and explicit `flush` calls as the triggers.
- **Removal.** Removing the logger from `LogSmith` does not flush it; call `flush` first.

Known limitation to document rather than solve here: buffered entries are **not persisted across launches**,
so a crash or termination loses the pending batch. Disk-backed spooling (pairing with `FileLoggerManager`)
is a natural follow-up.

## Phase 4 — Documentation

- `README.md:18-23` — add the four destinations to the Key Features list.
- `README.md:128-151` — the mermaid architecture diagram hard-codes `Dest1[OSLogger]`/`Dest2[FileLogger]`;
  extend it with the new destinations and their outputs.
- Add a short "Custom Destinations" section to the README pointing at `ClosureLogger` as the easy path and
  the `ILogger` doc comment (`Core/ILogger.swift:15-40`) as the full path.
- `CLAUDE.md` — its Architecture diagram and Source layout list only `OSLogger` and `FileLogger`; add the
  four new destinations and `Core/LogEntry.swift`.
- Every new public symbol needs `///` DocC comments matching the existing density (see `FileLogger.swift`) —
  the checked-in `docs/` site is generated purely from these.
- Regenerate the static site per `CLAUDE.md:31-35`.

## Testing

New files in `Tests/SwiftLogSmithTests/`, following the existing `test<Action>_<Condition>_Should<Outcome>()`
convention and reusing `expectCompletion(description:fulfillmentCount:timeout:operation:)`
(`XCTestCase+Helpers.swift:19`). `LogMessage.init` is `internal`, so `@testable import SwiftLogSmith` is
required to construct fixtures — as `OSLoggerTests.swift:31` already does.

- `ConsoleLoggerTests.swift` — stream routing for all three `ConsoleStream` modes, `.undefined` accepted,
  color `always`/`never`, and `.automatic` resolving to no color on a pipe. Assert actual bytes through the
  internal initializer: pass `Pipe().fileHandleForWriting` handles and read the other ends, so nothing
  redirects the process's real stdout.
- `MemoryLoggerTests.swift` — capacity eviction (oldest dropped), `capacity <= 0` clamped to `1`, ordering,
  `count`, `export()` line count, `drain()` empties atomically, `clear()`, concurrent writes from multiple
  queues under `DispatchQueue.concurrentPerform` to prove the lock holds.
- `ClosureLoggerTests.swift` — handler receives both raw and formatted forms; async handler's `false`
  propagates to the completion; an async handler that calls its completion twice forwards only the first
  result; handlers run in order.
- `RemoteLoggerTests.swift` — batching at `batchSize`, timer-driven flush, retry-then-succeed, retries
  exhausted (the batch returns to the buffer rather than being dropped), `.rejected` drops and counts, an
  encoder returning `nil`, both overflow policies (`dropNewest` completes `false`), `flush()` drains, an
  empty `flush()` completes `true`, one batch in flight at a time, deallocation cancels the timer, and
  completion-called-exactly-once. All against an in-test `RemoteLogTransport` stub; no network. Production
  backoff would exceed `expectCompletion`'s one-second default timeout, so give `RemoteLogger` an internal
  initializer taking a `retryBaseDelay`, following `FileLoggerManager`'s (`FileLogger.swift:206-212`), and
  use millisecond delays and a short `flushInterval` in tests.
- `JSONRemoteLogPayloadEncoderTests.swift` — both payload styles and their `contentType`, tags/metadata
  round-trip, `logType` for `.none`/`.undefined`, epoch-millisecond timestamps, sorted keys, empty input.
- `URLSessionRemoteLogTransportTests.swift` — request method, headers and `Content-Type`; status mapping for
  2xx, 408/429/5xx, other 4xx and a transport error. Register a `URLProtocol` subclass in an ephemeral
  `URLSessionConfiguration`'s `protocolClasses`; inside the stub the body arrives on `httpBodyStream`, not
  `httpBody`.

Integration check: register all four on a private `LogManager(identifier:defaultLogger:)` with an `OSLogger`
default — as `LogManagerTests.swift:66` does — rather than the shared `LogSmith` singleton, so nothing leaks
into other suites, and assert the aggregate completion is `true`, exercising the `DispatchGroup` fan-out.

## Verification

```bash
swift build
swift test
swift test --filter SwiftLogSmithTests.MemoryLoggerTests
swift test --filter SwiftLogSmithTests.RemoteLoggerTests
```

`ConsoleLogger`'s bytes are asserted in `ConsoleLoggerTests` through its internal `FileHandle` seam; its
lines also showing up in `swift test` output is a useful smoke check, not a substitute.

Also confirm:

- No Swift 6 strict-concurrency or `.strictMemorySafety()` diagnostics on the default manifest, **and** on
  the 6.0 path — which CI does not currently build, despite the comment at
  `.github/workflows/build-and-test.yml:16` (see item 10 below).
- Every member meant for Obj-C appears in the generated header,
  `.build/<triple>/debug/SwiftLogSmith.build/include/SwiftLogSmith-Swift.h` (e.g.
  `grep -n 'ConsoleLogger\|MemoryLogger\|ClosureLogger\|RemoteLogger'` on it).
- Docs preview renders the new types: `swift package --disable-sandbox preview-documentation --target SwiftLogSmith`.
- Coverage does not regress — CI uploads to Coveralls from the `macos-26` leg.

## Flagged for a future 2.0 (out of scope here, recorded so it is not lost)

These are real defects/limitations found while surveying the destinations layer, all requiring breaking
changes:

> **Note:** only item 1 (the `ILogger` error channel) and the `SortOrder` rename in item 7 actually need a
> breaking change; the rest can ship in 1.x. Items 10–12 were found while reviewing this plan.

1. **`ILogger` has no error channel** — `log`'s completion is a bare `Bool` (`ILogger.swift:59`);
   `FileLogger.log` discards the manager's `NSError` outright (`FileLogger.swift:92-94`); `LogManager`
   AND-reduces booleans (`LogManager.swift:278`) and never reports *which* destination failed. A failing
   destination is invisible in production.
2. **`FileLogger`'s default argument is `try!`** (`FileLogger.swift:81`) — a logging library that traps at
   construction if Application Support is unavailable.
3. **`FileLogger.manager` is internal** (`FileLogger.swift:73`) — a caller using the default manager has no
   route to `listLogFiles`/`clearLogs`, i.e. no log export path.
4. **`OSLogger` has no privacy control** (`OSLogger.swift:71-93`) — every message is a non-literal
   interpolation with no `privacy:` argument, so payloads read as `<private>` off-device.
5. **Purging only runs as a side effect of a roll** (`FileLogger.swift:323-326`) and counts only `.zip`
   files (`:388`, `:402`), so with the default `SessionRollingFrequency` the active `.log` grows unbounded
   within a session.
6. **Locale-sensitive log filenames** — the `DateFormatter` at `FileLogger.swift:164-168` sets no
   `en_US_POSIX` locale or fixed time zone, so `SLS_<timestamp>.log` names are wrong under non-Gregorian
   user calendars and same-millisecond rolls collide.
7. **Top-level `SortOrder`** (`FileLogger.swift:29`) shadows Foundation's `SortOrder` for every client; the
   descending comparator's `!result` (`:277`) is not a valid strict weak ordering.
8. **`LogMessage` carries no native timestamp, callsite, or thread** (`LogMessage.swift:47-56`) and its init
   is `internal`, so third-party destinations cannot construct one to test against.
9. **Stray `print(...)` in library code** at `FileLogger.swift:378`.
10. **CI never builds the Swift 6.0 manifest** — the `macos-15` runner's Xcode 16.4 carries Swift 6.1.2 (per
    the environment step of the latest `main` run), so CI covers `Package@swift-6.1.swift` and
    `Package.swift`; `Package@swift-6.0.swift` and `Package@swift-6.2.swift` are never built, despite the
    comment at `.github/workflows/build-and-test.yml:16`. If 6.0 support matters, add a job pinned to a
    Swift 6.0 toolchain.
11. **Data race on `LogManager.loggerItems`** — it is read on the manager tagger's queue
    (`LogManager.swift:204`) while `addLogger`/`removeLogger`/`replaceDefaultLogger` mutate it on the
    manager's queue (`:100-137`). Snapshotting `loggerItems` on the manager's queue before the hop to the
    tagger fixes it without changing the sequential design.
12. **`InternalTag(.threadName)` reports the library's queue, not the caller's thread** — it is resolved
    after the queue hops (`LogManager.swift:350-357`), so it always yields the tagger's label
    (`com.swift.logtag.<UUID>`). Capture the thread name before the first hop and pass it through, as
    `fileId`/`function`/`line` already are.
