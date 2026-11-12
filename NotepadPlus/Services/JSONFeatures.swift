import Foundation

/// Lightweight JSONPath evaluator intended for editor-sized queries. It parses
/// the document once, then walks only the requested path (no regex over source).
struct JSONPathMatch: Identifiable {
    let id = UUID()
    let path: String
    let value: Any
}

enum JSONPathEngine {
    enum Segment: Equatable { case key(String), index(Int), wildcard }

    static func query(_ source: String, path: String) throws -> [JSONPathMatch] {
        guard let data = source.data(using: .utf8) else { throw JSONPathError.invalidPath }
        let root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let segments = try parse(path)
        var values: [(String, Any)] = [("$", root)]
        for segment in segments {
            var next: [(String, Any)] = []
            for (prefix, value) in values {
                switch segment {
                case .key(let key):
                    if let object = value as? [String: Any], let child = object[key] { next.append((prefix + "." + key, child)) }
                case .index(let index):
                    if let array = value as? [Any], array.indices.contains(index) { next.append((prefix + "[\(index)]", array[index])) }
                case .wildcard:
                    if let object = value as? [String: Any] {
                        for key in object.keys.sorted() { if let child = object[key] { next.append((prefix + "." + key, child)) } }
                    } else if let array = value as? [Any] {
                        for (index, child) in array.enumerated() { next.append((prefix + "[\(index)]", child)) }
                    }
                }
            }
            values = next
        }
        return values.map { JSONPathMatch(path: $0.0, value: $0.1) }
    }

    private static func parse(_ path: String) throws -> [Segment] {
        var text = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text == "$" || text.hasPrefix("$.") || text.hasPrefix("$[") else { throw JSONPathError.invalidPath }
        if text == "$" { return [] }
        text.removeFirst()
        var result: [Segment] = []
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "." { i = text.index(after: i) }
            if i < text.endIndex && text[i] == "[" {
                guard let close = text[i...].firstIndex(of: "]") else { throw JSONPathError.invalidPath }
                let token = String(text[text.index(after: i)..<close])
                if token == "*" { result.append(.wildcard) }
                else if let index = Int(token) { result.append(.index(index)) }
                else { throw JSONPathError.invalidPath }
                i = text.index(after: close)
                continue
            }
            let start = i
            while i < text.endIndex && text[i] != "." && text[i] != "[" { i = text.index(after: i) }
            let key = String(text[start..<i])
            guard !key.isEmpty else { throw JSONPathError.invalidPath }
            result.append(key == "*" ? .wildcard : .key(key))
        }
        return result
    }
}

enum JSONPathError: LocalizedError { case invalidPath
    var errorDescription: String? { "JSONPath 路径无效，请使用 $.items[0].name 或 $.*" }
}

struct JSONValidationIssue: Identifiable {
    let id = UUID()
    let message: String
    let utf16Location: Int
    let line: Int
    let column: Int
}

enum JSONValidator {
    static func validate(_ source: String) -> JSONValidationIssue? {
        guard let data = source.data(using: .utf8) else { return JSONValidationIssue(message: "无法读取文本", utf16Location: 0, line: 1, column: 1) }
        do { _ = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]); return nil }
        catch {
            let ns = source as NSString
            let lineHint = (error as NSError).userInfo["NSJSONSerializationErrorLineNumber"] as? Int
            let columnHint = (error as NSError).userInfo["NSJSONSerializationErrorColumnNumber"] as? Int
            let line = lineHint ?? 1
            let column = columnHint ?? 1
            let lines = source.components(separatedBy: "\n")
            let before = lines.prefix(max(0, line - 1)).reduce(0) { total, item in total + (item as NSString).length + 1 }
            let location = min(ns.length, max(0, before + column - 1))
            return JSONValidationIssue(message: error.localizedDescription, utf16Location: location, line: line, column: column)
        }
    }
}

struct JSONTreeNode: Identifiable {
    let id = UUID()
    let key: String
    let value: String
    let children: [JSONTreeNode]

    /// Builds a bounded preview. The editor remains responsive for very large
    /// JSON files; a truncation row indicates that the tree is a preview and
    /// the source editor still contains the complete document.
    static func make(key: String, any: Any, depth: Int = 0) -> JSONTreeNode {
        var budget = 12_000
        return build(key: key, any: any, depth: depth, budget: &budget)
    }

    private static func build(key: String, any: Any, depth: Int, budget: inout Int) -> JSONTreeNode {
        guard budget > 0 else { return JSONTreeNode(key: key, value: "…（树视图已限制节点数）", children: []) }
        budget -= 1
        if depth > 64 { return JSONTreeNode(key: key, value: "…", children: []) }
        if let object = any as? [String: Any] {
            var children: [JSONTreeNode] = []
            children.reserveCapacity(min(object.count, 64))
            for key in object.keys.sorted() {
                guard let value = object[key] else { continue }
                children.append(build(key: key, any: value, depth: depth + 1, budget: &budget))
                if budget <= 0 { break }
            }
            if children.count < object.count { children.append(JSONTreeNode(key: "…", value: "其余节点已隐藏", children: [])) }
            return JSONTreeNode(key: key, value: "{\(object.count)}", children: children)
        }
        if let array = any as? [Any] {
            var children: [JSONTreeNode] = []
            children.reserveCapacity(min(array.count, 64))
            for (index, value) in array.enumerated() {
                children.append(build(key: "[\(index)]", any: value, depth: depth + 1, budget: &budget))
                if budget <= 0 { break }
            }
            if children.count < array.count { children.append(JSONTreeNode(key: "…", value: "其余节点已隐藏", children: [])) }
            return JSONTreeNode(key: key, value: "[\(array.count)]", children: children)
        }
        if any is NSNull { return JSONTreeNode(key: key, value: "null", children: []) }
        if let string = any as? String { return JSONTreeNode(key: key, value: "\"\(string)\"", children: []) }
        return JSONTreeNode(key: key, value: String(describing: any), children: [])
    }
}
