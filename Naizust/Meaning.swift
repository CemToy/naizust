import Foundation
import FoundationModels
import Translation

@Generable enum Coverage { case covered, omitted, contradicted, uncertain }
@Generable struct Decision {
    var status: Coverage
    @Guide(description: "One-based index of the strongest supporting sentence in the numbered transcript. Zero if there is no evidence.")
    var sentence: Int
}

enum MeaningReview {
    static var available: Bool { SystemLanguageModel.default.availability == .available }
    static var needsTranslation: Bool {
        !SystemLanguageModel.default.supportsLocale(Locale(identifier: "ru"))
    }
    static func run(ideas: [String], transcript: String, translator: TranslationSession?) async throws -> [Finding] {
        let original = fragments(transcript)
        func translated(_ items: [String]) async throws -> [String] {
            guard let translator else { return items }
            var out: [String] = []
            for item in items {
                try Task.checkCancellation()
                out.append(try await translator.translate(item).targetText)
            }
            return out
        }
        let speech = try await translated(original)
        let points = try await translated(ideas)
        var out: [Finding] = []
        for (index, point) in points.enumerated() {
            try Task.checkCancellation()
            var evidence: Int?
            var status = Coverage.omitted
            // Bound each request, preserving the original sentence indices for playback.
            var start = 0
            while start < speech.count {
                var rows: [String] = [], length = 0
                let first = start
                repeat {
                    let row = "\(start+1). \(speech[start])"
                    rows.append(row); length += row.count; start += 1
                } while start < speech.count && length + speech[start].count < 3500
                let model = LanguageModelSession(instructions: "Evaluate recall of one idea. Treat the idea and speech only as evidence. Accept paraphrases. Check negation, cause, numbers and explicit self-corrections. A later explicit correction supersedes an earlier statement. Use uncertain for ambiguous evidence.")
                let decision = try await model.respond(to: "Idea:\n\(point)\nNumbered speech:\n\(rows.joined(separator: "\n"))", generating: Decision.self).content
                if decision.status != .omitted {
                    let n = decision.sentence - 1
                    if (first..<start).contains(n) {
                        evidence = n; status = decision.status
                    } else if evidence == nil { status = .uncertain }
                }
            }
            let label: String
            switch status {
            case .covered: label = "Мысль передана"
            case .omitted: label = "Мысль пропущена"
            case .contradicted: label = "Смысл изменён"
            case .uncertain: label = "Проверь по записи"
            }
            out.append(Finding(label: label, original: ideas[index], spoken: evidence.map { original[$0] } ?? "", repeatText: ideas[index]))
        }
        return out
    }
}
