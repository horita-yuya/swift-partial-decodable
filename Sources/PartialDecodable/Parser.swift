import Foundation

public enum JsonValue: Equatable {
    case null
    case boolean(Bool)
    case number(Double)
    case string(String)
    case array([JsonValue])
    case object([String: JsonValue])

    public static func == (lhs: JsonValue, rhs: JsonValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null):
            return true
        case (.boolean(let l), .boolean(let r)):
            return l == r
        case (.number(let l), .number(let r)):
            return l == r
        case (.string(let l), .string(let r)):
            return l == r
        case (.array(let l), .array(let r)):
            return l == r
        case (.object(let l), .object(let r)):
            return l == r
        default:
            return false
        }
    }

    public func toJSONData() throws -> Data {
        return try JSONSerialization.data(withJSONObject: toAny(), options: [])
    }

    private func toAny() -> Any {
        switch self {
        case .null:
            return NSNull()
        case .boolean(let value):
            return value
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .array(let items):
            return items.map { $0.toAny() }
        case .object(let properties):
            return properties.mapValues { $0.toAny() }
        }
    }
}

private enum StateEnum {
    case initial
    case inString
    case inArray
    case inObjectExpectingKey
    case inObjectExpectingValue
}

private enum ParserState {
    case initial
    case inString(value: String)
    case inArray(value: JsonArray)
    case inObjectExpectingKey(prevKey: String?, object: JsonObject)
    case inObjectExpectingValue(key: String, object: JsonObject)

    var stateEnum: StateEnum {
        switch self {
        case .initial: return .initial
        case .inString: return .inString
        case .inArray: return .inArray
        case .inObjectExpectingKey: return .inObjectExpectingKey
        case .inObjectExpectingValue: return .inObjectExpectingValue
        }
    }
}

private class JsonArray {
    var items: [JsonValue] = []

    func append(_ value: JsonValue) {
        items.append(value)
    }

    func updateLast(_ value: JsonValue) {
        if !items.isEmpty {
            items[items.count - 1] = value
        }
    }

    var lastIndex: Int? {
        items.isEmpty ? nil : items.count - 1
    }

    func toJsonValue() -> JsonValue {
        return .array(items)
    }
}

private class JsonObject {
    var properties: [String: JsonValue] = [:]
    var keys: [String] = []

    func set(key: String, value: JsonValue) {
        if key == "__proto__" {
            properties[key] = value
        } else {
            if properties[key] == nil {
                keys.append(key)
            }
            properties[key] = value
        }
    }

    func toJsonValue() -> JsonValue {
        return .object(properties)
    }
}

public class Parser: TokenHandler {
    private var stateStack: [ParserState] = [.initial]
    private var toplevelValue: JsonValue?
    private var toplevelContainer: Any?
    private var tokenizer: Tokenizer!
    private var finished = false
    private var progressed = false

    public init<S: AsyncSequence>(_ stream: S) where S.Element == String {
        self.tokenizer = Tokenizer(stream, handler: self)
    }

    private func updateToplevelValue() {
        rebuildNestedContainers()

        if let arr = toplevelContainer as? JsonArray {
            toplevelValue = arr.toJsonValue()
        } else if let obj = toplevelContainer as? JsonObject {
            toplevelValue = obj.toJsonValue()
        }
    }

    private func rebuildNestedContainers() {
        for i in stride(from: stateStack.count - 1, through: 0, by: -1) {
            guard i > 0 else { break }

            let parentState = stateStack[i - 1]
            let currentState = stateStack[i]

            switch currentState {
            case .inArray(let arr):
                switch parentState {
                case .inArray(let parentArr):
                    parentArr.updateLast(arr.toJsonValue())

                case .inObjectExpectingValue(let key, let parentObj):
                    parentObj.set(key: key, value: arr.toJsonValue())

                case .inObjectExpectingKey(let key?, let parentObj):
                    parentObj.set(key: key, value: arr.toJsonValue())

                default:
                    break
                }

            case .inObjectExpectingKey(_, let obj),
                 .inObjectExpectingValue(_, let obj):
                switch parentState {
                case .inArray(let parentArr):
                    parentArr.updateLast(obj.toJsonValue())

                case .inObjectExpectingValue(let key, let parentObj):
                    parentObj.set(key: key, value: obj.toJsonValue())

                case .inObjectExpectingKey(let key?, let parentObj):
                    parentObj.set(key: key, value: obj.toJsonValue())

                default:
                    break
                }

            default:
                break
            }
        }
    }

    public func next() async throws -> JsonValue? {
        if finished {
            return nil
        }

        while true {
            progressed = false
            try await tokenizer.pump()

            guard let value = toplevelValue else {
                throw JSONError.internalError("toplevelValue should not be nil after at least one call to pump()")
            }

            if progressed {
                return value
            }

            if stateStack.isEmpty {
                try await tokenizer.pump()
                finished = true
                return value
            }
        }
    }

    public func handleNull() {
        handleValueToken(type: .null, value: nil)
    }

    public func handleBoolean(_ value: Bool) {
        handleValueToken(type: .boolean, value: value)
    }

    public func handleNumber(_ value: Double) {
        handleValueToken(type: .number, value: value)
    }

    public func handleStringStart() {
        let state = currentState()
        if !progressed && state.stateEnum != .inObjectExpectingKey {
            progressed = true
        }

        switch state {
        case .initial:
            stateStack.removeLast()
            toplevelValue = progressValue(type: .stringStart, value: nil)

        case .inArray(let arr):
            let v = progressValue(type: .stringStart, value: nil)
            arr.append(v)
            updateToplevelValue()

        case .inObjectExpectingKey:
            stateStack.append(.inString(value: ""))

        case .inObjectExpectingValue(let key, let object):
            let sv = progressValue(type: .stringStart, value: nil)
            object.set(key: key, value: sv)
            updateToplevelValue()

        case .inString:
            fatalError("Unexpected string start token in the middle of string")
        }
    }

    public func handleStringMiddle(_ value: String) {
        guard case .inString(let currentValue) = currentState() else {
            fatalError("Unexpected string middle token")
        }

        if !progressed {
            if stateStack.count >= 2 {
                let prev = stateStack[stateStack.count - 2]
                if prev.stateEnum != .inObjectExpectingKey {
                    progressed = true
                }
            }
        }

        let newValue = currentValue + value
        stateStack[stateStack.count - 1] = .inString(value: newValue)

        let parentState = stateStack.count >= 2 ? stateStack[stateStack.count - 2] : nil
        updateStringParent(updated: newValue, parentState: parentState)
    }

    public func handleStringEnd() {
        guard case .inString(let value) = currentState() else {
            fatalError("Unexpected string end token")
        }

        stateStack.removeLast()
        let parentState = stateStack.last
        updateStringParent(updated: value, parentState: parentState)
    }

    public func handleArrayStart() {
        handleValueToken(type: .arrayStart, value: nil)
    }

    public func handleArrayEnd() {
        guard case .inArray = currentState() else {
            fatalError("Unexpected array end token")
        }
        stateStack.removeLast()
    }

    public func handleObjectStart() {
        handleValueToken(type: .objectStart, value: nil)
    }

    public func handleObjectEnd() {
        let state = currentState()
        switch state.stateEnum {
        case .inObjectExpectingKey, .inObjectExpectingValue:
            stateStack.removeLast()
        default:
            fatalError("Unexpected object end token")
        }
    }

    private func currentState() -> ParserState {
        guard let state = stateStack.last else {
            fatalError("Unexpected trailing input")
        }
        return state
    }

    private func handleValueToken(type: JsonTokenType, value: Any?) {
        let state = currentState()
        if !progressed {
            progressed = true
        }

        switch state {
        case .initial:
            stateStack.removeLast()
            toplevelValue = progressValue(type: type, value: value)

        case .inArray(let arr):
            let v = progressValue(type: type, value: value)
            arr.append(v)
            updateToplevelValue()

        case .inObjectExpectingValue(let key, let object):
            if type != .stringStart {
                stateStack.removeLast()
                stateStack.append(.inObjectExpectingKey(prevKey: key, object: object))
            }
            let v = progressValue(type: type, value: value)
            object.set(key: key, value: v)
            updateToplevelValue()

        case .inString:
            fatalError("Unexpected value token in the middle of string")

        case .inObjectExpectingKey:
            fatalError("Unexpected value token in the middle of object expecting key")
        }
    }

    private func updateStringParent(updated: String, parentState: ParserState?) {
        guard let parentState = parentState else {
            toplevelValue = .string(updated)
            return
        }

        switch parentState {
        case .inArray(let arr):
            arr.updateLast(.string(updated))
            updateToplevelValue()

        case .inObjectExpectingValue(let key, let object):
            object.set(key: key, value: .string(updated))
            updateToplevelValue()
            if case .inObjectExpectingValue = stateStack.last {
                stateStack.removeLast()
                stateStack.append(.inObjectExpectingKey(prevKey: key, object: object))
            }

        case .inObjectExpectingKey(_, let object):
            if case .inObjectExpectingKey = stateStack.last {
                stateStack.removeLast()
                stateStack.append(.inObjectExpectingValue(key: updated, object: object))
            }

        default:
            fatalError("Unexpected parent state for string: \(parentState.stateEnum)")
        }
    }

    private func progressValue(type: JsonTokenType, value: Any?) -> JsonValue {
        switch type {
        case .null:
            return .null

        case .boolean:
            return .boolean(value as! Bool)

        case .number:
            return .number(value as! Double)

        case .stringStart:
            stateStack.append(.inString(value: ""))
            return .string("")

        case .arrayStart:
            let arr = JsonArray()
            stateStack.append(.inArray(value: arr))
            if stateStack.count == 1 {
                toplevelContainer = arr
            }
            return arr.toJsonValue()

        case .objectStart:
            let obj = JsonObject()
            stateStack.append(.inObjectExpectingKey(prevKey: nil, object: obj))
            if stateStack.count == 1 {
                toplevelContainer = obj
            }
            return obj.toJsonValue()

        default:
            fatalError("Unexpected token type: \(type.description)")
        }
    }
}

public struct IncrementalJSONParser<S: AsyncSequence>: AsyncSequence where S.Element == String {
    public typealias Element = JsonValue

    private let stream: S

    public init(_ stream: S) {
        self.stream = stream
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private let parser: Parser

        init(_ parser: Parser) {
            self.parser = parser
        }

        public mutating func next() async throws -> JsonValue? {
            return try await parser.next()
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        return AsyncIterator(Parser(stream))
    }
}

public func parse<S: AsyncSequence>(_ stream: S) -> IncrementalJSONParser<S> where S.Element == String {
    return IncrementalJSONParser(stream)
}
