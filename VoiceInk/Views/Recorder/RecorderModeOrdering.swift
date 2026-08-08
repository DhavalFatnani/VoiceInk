import Foundation

/// Which mode chips the recorder shows, when there are more modes than room.
///
/// The panel shows four. Adding a sixth mode put it past that edge, and there was no sign it
/// existed — no chip, no count, nothing to say ⌥6 would reach it. The mode was invisible in the one
/// surface meant to switch between modes.
///
/// A larger fixed limit only moves the cliff. Ordering by recent use means the modes you actually
/// work in stay visible and the ones you configured once drift out, which is the same trick that
/// makes the language recents useful.
///
/// **The shortcut number is not the display position.** ⌥N indexes into the stored mode order, so a
/// chip's label has to keep reporting where the mode sits in *that* list, not where it happens to
/// appear after reordering. Getting this wrong would silently point every chip at the wrong mode —
/// which is worse than the problem being solved.
enum RecorderModeOrdering {
    struct Slot: Equatable {
        /// Position in the stored order. This is what ⌥N selects and what the chip must display.
        let shortcutIndex: Int
        let modeID: UUID
    }

    struct Result: Equatable {
        let visible: [Slot]
        /// Modes that did not fit. Surfaced as a count so the panel can say they exist.
        let hiddenCount: Int
    }

    /// - Parameters:
    ///   - modeIDs: enabled modes, in stored order — the order ⌥N indexes into.
    ///   - activeID: always shown, however long since it was last used. Hiding the mode you are
    ///     currently in would be absurd, and it is the one whose name you most need to see.
    ///   - lastUsed: last-use timestamps. Missing means never used.
    ///   - limit: how many chips fit.
    static func arrange(
        modeIDs: [UUID],
        activeID: UUID?,
        lastUsed: [UUID: Date],
        limit: Int
    ) -> Result {
        guard limit > 0 else { return Result(visible: [], hiddenCount: modeIDs.count) }

        let slots = modeIDs.enumerated().map { Slot(shortcutIndex: $0.offset, modeID: $0.element) }
        guard slots.count > limit else { return Result(visible: slots, hiddenCount: 0) }

        let ranked = slots.sorted { lhs, rhs in
            // The active mode outranks everything.
            if let activeID {
                if lhs.modeID == activeID { return true }
                if rhs.modeID == activeID { return false }
            }
            switch (lastUsed[lhs.modeID], lastUsed[rhs.modeID]) {
            case let (left?, right?) where left != right:
                return left > right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                // Never used, or used at the same instant: fall back to stored order so the result
                // is stable rather than dependent on dictionary iteration.
                return lhs.shortcutIndex < rhs.shortcutIndex
            }
        }

        // Chosen by recency, then shown in stored order. Chips that reshuffle position every take
        // are unhittable by muscle memory, and the whole point is being able to reach them.
        let chosen = ranked.prefix(limit).sorted { $0.shortcutIndex < $1.shortcutIndex }
        return Result(visible: Array(chosen), hiddenCount: slots.count - limit)
    }
}
