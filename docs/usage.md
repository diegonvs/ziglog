# Usage guide

## Quick start

```bash
# 1. Build
zig build

# 2. Start capturing logs from a program
node app.js | ./zig-out/bin/ziglog start

# 3. In another terminal, search logs
./zig-out/bin/ziglog find error

# 4. Or watch new entries live
./zig-out/bin/ziglog tail
```

## Commands

### `start`

Reads lines from stdin and appends each one as a timestamped JSON entry to `ziglog.jsonl`.

```bash
<some-program> | ziglog start
```

- Each line becomes one entry: `{"ts":<unix seconds>,"msg":"<line>"}`
- The log file is created automatically if it does not exist
- The file is never truncated — each run appends to the existing file
- Press `Ctrl+C` to stop ingestion

**Example:**

```bash
while true; do echo "heartbeat $(date)"; sleep 1; done | ziglog start
```

### `find <query>`

Searches `ziglog.jsonl` for entries whose message contains `<query>` (case-sensitive).

```bash
ziglog find error
ziglog find "connection refused"
ziglog find warn
```

Output is formatted with ANSI colors and a human-readable `[HH:MM:SS]` timestamp (UTC). Color coding:

| Color       | Keywords detected (case-insensitive)     |
|-------------|------------------------------------------|
| Bold red    | `error`, `fatal`, `panic`                |
| Yellow      | `warn`                                   |
| Green       | `info`, `start`, `ready`                 |
| Default     | anything else                            |

If no entries match, a warning is printed and the exit code is 0.

If the log file does not exist yet, a hint is shown to run `ziglog start` first.

### `tail`

Watches `ziglog.jsonl` and prints new entries in real time as they are appended.

```bash
ziglog tail
```

- Starts at the **current end** of the file — existing entries are not replayed
- Uses kernel-native file watching (kqueue on macOS, inotify on Linux) for minimal CPU usage
- Press `Ctrl+C` to stop

If the log file does not exist yet, a hint is shown to run `ziglog start` first.

## Log file format

`ziglog.jsonl` is a plain text file in [JSONL](https://jsonlines.org/) format — one JSON object per line:

```
{"ts":1711900800,"msg":"server started on port 3000"}
{"ts":1711900801,"msg":"warn: high memory usage"}
{"ts":1711900802,"msg":"error: connection refused"}
```

Fields:

| Field | Type   | Description                    |
|-------|--------|--------------------------------|
| `ts`  | number | Unix timestamp (seconds, UTC)  |
| `msg` | string | The original log line          |

Because it is plain JSONL, you can process it with standard tools:

```bash
# count error entries
grep '"error' ziglog.jsonl | wc -l

# pretty-print all entries with jq
cat ziglog.jsonl | jq .

# extract just messages
cat ziglog.jsonl | jq -r '.msg'
```

## Error messages

| Message | Cause | Fix |
|---|---|---|
| `No logs found. Use 'ziglog start' first.` | `ziglog.jsonl` does not exist | Run `ziglog start` to create it |
| `No results for '<query>'.` | No entries matched the query | Try a different search term |
| `Unknown command. Use: start, find, tail` | Unrecognised subcommand | Check the spelling |
| `Missing argument. Usage: ziglog find <query>` | `find` called without a query | Add the search term |
