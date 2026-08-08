import SwiftUI

/// Mode switching for a surface with nowhere to put a button.
///
/// The panel hides its modes behind a grid icon that expands on hover. Ambient cannot borrow that:
/// there is no chrome to hang an icon off, and a hover target parked over the user's work would
/// swallow clicks on whatever is underneath. So this inverts it — the modes are always legible
/// while a take is running, and disappear entirely when it is not.
///
/// That turns out to be the better trade here. The shortcut is printed next to each name, so the
/// row teaches ⌥1–9 every time you record and then gets out of the way; and the moment it is on
/// screen is exactly the moment switching matters, because a mode chosen after the take has started
/// still applies to it.
///
/// Only shown during a take, which is also what makes it safe to accept clicks at all — the rest of
/// the time the ambient window is entirely transparent to the mouse.
struct AmbientModeStrip: View {
    let tint: Color
    var palette = AmbientPalette(isLight: false)

    private let modeManager = ModeManager.shared

    /// Four is what fits at a readable size without the row starting to look like a toolbar.
    private static let limit = 4

    private var enabled: [ModeConfig] { modeManager.enabledConfigurations }

    private var activeModeID: UUID? {
        modeManager.currentEffectiveConfiguration?.id
    }

    /// Chosen by recent use rather than by stored position, so a mode added later does not sit
    /// permanently past the edge with nothing to say it exists.
    private var arrangement: RecorderModeOrdering.Result {
        RecorderModeOrdering.arrange(
            modeIDs: enabled.map(\.id),
            activeID: activeModeID,
            lastUsed: RecorderModeFamiliarity.lastUsedMap(for: enabled.map(\.id)),
            limit: Self.limit
        )
    }

    var body: some View {
        let arrangement = self.arrangement
        if !arrangement.visible.isEmpty {
            HStack(spacing: 18) {
                ForEach(arrangement.visible, id: \.modeID) { slot in
                    if let mode = enabled.first(where: { $0.id == slot.modeID }) {
                        AmbientModeItem(
                            mode: mode,
                            // The stored position, because that is what ⌥N selects. Numbering by
                            // display position would point every chip at the wrong mode.
                            shortcutNumber: slot.shortcutIndex + 1,
                            isActive: mode.id == activeModeID,
                            tint: tint,
                            palette: palette
                        ) {
                            modeManager.setActiveConfiguration(mode)
                        }
                    }
                }

                if arrangement.hiddenCount > 0 {
                    Text(
                        String(
                            format: String(localized: "+%lld more · ⌥1–%lld"),
                            Int64(arrangement.hiddenCount), Int64(enabled.count))
                    )
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.textPrimary.opacity(0.55))
                    .shadow(color: palette.textShadow, radius: 2, y: 1)
                    .help(String(localized: "More modes are available by keyboard"))
                }
            }
        }
    }
}

/// Text that happens to be tappable, following the caption's rule: no capsule, no fill. The active
/// mode is marked by being *lit* rather than by a background, which is the only marker this design
/// has that does not reintroduce chrome.
private struct AmbientModeItem: View {
    let mode: ModeConfig
    let shortcutNumber: Int
    let isActive: Bool
    let tint: Color
    let palette: AmbientPalette
    let action: () -> Void

    @State private var isHovering = false

    /// The inactive floor used to be 0.45, which over a bright window was not readable at all — a
    /// control you cannot see is not a control. Dimming still marks the active one; it just no
    /// longer does it by making the others disappear.
    private var nameOpacity: Double {
        if isActive { return 1 }
        return isHovering ? 1 : 0.78
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(verbatim: "⌥\(shortcutNumber)")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(palette.textPrimary.opacity(isActive ? 0.75 : 0.5))

                Text(mode.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? tint : palette.textPrimary.opacity(nameOpacity))
            }
            .lineLimit(1)
            // Dark and tight before anything coloured: these sit over arbitrary content, and
            // contrast is what makes glyphs sharp where glow only makes them foggy.
            .shadow(color: palette.textShadow, radius: 2, y: 1)
            .shadow(color: palette.textShadow.opacity(0.5), radius: 6)
            .shadow(color: tint.opacity(isActive ? 0.5 : 0), radius: 8)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(AppTheme.Motion.quick, value: isActive)
        .animation(AppTheme.Motion.quick, value: isHovering)
        .accessibilityLabel(
            Text(
                String(
                    format: String(localized: "Switch to %@, option %lld"),
                    mode.name, Int64(shortcutNumber)
                )
            )
        )
    }
}
