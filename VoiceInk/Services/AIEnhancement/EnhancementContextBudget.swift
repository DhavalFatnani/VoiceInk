import Foundation

/// How much captured context a model is handed before it starts work.
///
/// Context is not free. Every character becomes prompt the model must read before it writes
/// anything, and that reading — prefill — is charged at a very different rate depending on where
/// the model runs. Against a hosted API it is someone else's GPU and a few hundred milliseconds.
/// Against a model on this machine it is the dominant cost of the whole request.
///
/// Measured on an M-series laptop with 16 GB, enhancing one dictated sentence:
///
///     qwen2.5:14b, ~1300 tokens of prompt   prefill 16.5s, generation 2.0s
///     qwen2.5:14b,  ~190 tokens of prompt   prefill  2.5s, generation 2.0s
///     qwen2.5:7b,   ~190 tokens of prompt   prefill  1.3s, generation 0.9s
///
/// The extra ~1100 tokens were window OCR, pasted in whole because nothing bounded it. They cost
/// fourteen seconds of waiting to improve one sentence — and on a text-heavy window there was no
/// ceiling at all. A screenful of text is context; a whole document is a tax.
///
/// So context is capped, and capped much harder when the model runs here.
enum EnhancementContextBudget {
    /// Roughly 300 tokens: enough for a window title and the text around the cursor, little enough
    /// that prefill stays under a second even on a small local model.
    static let localCharacters = 1200

    /// Hosted models read far faster and bill by the token rather than the second, so the limit is
    /// about relevance rather than latency.
    static let cloudCharacters = 8000

    static func limit(runsLocally: Bool) -> Int {
        runsLocally ? localCharacters : cloudCharacters
    }

    /// Fits blocks into a shared budget, in the order given.
    ///
    /// Order is priority: text the person deliberately selected earns its place ahead of whatever
    /// happened to be on screen. Each block takes what is left, a block too big for the remainder is
    /// clipped, and once the budget is spent the rest are dropped rather than silently half-included.
    static func fit(_ blocks: [String], within limit: Int) -> [String] {
        guard limit > 0 else { return [] }

        var remaining = limit
        var kept: [String] = []

        for block in blocks where !block.isEmpty {
            guard remaining > 0 else { break }

            if block.count <= remaining {
                kept.append(block)
                remaining -= block.count
            } else {
                let clipped = clip(block, to: remaining)
                if !clipped.isEmpty {
                    kept.append(clipped)
                }
                remaining = 0
            }
        }

        return kept
    }

    /// Keeps the head of the text and says that it stopped.
    ///
    /// The head, because a window's title and its first lines identify what is being worked on,
    /// which is what context is for. Saying so, because a model handed a sentence that stops
    /// mid-word will otherwise try to finish it.
    static func clip(_ text: String, to limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard text.count > limit else { return text }

        let marker = "\n…(context truncated)"
        guard limit > marker.count else {
            return String(text.prefix(limit))
        }

        let budget = limit - marker.count
        var head = String(text.prefix(budget))

        // Prefer a line break, then a space, so the text ends somewhere a reader would stop.
        if let lastNewline = head.lastIndex(of: "\n"), head.distance(from: lastNewline, to: head.endIndex) < budget / 2 {
            head = String(head[head.startIndex..<lastNewline])
        } else if let lastSpace = head.lastIndex(of: " "),
            head.distance(from: lastSpace, to: head.endIndex) < budget / 2
        {
            head = String(head[head.startIndex..<lastSpace])
        }

        return head + marker
    }
}
