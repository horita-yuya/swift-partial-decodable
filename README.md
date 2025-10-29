# swift-partial-decodable

Incremental JSON parsing for Swift. Decode JSON objects as data streams in, getting partial results before the entire payload arrives.

## Usage

### With String Chunks

```swift
import PartialDecodable

struct User: Decodable {
    var name: String?
    var email: String?
}

// Create a stream of JSON chunks (simulating network packets)
// Chunks can be split anywhere - even in the middle of keys or values
let chunks = AsyncStream<String> { continuation in
    continuation.yield(#"{"na"#)           // Incomplete key
    continuation.yield(#"me":"Alice","em"#) // Complete first field, incomplete key
    continuation.yield(#"ail":"alice@example.com"}"#)
    continuation.finish()
}

// Decode incrementally - emits after each meaningful update
for try await user in incrementalDecode(User.self, from: chunks) {
    print(user)
    // First:  User(name: nil, email: nil)
    // Second: User(name: "Alice", email: nil)
    // Third:  User(name: "Alice", email: "alice@example.com")
}
```

### With URLSession (Byte Streams)

```swift
import PartialDecodable

struct Response: Decodable {
    var content: Content?
}

struct Content: Decodable {
    var text: String?
}

// Stream JSON from a URL
let url = URL(string: "https://api.example.com/stream")!
let (bytes, _) = try await URLSession.shared.bytes(from: url)

// Decode character by character as bytes arrive
for try await response in incrementalDecode(Response.self, from: bytes) {
    print(response.content?.text ?? "")
    // Updates as each character is received
}
```

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yuyahorita/swift-partial-decodable.git", from: "0.0.1")
]
```
