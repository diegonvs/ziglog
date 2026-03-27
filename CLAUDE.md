# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`ziglog` is a CLI tool for ingesting, searching, and streaming logs, built in Zig. The MVP exposes three commands:

```bash
node app.js | ziglog start   # ingest logs from stdin
ziglog find error            # search logs by text
ziglog tail                  # stream logs in real time
```

Logs are stored as append-only JSONL files.

## Build & Run

```bash
zig build              # compile the project
zig build run          # build and run
zig build test         # run all tests
zig build test -- --filter "test name"  # run a single test
```

Binary produced at `zig-out/bin/ziglog`.

## Architecture

```
CLI (main.zig) → parser.zig
                     │
         ┌───────────┼───────────┐
         │           │           │
      ingest       query        tail
  stdin_reader   search.zig   tailer.zig
         │           │           │
         └─────┬─────┴─────┬─────┘
               │           │
          storage/      formatter/
      writer+reader      pretty.zig
```

- `src/main.zig` — entry point; routes subcommands to modules
- `src/cli/parser.zig` — parses argv into a tagged union of commands
- `src/ingest/stdin_reader.zig` — reads lines from stdin, wraps in JSON, delegates to storage writer
- `src/storage/writer.zig` / `reader.zig` — append-only JSONL log file operations
- `src/query/search.zig` — reads storage and filters by substring match
- `src/tail/tailer.zig` — watches the log file and streams new entries
- `src/formatter/pretty.zig` — formats log entries with ANSI colors for terminal output

## Zig conventions used in this project

- Allocator is passed explicitly; the general-purpose allocator (`std.heap.GeneralPurposeAllocator`) is initialized in `main.zig` and threaded down.
- Errors are propagated with `!` return types; no silent ignoring.
- Module files are imported with `@import("../module/file.zig")`.
