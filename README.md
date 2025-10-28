# swift-partial-decodable

Incremental JSON parsing for Swift. Decode JSON objects as data streams in, getting partial results before the entire payload arrives.

## Usage

```swift
import PartialDecodable

struct User: Decodable {
    var name: String?
    var email: String?
}

// Create a stream of JSON chunks
let chunks = AsyncStream<String> { continuation in
    continuation.yield(#"{"name":"#)
    continuation.yield(#""Alice","#)
    continuation.yield(#""email":"alice@example.com"}"#)
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

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yuyahorita/swift-partial-decodable.git", from: "1.0.0")
]
```
