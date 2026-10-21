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

Instead the bridge routes through a single `LogSmith` funnel, `logInternal`, which every first-party
logging function uses too, so every operation stays behind the same hop. A user-owned `LogManager`
remains available as opt-in isolation.

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

### Former sharp edge: `LogType` ordering inversion — fixed in 2.0.0

Up to 1.1.0, `LogType`'s raw values ordered `notice(1) < info(2) < debug(3) < trace(4)` — the **reverse** of
swift-log's `trace < debug < info < notice`. Since `LogManager` filters with
`logType.rawValue >= minimum`, calling `setMinimumLogType(.info)` silently dropped swift-log
`.notice` messages.

The first version of the bridge only worked around it: the handler defaults `logLevel` to `.trace` so swift-log's
own (correctly ordered) comparison does the gating, and the documentation told users to filter bridged loggers on
`logger.logLevel` or `bootstrapWithLogSmith(defaultLogLevel:)` and leave LogSmith's minimums alone. The raw values
now follow severity, so there is nothing left to work around. See "`LogType` and `LogLevel` are ordered by
severity" under "Found during pre-merge testing".

---

## Implementation checklist

### Core (`Sources/SwiftLogSmith/`) — additive, except `LogManager.log` (see "Found during pre-merge testing")

- [x] `Core/LogMessage.swift`: add `@objc public protocol LogPayload: Sendable {}`
- [x] `Core/LogMessage.swift`: add `public let payload: (any LogPayload)?`, extend internal init
- [x] `Core/LogManager.swift`: replace `fileId`/`function` with `String`, add `payload:` param
- [x] `Core/LogManager.swift`: refactor `extractTags` / `LogTagsExtractor.extract` to `String`
- [x] `LogSmith.swift`: ~~keep `StaticString` on all nine `log*` statics~~ — superseded: all nine now take `String`
      (see "Found during pre-merge testing")
- [x] `LogSmith.swift`: add one package-scoped funnel, `logInternal`, with `payload` + `String` source location;
      every `log*` facade routes through it (see "Found during pre-merge testing")
- [x] Confirm `LogMessage` still has **checked** `Sendable` (no `@unchecked` crept in)

### Manifests

- [x] `Package.swift`: swift-log dep, product, target, test target
- [x] `Package@swift-6.2.swift`: same
- [x] `Package@swift-6.0.swift` and `Package@swift-6.1.swift`: **unchanged**
- [x] `Package.resolved` regenerated by SwiftPM, not hand-edited

### Backend (`Sources/SwiftLogSmithBackend/`)

- [x] `LogSmithLogHandler.swift` — struct, implements `log(event:)`
- [x] Shared mode (default) → routes via `LogSmith.logInternal`
- [x] Isolated mode (opt-in) → user-owned `LogManager`
- [x] Metadata precedence: handler `metadata` < `metadataProvider` < per-call `event.metadata`
- [x] `subscript(metadataKey:)`, `metadata`, `logLevel`, `metadataProvider`
- [x] `SwiftLogPayload.swift` — final, checked Sendable, holds `label`/`LogEvent`/`resolvedMetadata` (`source` is read from `event.source`)
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
- [x] `swift test` — the existing 39 tests pass **unchanged** (necessary, but weaker evidence of
      additivity than it looks: none of them passes an explicit `StaticString`, so they cannot see the
      `LogManager.log` break — see "Found during pre-merge testing")
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
| **Rich core metadata** (`[String: String]` → structured) | Would break dictionary-literal ergonomics: swift-log keeps `["k": "v"]` compiling because `MetadataValue` is an *enum* conforming to `ExpressibleByStringLiteral`, which isn't ObjC-representable. An existential `any LogMetadataValue` cannot be expressed by a literal, so every call site would regress. Also breaks all nine `LogSmith.log*` statics plus `LogFormatter.addMetadataPart`'s closure type. Legitimate as its own major version, decided on core-library merit — not as a prerequisite for the bridge. When it lands, lift the nested collapse in `LogSmithLogHandler.flatten`; see "Metadata: a sorted default, and nested values collapsed per top-level key". |
| **`SwiftLogDestination: ILogger`** (LogSmith → swift-log) | The reverse direction. Would let `LogSmith.logE` reach existing swift-log handlers, but does not capture logs from libraries using swift-log, which is the actual goal here. |

---

## Deviations found during execution

### `LogManager.log` keeps `#fileID`/`#function`/`#line` defaults

The plan specified the new `String`-based parameters should have **no defaults**, so that calls
omitting them would unambiguously resolve to the `StaticString` variant. That reasoning was an
artifact of an earlier overload-based design that was abandoned in favour of straight replacement.

With only one `log` method there is nothing to disambiguate, and `#fileID`/`#function` work as
`String` defaults just as well as `StaticString` ones. Dropping the defaults would have broken
~20 existing `LogManagerTests` call sites and every direct `LogManager` user, for no benefit.

Kept the defaults. Result: all 39 existing tests pass with no test-file changes at all. (That is weaker
evidence of additivity than it first looked; see "Found during pre-merge testing".)

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

## Found during pre-merge testing

Written after the checklists above were ticked; where they disagree, this section wins.

### `fileId`/`function` are `String` everywhere — a source-breaking change

`fileId` and `function` now take `String` on `LogManager.log` and on all nine `LogSmith.log*` statics (they were
`StaticString`), and `LogManager.log` gained `payload:`. The nine statics gained it too (see "The logging statics take
a payload too"), and `swift package diagnose-api-breaking-changes v1.1.0 --products SwiftLogSmith` reports the two
changes together, so the allowlist entries for them are described there.

Defaults, `#fileID`/`#function` literals and string literals keep compiling, so most callers cannot tell. What breaks
is forwarding a `StaticString`: the documentation for every static says a wrapper author *should* pass the caller's
source information to these parameters, and a wrapper that does so with `StaticString` parameters no longer
compiles. The fix is to declare the wrapper's own parameters as `String` (callers of the wrapper are unaffected);
that migration line goes in the release notes. The existing tests could not see the break: none passes an explicit
`fileId`.

Why `String` everywhere rather than two overloads (measured, release build, filtered path): no performance
advantage is left — caller-side enqueue cost is identical (360 vs 363 ns), and end to end all-`String` is within
~2% of 1.1.0 while the previous mixed design (`StaticString` statics converting before the filter) was +34%. The
literal-only guarantee protects nothing here (`message` is already a `String`; the formatter escapes none of
`message`, `fileId` or `function`). A `StaticString`/`String` overload pair is ambiguous unless the `String`
overload has no defaults, and even then explicit literals silently pick `String`. One type removes the glue, matches
swift-log, and makes the statics callable from Objective-C.

**Versioning — decision: ship as 2.0.0.** A documented use (a wrapper forwarding `StaticString`) stops compiling,
which SemVer treats as an incompatible change. The library has few consumers (3 stars, 0 forks, no public
dependents found on GitHub), so a major bump costs almost nothing: `from: "1.x"` consumers stay on 1.1.0 until they
opt in with `from: "2.0.0"`, instead of hitting a compile error on a routine update. The README install snippet
already says `from: "2.0.0"`.

CI diffs against the latest release tag and ignores only what is listed in `.github/api-breakage-allowlist.txt`
(the file is parsed verbatim, so it cannot hold comments). Once `v2.0.0` is tagged it becomes the baseline and the
entries can be deleted.

**Objective-C:** none of `LogManager.log`, `LogSmith.log*` was visible to Objective-C in 1.1.0 — `StaticString` is
not representable and `@objcMembers` omits such members silently — so no Objective-C caller can be broken. They are
now visible (`+[LogSmith logE:metadata:payload:fileId:function:line:completion:]` and so on); Objective-C has no
default arguments, so callers pass the payload (`nil` for none), file, function and line explicitly.

### `LogType` and `LogLevel` are ordered by severity — the raw values changed

`LogManager` admits a message only if `logType.logLevel.rawValue >= minLogLevel.rawValue` **and**
`logType.rawValue >= minLogType.rawValue` (once manager-wide, once per logger). That is a severity filter only if
the raw values rise with severity, and for four `LogType` cases and two `LogLevel` cases they did not. `LogType` ran
`notice < info < debug < trace` at the low end, and `LogLevel` ran `default, info, debug, error, fault` (the order of
`OSLogType`'s constants), so `setMinimumLogType(.info)` silently dropped `.notice` and `setMinimumLogLevel(.debug)`
let warnings through while dropping info. The existing suite passes on either ordering — nothing in it discriminates
— which is how this went unnoticed.

Decision: **change the raw values**, so that one `>=` on the raw value stays the whole rule, rather than add a
parallel severity rank for the filter to use. 2.0.0 is a major release anyway, so the break costs nothing extra.

| | 1.1.0 | now |
|---|---|---|
| `LogType` | `notice` 1, `info` 2, `debug` 3, `trace` 4 | `trace` 1, `debug` 2, `info` 3, `notice` 4 |
| `LogLevel` | `undefined` −1, `default` 0, `info` 1, `debug` 2 | `all` 0, `debug` 1, `info` 2 |

Everything else keeps its value: `LogType` `undefined` −1, `none` 0, `warning` 5, `error` 6, `fault` 7, `critical` 8,
and `LogLevel` `error` 3, `fault` 4. The roll-up `LogType.logLevel` is now:

| `LogType` | `LogLevel` |
|---|---|
| `undefined`, `none` | `all` |
| `trace`, `debug` | `debug` |
| `info`, `notice` | `info` |
| `warning`, `error` | `error` |
| `fault`, `critical` | `fault` |

- **`LogLevel.default` is renamed `all`** and keeps raw value 0. Used as a minimum it never meant a level of its own,
  it meant "no minimum", which `all` says; it is also the level of logs that carry no severity. `all` is the usual
  name for the lowest threshold (`Level.ALL` in Log4j and java.util.logging), whereas `none` or `off` usually means
  the opposite: nothing passes.
- **`LogLevel.undefined` is removed.** Every log has a level, so there is nothing for it to describe;
  `LogType.undefined` and `.none` roll up to `.all`.
- **`LogType.notice` maps to `.info`** (it was `.default`). That keeps the roll-up monotone — the level never goes
  down as severity goes up, pinned by `testLogLevel_AsSeverityRises_ShouldNeverGoDown` — so a `LogLevel` minimum
  cuts at one of the same points as a `LogType` minimum, only more coarsely.

What a minimum now delivers. `warning`+ is `warning`, `error`, `fault` and `critical`; "and above" means every type
at least that severe in the order `trace < debug < info < notice < warning < error < fault < critical`.

| minimum | 1.1.0 | now |
|---|---|---|
| type `.trace` | `trace`, `warning`+ | `trace` and above |
| type `.debug` | `debug`, `trace`, `warning`+ | `debug` and above |
| type `.info` | `info`, `debug`, `trace`, `warning`+ | `info` and above |
| type `.notice` | `notice`, `info`, `debug`, `trace`, `warning`+ | `notice` and above |
| level `.debug` | `trace`, `debug`, `warning`+ | `trace` and above |
| level `.info` | `trace`, `debug`, `info`, `warning`+ | `info` and above |

Unchanged: the default minimums, type `.warning`/`.error`/`.fault`/`.critical` and level `.error`/`.fault`. A log of
type `.undefined` is still dropped by default, because it sorts below `.none`, the default type minimum. Delivering
one used to need all four minimums (manager and default logger, level and type) lowered, since its level was
`LogLevel.undefined`; now only the two type minimums need `.undefined`.

**`UserDefaults` overrides.** The per-manager and per-logger override keys are a runtime knob that the library only
reads; it never writes a raw value, so there is nothing to migrate. A value set by hand keeps its number, which now
names a different case for four types (`1` was `notice`, is now `trace`). The four reads did `LogType(rawValue:)!` and
`LogLevel(rawValue:)!`, which trap on a number that is not a case (observed with `99`: signal code 4) — independent of
this change, but the numbers just moved, and `LogLevel`'s `-1` stopped being a case. They now ignore such a value
and use the configured minimum.

**Objective-C.** `LogLevelDefault` is now `LogLevelAll` and `LogLevelUndefined` is gone. `LogTypeTrace`/`Debug`/
`Info`/`Notice` and `LogLevelInfo`/`Debug` keep their names but change value, so Objective-C code that stored or
compared the integers has to be reviewed; code that uses the constants just recompiles.

**API check.** `swift-api-digester` reports the added and removed `LogLevel` cases (3 of the allowlist's 45 entries)
but not changed raw values, so CI cannot catch them. `LogThresholdTests` pins them instead — the raw values,
the roll-up, every minimum and the override handling, each against an order written out by hand — and the release
notes must call them out.

**Bridge.** swift-log's seven levels map 1:1 onto `LogType`, and both sides now order severity the same way, so the
effective threshold of a bridged logger is simply the stricter of its `logLevel` and the LogSmith minimums. The
handler documentation and the README no longer warn about an inversion. Filtering on `logLevel` /
`defaultLogLevel` is still the better place, but because it is cheaper (swift-log skips the call, so the payload and
metadata are never built), not because it avoids a trap. `defaultLogLevel` still defaults to `.trace`.

**Release notes (2.0.0)**, alongside the `StaticString` → `String` migration above:

- `LogType` raw values changed: `trace` 1, `debug` 2, `info` 3, `notice` 4. `LogLevel` raw values changed: `debug` 1,
  `info` 2. Both now increase with severity.
- `LogLevel.default` is renamed `LogLevel.all`; `LogLevel.undefined` is removed (`LogType.undefined` and `.none` map to
  `.all`); `LogType.notice` now maps to `LogLevel.info`.
- Minimums are now severity thresholds (the table above). Code that set type `.trace`/`.debug`/`.info`/`.notice` or
  level `.debug`/`.info` will see different logs.
- A `UserDefaults` override that is not a valid raw value is ignored instead of crashing.

### Metadata: a sorted default, and nested values collapsed per top-level key

The README's swift-log example showed `"user": "[\"id\": \"7\"]"`, and a review comment asked whether the backslashes
were real. They were, and two separate things produced them:

- The bridge flattened a nested value with swift-log's own `MetadataValue.description`, which for a dictionary is
  `dict.mapValues { $0.description }.description`. It sorts nothing at any level, and from the second level down it
  escapes the quotes of the level below, because the inner string is a dictionary value of the outer one. Array
  items came out quoted.
- `LogFormatter.default` printed the whole `[String: String]` with `"\(metadata)"` (unchanged since 1.1.0). Swift's
  dictionary description escapes any quote or backslash inside a value and iterates in a different key order on every
  run. First-party values hit the same thing: a JSON value `{"a":1}` printed as `["body": "{\"a\":1}"]`.

Decisions:

1. **Default format: the same text as before, sorted by key** (`["code": "404", "user": "[id=7]"]`). It is built from
   `String(reflecting:)`, the call the standard library uses for each key and value of a dictionary description, so
   the escaping is identical (compared with the standard library over 225 key/value pairs) and only the order is
   stable now. `"\(dictionary)"` itself cannot be sorted, and `"\(dictionary.sorted { … })"` prints an array of
   labelled tuples. The closure is inline on the public `Builder.addMetadataPart`. The three private `LogPart`
   classes take every argument explicitly: they are only ever built by the Builder, which passes everything, so
   their own defaults were dead code and a second copy of this closure.
2. **Bridge: every top-level key stays an entry of its own; a nested dictionary or array collapses into the string
   value of its key.** `LogMessage.metadata` keeps the core's flat contract, and a metadata format still applies to
   each entry. The collapsed string is `[key=value, key=value]`, sorted by key at every depth, with arrays as
   `[item, item]` in their own order and nothing quoted, so the default formatter has nothing to escape when it
   prints it as a value. `description` is not used. `SwiftLogPayload.resolvedMetadata` still carries the untouched
   tree. For example `code: 404, tags: [a, b], user: {id: 7, address: {city: X, zip: 1}}` arrives as
   `["code": "404", "tags": "[a, b]", "user": "[address=[city=X, zip=1], id=7]"]`.

Tried and dropped on the way:

- **A `[key=value, …]` default in the formatter.** It changed every user's log line, and it could not help the second
  level anyway: the formatter only receives strings, so a string already built with escapes and a random order is
  beyond it.
- **Rendering the whole line's worth of metadata in the bridge, top level included.** Presentation would then be
  decided before a metadata format ever saw it, so a custom `addMetadataPart(format:)` could not restyle or filter
  anything. Only the nested part is collapsed; the top level stays entries.
- **Dotted keys** (`user.address.city`, `tags.0`). This is the formatter-neutral answer: every leaf becomes an entry,
  so a custom format can restyle, filter or redact nested keys (a format that hides keys containing "password" works
  on `user.password`, but cannot see inside `user=[…, password=…]`). Not taken because the `user` entry disappears
  from the metadata and the keys would change again once core metadata can nest; the collapse keeps the top-level
  keys stable and lives in one function.

Accepted limitation: a metadata format sees a nested value as one string and cannot restyle or filter inside it.
Loggers that need the structure read `SwiftLogPayload.resolvedMetadata`. A value that itself contains `", "` or
`"="` is ambiguous inside the unquoted string. Values with quotes are escaped as in any dictionary description, as
they were in 1.1.0.

**Lifting it later.** When core metadata can nest (see "Deliberately deferred"), stop collapsing:
`LogSmithLogHandler.flatten` passes the nested values through and keeps the keys. The top-level keys do not change,
so `metadata["user"]` keeps working and only the type of its value does.

**Cost** (release build, one Intel Mac, medians). `flatten` runs on the caller's thread, once for every statement that
passes swift-log's level check; a statement below the logger's `logLevel` never reaches it. Flat metadata costs what
swift-log's `description` cost (about 250 ns for 5 entries). Nested metadata is about twice as fast (the two-level
README example: 2.2 µs against 5.0 µs). The whole bridge call on the caller's thread is 5.3 µs with 5 flat entries
and 9.1 µs with the two-level example, so `flatten` is about 5% of it for flat metadata and 16–32% for nested. A
variant that renders into one output buffer was 22–32% faster on nested metadata, which is 5–10% of the whole call;
not adopted.

Tests. Default format: the sort order, empty metadata, the same text as printing the dictionary for single-entry
dictionaries holding quotes, backslashes, newlines and emoji, and independence from insertion order (the same 30
entries inserted in opposite orders). Bridge: the agreed shape (top-level keys kept, nested collapsed), second-level
and mixed nesting, empty containers and convertible values, insertion-order independence of nested dictionaries, a
custom `addMetadataPart(format:)` restyling each top-level entry and seeing a nested value as one string, and two
whole lines through the default formatter (the README example and a second-level one, asserting that no backslash
appears). Restoring `"\(metadata)"`, dropping the sort, the brackets or the space, not escaping, sorting descending,
going back to `description`, not recursing, quoting nested values, sorting arrays, collapsing the whole top level,
dropping nested values, or switching to dotted keys each fails at least one of them.

Release note (2.0.0): the default metadata text is unchanged apart from being sorted by key; it used to vary from run
to run. Nested swift-log metadata arrives in `LogMessage.metadata` as one unquoted `[key=value]` string per
top-level key, where it used to be swift-log's `description`; the original stays on
`SwiftLogPayload.resolvedMetadata`.

### The bridge entry point is `LogSmith.logInternal`, package-scoped

It was a public `LogSmith.log(_:logType:metadata:payload:…)`, which shared its name with the level-less
`LogSmith.log(_:metadata:…)` facade and differed from it only by a label (review feedback). It is now
`logInternal` with `package` access: the backend, a separate module in the same package, can call it, while a
consumer package cannot (`'logInternal' is inaccessible due to 'package' protection level`). `internal` would not
have worked, because the backend is a different module. It is absent from the public documentation and the
Objective-C header, and being new in this release it has no effect on the API check.

All nine `log*` facades now delegate to it, so the hop onto `LogSmith`'s queue exists once and the first-party
facades and the backend share the exact same path. Its `fileId`/`function`/`line` parameters have no defaults, so
a caller cannot log its own location by accident. A release-build benchmark shows no difference from the previous
shape beyond run-to-run noise.

### The logging statics take a payload too

`logInternal` and `LogManager.log` take an optional `payload`, and the nine `LogSmith` statics are the public facade
over them, so they take it as well: `payload: (any LogPayload)? = nil`, after `metadata` and before the source
location, the order `logInternal` and `LogManager.log` use. Structured context is then not a bridge-only feature: any
first-party caller or wrapper can attach a `LogPayload`, and any `ILogger` reads it back with a conditional cast.

Every call that compiled still compiles (the parameter defaults to `nil` and `completion` stays last, so trailing
closures are unaffected). Objective-C callers, for whom the selectors are new in this release, pass `nil`; the
generated header shows `payload:(id <LogPayload> _Nullable)` on all nine, and `logInternal` is still absent from it.

The API digester matches each new signature to the old one by position, so inserting a parameter in the middle is
reported as a rename plus shifted parameter-type changes. The allowlist therefore holds 45 entries: for each of
`logT` … `logF` four parameter-type changes and one rename (40), `LogSmith.log` removed, `LogManager.log` removed,
and the 3 `LogLevel` entries. They are mechanical, and are deleted once `v2.0.0` is tagged and becomes the baseline.

Tests: each of the nine statics delivers the very same payload instance and none invents one when it is omitted;
payload, metadata and an explicit call site arrive together through a facade; and `PublicAPICompileTests` calls the
statics with a payload from outside the module. Making any single static drop its payload fails a test that names
the type it logs at.

### swift-log lower bound is 1.12.0, not 1.11.0

The handler reads `LogEvent.error`, which first shipped in swift-log 1.12.0; the backend does not compile against
1.11.0. `Package.resolved` pins 1.15.0, which hid this. Both manifests now say `from: "1.12.0"`, and a CI job
builds and tests at whatever lower bound `Package.swift` declares.

### Handler-level metadata was dropped on statements with no metadata of their own

`resolveMetadata` returned `nil` when a statement carried nothing beyond the handler's baseline, and
`log(event:)` flattened `nil` to `[:]`, so `logger[metadataKey: "request-id"] = ...` followed by a plain
`logger.info(...)` delivered no `request-id`. swift-log's `StreamLogHandler` has the same fast path but falls
back to its stored baseline. `resolveMetadata` no longer returns an optional: it always returns the merged
metadata (the baseline when the statement adds nothing, empty when there is none), and
`SwiftLogPayload.resolvedMetadata` is non-optional to match.

### CI covered two of the four manifests

macos-15's Xcode 16.4 is Swift 6.1.2, so the job selected `Package@swift-6.1.swift`, not the 6.0 manifest its
comment claimed; macos-26 selected `Package.swift`. `Package@swift-6.2.swift` — the manifest every Swift 6.2
consumer of the backend gets — was never built. CI now has a Swift 6.2 leg (Xcode pinned, toolchain asserted).
`Package@swift-6.0.swift` is deliberately left unexercised.

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
