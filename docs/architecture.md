# Architecture

`ziglog` is structured as a set of small, focused modules wired together by `main.zig`.

## Module map

```
src/
├── main.zig                  Entry point — allocator setup, arg parsing, command dispatch
├── cli/
│   └── parser.zig            Parses argv into a typed Command union
├── ingest/
│   └── stdin_reader.zig      Reads stdin line by line, delegates to storage writer
├── storage/
│   └── writer.zig            Append-only JSONL writer
├── query/
│   └── search.zig            Substring search over stored JSONL entries
├── tail/
│   └── tailer.zig            Reactive file watcher — streams new entries as they arrive
└── formatter/
    └── pretty.zig            ANSI-colored terminal output; shared LogEntry type
```

## Data flow

### `ziglog start`

```
stdin
  └─► stdin_reader.run()
        └─► LogWriter.writeEntry()   serialize to JSON + append newline
              └─► ziglog.jsonl
```

### `ziglog find <query>`

```
ziglog.jsonl
  └─► search.run()
        ├─► parse each JSONL line → LogEntry
        ├─► matches()             substring filter (case-sensitive)
        └─► pretty.print()        ANSI output to stdout
```

### `ziglog tail`

```
ziglog.jsonl
  └─► tailer.run()
        ├─► seek to end of file (skip history)
        ├─► watchKqueue()    macOS/BSD — blocks on kernel event (EVFILT_VNODE + NOTE_WRITE)
        │   watchInotify()   Linux    — blocks on inotify IN.MODIFY
        │   watchPoll()      fallback — polls every 250ms
        └─► readNew()        reads bytes since last position → pretty.print()
```

## Key design decisions

### Append-only JSONL storage

Each log entry is a single JSON object on its own line. This format is easy to inspect with standard tools (`jq`, `grep`, etc.), trivially appendable, and requires no parsing of prior content to write a new entry.

### Explicit allocator threading

Zig has no global allocator. `main.zig` initializes a `GeneralPurposeAllocator` and passes it down to every function that allocates. This makes memory ownership explicit and allows the GPA to detect leaks on exit.

### Testable I/O with `countMatches`

`search.run()` prints directly to stdout, which is hard to assert in tests. The `countMatches` function exposes the same logic as a pure `!usize` return value, making it testable without capturing stdout. This pattern is used wherever testability would otherwise require I/O interception.

### Reactive tail without polling

`tailer.zig` uses OS-native event APIs instead of a sleep loop:

| Platform     | Mechanism   | How it works                                      |
|--------------|-------------|---------------------------------------------------|
| macOS / BSD  | kqueue      | `EVFILT_VNODE` + `NOTE_WRITE` blocks until write  |
| Linux        | inotify     | `IN.MODIFY` event read blocks until file changes  |
| Other        | polling     | `getEndPos` + `Thread.sleep(250ms)` fallback      |

The selection is done at **compile time** via `builtin.os.tag`, so non-applicable branches are fully eliminated by the compiler.

### Zig 0.15 I/O API

Zig 0.15 replaced `std.io.bufferedReader` with a buffer-owning reader API. All file reading uses:

```zig
var buf: [65536]u8 = undefined;
var reader = file.readerStreaming(&buf);
while (try reader.interface.takeDelimiter('\n')) |line| { ... }
```

The buffer is stack-allocated; the reader methods live on `reader.interface` (type `std.Io.Reader`).
