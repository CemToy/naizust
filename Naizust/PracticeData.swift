import Foundation

enum Mode: String, Codable, CaseIterable {
    case exact = "Слово в слово"
    case meaning = "Своими словами"
}
struct Piece: Identifiable, Codable {
    var id = UUID()
    var title = ""
    var body = ""
    var ideas = ""
    var mode = Mode.exact
    var attempts: [Attempt] = []
}
struct Finding: Identifiable, Codable {
    var id = UUID()
    var label: String
    var original: String
    var spoken: String
    var second: Double?
    var repeatText: String
}
struct Attempt: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var mode: Mode
    var source: String
    var transcript = ""
    var points: [String]? = nil
    var hints: [String] = []
    var findings: [Finding] = []
    var audio: String?
    var note = ""
}
func words(_ text: String) -> [String] {
    text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
}
func key(_ word: String) -> String {
    word.lowercased().replacingOccurrences(of: "ё", with: "е")
}
func fragments(_ text: String) -> [String] {
    text.components(separatedBy: CharacterSet(charactersIn: ".!?;\n")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
}
struct TimedWord { var word: String; var time: Double }

// Align the suffix against nearby source positions, tolerating skipped words.
func nextPosition(source: [String], speech: String, near: Int) -> Int {
    let tail = words(speech).suffix(10).map(key)
    guard !tail.isEmpty else { return near }
    let start = max(0, near - 16), end = min(source.count, near + 48)
    guard start < end else { return near }
    var row = Array(repeating: 0, count: end-start+1)
    for word in tail {
        var next = row
        next[0] = 0
        for j in 1..<row.count {
            next[j] = max(0, row[j-1] + (key(source[start+j-1]) == word ? 3 : -3), row[j]-2, next[j-1]-2)
        }
        row = next
    }
    let best = row.max() ?? 0
    guard best >= 3 else { return near }
    let matches = row.indices.filter { row[$0] == best }
    return start + (matches.min { abs(start+$0-near-1) < abs(start+$1-near-1) } ?? 0)
}

func exactFindings(source: String, transcript: String, timing: [TimedWord]) -> [Finding] {
    let lines = fragments(source)
    let tokens = lines.enumerated().flatMap { n, line in words(line).map { ($0,n) } }
    let heard = words(transcript)
    let expected = tokens.map { key($0.0) }
    let actual = heard.map(key)
    let diff = actual.difference(from: expected)
    var removed = Set<Int>(), added = Set<Int>()
    for change in diff {
        switch change {
        case .remove(let i, _, _): removed.insert(i)
        case .insert(let j, _, _): added.insert(j)
        }
    }
    let timed = timing.map { key($0.word) } == actual
    var i = 0, j = 0, result: [Finding] = []
    while i < tokens.count || j < actual.count {
        let a = i, b = j
        while removed.contains(i) { i += 1 }
        while added.contains(j) { j += 1 }
        if i != a || j != b {
            let label = i == a ? "Добавлено" : (j == b ? "Пропущено" : "Замена")
            let context = tokens.isEmpty ? source : lines[tokens[min(a,tokens.count-1)].1...tokens[min(max(a,i-1),tokens.count-1)].1].joined(separator: ". ")
            result.append(Finding(label: label, original: tokens[a..<i].map { $0.0 }.joined(separator: " "), spoken: heard[b..<j].joined(separator: " "), second: timed && !timing.isEmpty ? timing[min(b,timing.count-1)].time : nil, repeatText: context))
        } else { i += 1; j += 1 }
    }
    return result
}

