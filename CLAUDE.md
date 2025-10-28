# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Swift package that provides incremental JSON parsing capabilities for streaming data. The library enables decoding JSON objects incrementally as data arrives in chunks, emitting intermediate partial results before the entire JSON payload is complete.

## Core Architecture

The library is built on a two-layer architecture:

### Layer 1: Tokenizer (Tokenizer.swift)

The `Tokenizer` class is a low-level streaming JSON tokenizer that:
- Processes an `AsyncSequence<String>` input stream chunk by chunk
- Maintains an internal state machine (`TokenizerState`) to track parsing progress
- Uses the `Input` helper class to buffer incoming chunks and manage lookahead
- Emits tokens via the `TokenHandler` protocol as JSON elements are recognized
- Supports backpressure through the `pump()` method that processes until at least one token is emitted

Key token types include:
- Primitive values: `null`, `boolean`, `number`
- String boundaries: `stringStart`, `stringMiddle`, `stringEnd` (strings are streamed in parts)
- Container boundaries: `arrayStart`, `arrayEnd`, `objectStart`, `objectEnd`

The tokenizer handles:
- JSON escape sequences (`\n`, `\t`, `\uXXXX`, etc.)
- Number validation using regex
- Whitespace skipping
- Chunked input buffering

### Layer 2: Parser (Parser.swift)

The `Parser` class builds on the tokenizer by:
- Implementing `TokenHandler` to receive tokens
- Building a `JsonValue` AST incrementally using internal `JsonArray` and `JsonObject` containers
- Maintaining a state stack (`ParserState`) to track nested structures
- Emitting partial results after each meaningful progress via the `next()` async method
- Rebuilding nested containers on each update to provide snapshots of the current state

The parser emits intermediate values for:
- Each new array element added
- Each new object property set or value updated
- Each chunk of a streaming string

### Public API: IncrementalJSONParser

The `IncrementalJSONParser` struct provides the user-facing API:
- Conforms to `AsyncSequence` for easy iteration with `for try await`
- Supports two modes:
  1. Raw `JsonValue` parsing: `IncrementalJSONParser(_ stream: S) where T == JsonValue`
  2. Decodable decoding: `IncrementalJSONParser(_ stream: S, decoder: JSONDecoder = JSONDecoder()) where T: Decodable`
- Convenience function: `incrementalDecode(_:from:decoder:)` for Decodable types

## Common Commands

### Build the package
```bash
swift build
```

### Run tests
```bash
swift test
```

### Run a specific test
```bash
swift test --filter <test-name>
```

For example:
```bash
swift test --filter testSimpleObject
swift test --filter TokenizerStreamTests
```

### Clean build artifacts
```bash
swift package clean
```

## Development Notes

### Platform Requirements
- Minimum Swift version: 6.2
- Minimum platform versions:
  - iOS 18
  - macOS 15
  - tvOS 18
  - watchOS 11
  - visionOS 2

### Test Structure
- Tokenizer tests: `Tests/PartialDecodableTests/TokenizerStreamTests.swift`
  - Tests the low-level token emission with a `TestTokenHandler`
  - Tests chunked input processing
- Parser tests: `Tests/PartialDecodableTests/ParserIncrementalTests.swift`
  - Tests incremental decoding with the `incrementalDecode` API
  - Tests both `JsonValue` and `Decodable` decoding paths
  - Verifies intermediate results match expected progression

### Key Implementation Details

1. **String Streaming**: Strings are emitted as `stringStart`, multiple `stringMiddle` tokens, then `stringEnd`. This allows very long strings to be processed incrementally.

2. **Progress Tracking**: The `Parser` uses a `progressed` flag to determine when to emit a new value. Progress occurs when:
   - A value token is handled (except in object key position)
   - A string starts (except in object key position)
   - String content accumulates (except in object key position)

3. **Container Rebuilding**: When nested structures are updated, `rebuildNestedContainers()` walks the state stack to update parent containers with the latest child values.

4. **Buffer Management**: The `Input` class manages buffering with:
   - A sliding window that commits consumed data via `commit()`
   - Automatic buffer expansion via `tryToExpandBuffer()` when more data is needed
   - Lookahead support via `peek()` for multi-character sequences

5. **State Machines**: Both tokenizer and parser use explicit state enums to track progress through JSON structures, enabling incremental processing and resumption.
