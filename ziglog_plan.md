# 🧰 ziglog

A simple, fast, and developer-friendly CLI tool for ingesting, searching, and streaming logs — built with Zig.

---

## 🎯 Goal

Provide a lightweight alternative to traditional logging tools by focusing on:

- Simplicity
- Performance
- Great CLI experience
- Real-world usefulness for developers

---

## 🧱 Architecture Overview

```
            ┌───────────────┐
            │   CLI (zig)   │
            └──────┬────────┘
                   │
     ┌─────────────┼─────────────┐
     │             │             │
  ingest        query         tail
 (stdin/http)  (search)     (stream)
     │             │             │
     └───────┬─────┴─────┬───────┘
             │           │
        storage      formatter
         (file)        (output)
```

---

## 📁 Project Structure

```
ziglog/
  src/
    main.zig

    cli/
      parser.zig

    ingest/
      stdin_reader.zig

    storage/
      writer.zig
      reader.zig

    query/
      search.zig

    tail/
      tailer.zig

    formatter/
      pretty.zig
```

---

## 🧩 Core Modules

### CLI
Handles command parsing and routing.

### Ingest
Reads logs from stdin.

### Storage
Append-only JSONL file.

### Query
Search logs by text.

### Tail
Stream logs in real time.

### Formatter
Pretty output with colors.

---

## 🚀 MVP

```bash
node app.js | ziglog start
ziglog find error
ziglog tail
```
