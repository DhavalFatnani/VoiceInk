import Foundation
import Testing

@testable import VoiceInk

/// Which mode chips are shown when there are more modes than room.
///
/// A sixth mode was added and simply vanished: the panel showed four, there was no count, and
/// nothing indicated ⌥6 would reach it. The mode was invisible in the one surface built for
/// switching modes, and the take went to the wrong mode with the wrong model.
struct RecorderModeOrderingTests {

    private let ids = (0..<6).map { _ in UUID() }
    private let base = Date(timeIntervalSince1970: 1_760_000_000)

    private func arrange(
        count: Int = 6,
        active: Int? = nil,
        used: [Int: TimeInterval] = [:],
        limit: Int = 4
    ) -> RecorderModeOrdering.Result {
        let modeIDs = Array(ids.prefix(count))
        var lastUsed: [UUID: Date] = [:]
        for (index, offset) in used { lastUsed[ids[index]] = base.addingTimeInterval(offset) }
        return RecorderModeOrdering.arrange(
            modeIDs: modeIDs,
            activeID: active.map { ids[$0] },
            lastUsed: lastUsed,
            limit: limit
        )
    }

    // MARK: - The shortcut number is not the display position
    //
    // ⌥N indexes into the stored order. Numbering chips by where they end up after reordering
    // would point every one of them at a different mode than its label claims — worse than the
    // problem being fixed.

    @Test func shortcutIndexAlwaysReflectsStoredPosition() {
        // Mode 5 is the most recently used, so it is shown — but it is still ⌥6.
        let result = arrange(active: 0, used: [5: 100])
        let promoted = result.visible.first { $0.modeID == ids[5] }
        #expect(promoted?.shortcutIndex == 5)
    }

    @Test func everyVisibleSlotKeepsItsOwnIndex() {
        let result = arrange(used: [4: 50, 5: 100])
        for slot in result.visible {
            #expect(ids[slot.shortcutIndex] == slot.modeID)
        }
    }

    // MARK: - What gets shown

    @Test func everythingFitsWhenItFits() {
        let result = arrange(count: 3)
        #expect(result.visible.count == 3)
        #expect(result.hiddenCount == 0)
    }

    @Test func theOverflowIsCountedRatherThanSilentlyDropped() {
        let result = arrange()
        #expect(result.visible.count == 4)
        #expect(result.hiddenCount == 2)
    }

    @Test func recentlyUsedModesAreShown() {
        // The exact failure: mode 5 added last, never in the first four, invisible forever. Using
        // it once should bring it into view.
        let result = arrange(used: [5: 100])
        #expect(result.visible.contains { $0.modeID == ids[5] })
    }

    @Test func moreRecentBeatsLessRecent() {
        let result = arrange(used: [0: 10, 1: 20, 2: 30, 3: 40, 4: 50, 5: 60])
        let shown = Set(result.visible.map(\.modeID))
        #expect(shown == Set([ids[2], ids[3], ids[4], ids[5]]))
    }

    @Test func theActiveModeIsAlwaysShown() {
        // Hiding the mode you are currently in would be absurd, and its name is the one you most
        // need to see while recording.
        let result = arrange(active: 5, used: [0: 10, 1: 20, 2: 30, 3: 40])
        #expect(result.visible.contains { $0.modeID == ids[5] })
    }

    @Test func neverUsedModesFallBackToStoredOrder() {
        let result = arrange()
        #expect(result.visible.map(\.shortcutIndex) == [0, 1, 2, 3])
    }

    @Test func usedModesOutrankNeverUsedOnes() {
        let result = arrange(used: [5: 100])
        #expect(result.visible.contains { $0.modeID == ids[5] })
        #expect(!result.visible.contains { $0.modeID == ids[3] })
    }

    // MARK: - Stability

    @Test func chipsStayInStoredOrderOnScreen() {
        // Chosen by recency, displayed in stored order. Chips that reshuffle position after every
        // take cannot be hit by muscle memory, which is most of what a chip row is for.
        let result = arrange(used: [5: 100, 0: 90])
        let indices = result.visible.map(\.shortcutIndex)
        #expect(indices == indices.sorted())
    }

    @Test func theSameInputGivesTheSameAnswer() {
        // Ties fall back to stored order rather than dictionary iteration, so the row does not
        // shuffle between redraws.
        let first = arrange(used: [0: 10, 1: 10, 2: 10, 3: 10, 4: 10, 5: 10])
        let second = arrange(used: [0: 10, 1: 10, 2: 10, 3: 10, 4: 10, 5: 10])
        #expect(first == second)
    }

    // MARK: - Edges

    @Test func aZeroLimitShowsNothingAndCountsEverything() {
        let result = arrange(limit: 0)
        #expect(result.visible.isEmpty)
        #expect(result.hiddenCount == 6)
    }

    @Test func noModesIsNotAnError() {
        let result = arrange(count: 0)
        #expect(result.visible.isEmpty)
        #expect(result.hiddenCount == 0)
    }
}
