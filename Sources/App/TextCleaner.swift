import Foundation

/// Fast, deterministic cleanup that runs on every transcript (no AI required).
struct TextCleaner {
    let settings: SettingsData

    static let hallucinations: Set<String> = [
        "thank you.", "thank you", "thanks for watching.", "thanks for watching", "[blank_audio]", "(silence)",
        "[silence]", "you", "you.", "bye.", "bye", "thank you for watching.", ".", "the", "so", "okay.",
        "[music]", "(music)", "♪", "subtitles by the amara.org community",
    ]

    func clean(_ raw: String) -> String {
        var t = raw.replacingOccurrences(of: "\r", with: "")
        t = t.replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*\)"#, with: "", options: .regularExpression) // [BLANK_AUDIO], (laughs)
        t = collapseSpaces(t)
        if Self.hallucinations.contains(t.lowercased()) { return "" }

        if settings.removeFillers { t = removeFillers(t) }
        if settings.voiceCommands { t = applyVoiceCommands(t) }
        t = applyReplacements(t)
        t = fixPunctuationSpacing(t)
        if settings.smartCapitalization { t = capitalizeSentences(t) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: pieces

    private func collapseSpaces(_ s: String) -> String {
        s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private func removeFillers(_ s: String) -> String {
        var t = s
        let words = settings.fillerWords.map { NSRegularExpression.escapedPattern(for: $0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return t }
        let alt = words.joined(separator: "|")
        // Filler at start of sentence followed by comma: "Um, so we" -> "So we"
        t = t.replacingOccurrences(of: #"(?i)(^|[.!?]\s+)(?:\#(alt))[,.]?\s+(\w)"#,
                                   with: "$1$2", options: .regularExpression)
        // Filler mid-sentence: "we, um, went" / "we um went" -> "we went"
        t = t.replacingOccurrences(of: #"(?i)[,]?\s+(?:\#(alt))[,.]?(?=\s|$)"#, with: "", options: .regularExpression)
        // Filler alone at start
        t = t.replacingOccurrences(of: #"(?i)^(?:\#(alt))[,.]?\s*"#, with: "", options: .regularExpression)
        return collapseSpaces(t)
    }

    private func applyVoiceCommands(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: #"(?i)[,.;:]?\s*\bnew paragraph\b[,.]?\s*"#, with: "\n\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?i)[,.;:]?\s*\bnew line\b[,.]?\s*"#, with: "\n", options: .regularExpression)
        // "scratch that" removes the previous sentence/clause.
        while let r = t.range(of: #"(?i)\bscratch that[,.]?\s*"#, options: .regularExpression) {
            let before = String(t[..<r.lowerBound])
            let after = String(t[r.upperBound...])
            var keep = before
            if let cut = before.range(of: #"[.!?,]\s*[^.!?,]*$"#, options: .regularExpression) {
                keep = String(before[..<cut.lowerBound]) + String(before[cut.lowerBound]).replacingOccurrences(of: ",", with: ".") + " "
            } else {
                keep = ""
            }
            t = keep + after
        }
        return t
    }

    private func applyReplacements(_ s: String) -> String {
        var t = s
        for r in settings.replacements where !r.from.trimmingCharacters(in: .whitespaces).isEmpty {
            let pat = #"(?i)\b"# + NSRegularExpression.escapedPattern(for: r.from.trimmingCharacters(in: .whitespaces)) + #"\b"#
            t = t.replacingOccurrences(of: pat, with: NSRegularExpression.escapedTemplate(for: r.to), options: .regularExpression)
        }
        return t
    }

    private func fixPunctuationSpacing(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"([,.!?;:])(?=[A-Za-z])"#, with: "$1 ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"([.!?,]){2,}"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #" +\n"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\n +"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return collapseSpaces(t)
    }

    private func capitalizeSentences(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        var out = ""
        var capitalizeNext = true
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if capitalizeNext, c.isLetter {
                out.append(contentsOf: String(c).uppercased())
                capitalizeNext = false
            } else {
                out.append(c)
                if c == "." || c == "!" || c == "?" || c == "\n" { capitalizeNext = true }
                else if !c.isWhitespace && c != "\"" && c != "'" && c != "(" { capitalizeNext = false }
            }
            i = s.index(after: i)
        }
        // Standalone "i"
        out = out.replacingOccurrences(of: #"\bi\b(?=['\s,.!?]|$)"#, with: "I", options: .regularExpression)
        return out
    }

    /// True when the transcript shows signs the AI polish can actually improve: spoken self-corrections,
    /// repeated/stuttered words, or filler phrases the rule-based cleaner doesn't touch. Whisper already
    /// punctuates and capitalizes, so for a clean sentence the (1–2 s) AI pass would only reproduce it.
    static func needsPolish(raw: String) -> Bool {
        let t = raw.lowercased()
        // Whole-word matches only ("um" must not match "volume").
        let cues = ["no wait", "wait no", "i mean", "i meant", "sorry", "actually", "scratch that", "rather", "make that",
                    "correction", "not that", "instead", "no no", "er", "uh", "uhm", "um", "hmm", "you know", "kind of", "sort of",
                    "basically", "literally", "so yeah", "and yeah", "okay so"]
        let alt = cues.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        if t.range(of: "\\b(?:\(alt))\\b", options: .regularExpression) != nil { return true }
        if t.contains(", no,") || t.contains("like,") { return true }
        // Immediate word repeats: "they they", "the the", "I I".
        if t.range(of: #"\b(\w+)[,]?\s+\1\b"#, options: .regularExpression) != nil { return true }
        // Run-on: long stretch without any punctuation.
        if t.count > 140, t.range(of: #"[.!?]"#, options: .regularExpression) == nil { return true }
        return false
    }

    /// Words to bias Whisper toward (custom vocabulary) plus a style hint.
    static func whisperPrompt(from settings: SettingsData) -> String {
        var words = settings.replacements.map(\.to).filter { !$0.isEmpty }
        words = Array(Set(words)).sorted().prefix(40).map { $0 }
        let vocab = words.isEmpty ? "" : " Vocabulary: " + words.joined(separator: ", ") + "."
        return "This is a dictated message, transcribed with correct punctuation and capitalization." + vocab
    }
}
