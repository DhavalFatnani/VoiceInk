import Foundation
import Testing

@testable import VoiceInk

/// Capping the context handed to a model.
///
/// Window OCR was pasted into the prompt whole. Measured on a 16 GB M-series laptop, the ~1100
/// extra tokens that produced cost a 14B local model 16.5 seconds of prefill against 2 seconds of
/// actual generation — the model spent its time reading the screen rather than fixing the sentence,
/// and a text-heavy window had no ceiling at all.
struct EnhancementContextBudgetTests {

    @Test func localModelsGetAMuchSmallerBudget() {
        #expect(
            EnhancementContextBudget.limit(runsLocally: true)
                < EnhancementContextBudget.limit(runsLocally: false)
        )
    }

    @Test func contextThatFitsIsUntouched() {
        let blocks = ["one", "two", "three"]
        #expect(EnhancementContextBudget.fit(blocks, within: 1000) == blocks)
    }

    @Test func emptyBlocksAreDropped() {
        #expect(EnhancementContextBudget.fit(["a", "", "b"], within: 1000) == ["a", "b"])
    }

    @Test func earlierBlocksAreServedFirst() {
        // Selected text outranks a screen grab: the budget goes to the deliberate context.
        let selected = String(repeating: "s", count: 80)
        let screen = String(repeating: "w", count: 500)

        let kept = EnhancementContextBudget.fit([selected, screen], within: 100)

        #expect(kept.first == selected)
        #expect(kept.count == 2)
        #expect(kept[1].hasPrefix("w"))
    }

    @Test func aBlockTooBigForWhatIsLeftIsClipped() {
        let kept = EnhancementContextBudget.fit([String(repeating: "x", count: 5000)], within: 200)
        #expect(kept.count == 1)
        #expect(kept[0].count <= 200)
    }

    @Test func nothingSurvivesAnExhaustedBudget() {
        let first = String(repeating: "a", count: 100)
        let kept = EnhancementContextBudget.fit([first, "second", "third"], within: 100)
        #expect(kept == [first])
    }

    @Test func aZeroBudgetKeepsNothing() {
        #expect(EnhancementContextBudget.fit(["anything"], within: 0).isEmpty)
    }

    @Test func theTotalNeverExceedsTheBudget() {
        let blocks = (0..<10).map { _ in String(repeating: "z", count: 900) }
        let limit = EnhancementContextBudget.localCharacters

        let total = EnhancementContextBudget.fit(blocks, within: limit)
            .reduce(0) { $0 + $1.count }

        #expect(total <= limit)
    }

    @Test func clippedTextSaysThatItStopped() {
        // A model handed a sentence that ends mid-word will otherwise try to finish it.
        let clipped = EnhancementContextBudget.clip(String(repeating: "word ", count: 500), to: 200)
        #expect(clipped.contains("truncated"))
        #expect(clipped.count <= 200)
    }

    @Test func shortTextIsNotClippedOrMarked() {
        #expect(EnhancementContextBudget.clip("short", to: 200) == "short")
    }

    @Test func clippingPrefersToEndOnAWordBoundary() {
        let clipped = EnhancementContextBudget.clip("alpha beta gamma delta epsilon zeta", to: 30)
        #expect(!clipped.replacingOccurrences(of: "\n…(context truncated)", with: "").hasSuffix(" "))
        #expect(clipped.count <= 30)
    }

    @Test func aBudgetTooSmallForTheMarkerStillRespectsTheLimit() {
        let clipped = EnhancementContextBudget.clip(String(repeating: "x", count: 100), to: 5)
        #expect(clipped.count <= 5)
    }
}
