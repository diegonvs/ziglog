# ziglog

A lightweight CLI tool for ingesting, searching, and streaming logs, built in Zig.

Logs are stored as append-only [JSONL](https://jsonlines.org/) files, making them easy to inspect, archive, or process with other tools.

## Installation

**Requirements:** Zig 0.15.2

```bash
git clone https://github.com/diegonvs/ziglog.git
cd ziglog
zig build
```

The binary is produced at `zig-out/bin/ziglog`. Add it to your `PATH` or invoke it directly.

## Usage

### `ziglog start` — ingest logs from stdin

Pipe any program's output into `ziglog start` to capture it as structured logs:

```bash
node app.js | ziglog start
```

Each line from stdin is stored as a JSON entry with a Unix timestamp:

```json
{"ts":1711900800,"msg":"server started on port 3000"}
{"ts":1711900802,"msg":"error: connection refused"}
```

### `ziglog find <query>` — search logs by text

Filter stored logs by a substring (case-sensitive):

```bash
ziglog find error
ziglog find "connection refused"
```

Matching entries are printed with ANSI colors and human-readable timestamps:

```
[14:00:02] error: connection refused
```

### `ziglog tail` — stream new log entries in real time

Watch the log file and print new entries as they arrive (similar to `tail -f`):

```bash
ziglog tail
```

Uses kernel-native file watching (kqueue on macOS, inotify on Linux) with a polling fallback for other systems.

## Log file

Logs are stored in `ziglog.jsonl` in the current working directory. Each line is a self-contained JSON object:

```
{"ts":1711900800,"msg":"server started on port 3000"}
{"ts":1711900801,"msg":"warn: high memory usage"}
{"ts":1711900802,"msg":"error: connection refused"}
```

The file grows only by appending — existing entries are never modified.

## Development

```bash
zig build test                               # run all tests
zig build test -- --filter "test name"       # run a single test
```

See [docs/architecture.md](docs/architecture.md) for a detailed breakdown of the codebase.
