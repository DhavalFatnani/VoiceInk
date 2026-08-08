import SwiftUI

/// Language switching from the recorder, without opening the mode editor.
///
/// Chips rather than a menu, deliberately. This window refuses key focus — clicking a control here
/// must not pull focus off the app the text is about to land in — and a popup menu from a
/// non-activating panel is exactly the kind of thing that works until it doesn't. The mode strip
/// beside it already proves chips work in this window. The cost is that the full 99-language list
/// stays in the mode editor; the panel offers auto plus what you actually use, which is the switch
/// people need mid-flow.
struct AmbientLanguageChips: View {
    let tint: Color
    var palette = AmbientPalette(isLight: false)
    /// Languages the current transcription model can actually produce.
    let supported: [String: String]
    /// The mode's own language, shown so there is always a way back to it.
    let modeLanguage: String?
    /// Named so an unsupported language can say what *would* work.
    let capableModelName: String?

    private let session = LanguageSession.shared

    private var codes: [String] { session.offered(includingModeLanguage: modeLanguage) }

    /// Hidden entirely for someone who dictates in one language: the strip is already long, and a
    /// control that never changes is not worth its width.
    var hasSomethingToOffer: Bool {
        codes.count > 1 || session.override != nil
    }

    var body: some View {
        if hasSomethingToOffer {
            HStack(spacing: 10) {
                ForEach(codes, id: \.self) { code in
                    chip(for: code)
                }
            }
        }
    }

    @ViewBuilder
    private func chip(for code: String) -> some View {
        let isSupported = supported[code] != nil
        let isActive = (session.override ?? modeLanguage ?? "auto") == code

        AmbientLanguageChip(
            title: displayName(for: code),
            isActive: isActive,
            isSupported: isSupported,
            unavailableReason: isSupported ? nil : unavailableReason(for: code),
            tint: tint,
            palette: palette
        ) {
            // Choosing the mode's own language is a return to following the mode, not an override
            // that happens to match — otherwise switching modes would not change language.
            session.select(code == modeLanguage ? nil : code)
        }
    }

    private func displayName(for code: String) -> String {
        if code == "auto" { return String(localized: "Auto") }
        return supported[code]
            ?? LanguageDictionary.all[code]
            ?? code.uppercased()
    }

    /// Silence here is what made "VoiceInk has no Hindi" look true when the answer was "Parakeet has
    /// no Hindi". An unsupported language stays visible and says which model would serve it.
    private func unavailableReason(for code: String) -> String {
        let name = LanguageDictionary.all[code] ?? code.uppercased()
        guard let capableModelName else {
            return String(
                format: String(localized: "This model can't transcribe %@."), name)
        }
        return String(
            format: String(localized: "This model can't transcribe %@. %@ can."),
            name, capableModelName)
    }
}

private struct AmbientLanguageChip: View {
    let title: String
    let isActive: Bool
    let isSupported: Bool
    let unavailableReason: String?
    let tint: Color
    let palette: AmbientPalette
    let action: () -> Void

    @State private var isHovering = false

    private var opacity: Double {
        // Unsupported stays legible rather than disappearing. A control you cannot see teaches you
        // the feature does not exist; one you can see but not use teaches you why.
        if !isSupported { return 0.4 }
        if isActive { return 1 }
        return isHovering ? 1 : 0.78
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if !isSupported {
                    Image(systemName: "slash.circle")
                        .font(.system(size: 8.5, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
            }
            .foregroundStyle(
                isActive && isSupported ? tint : palette.textPrimary.opacity(opacity)
            )
            .lineLimit(1)
            .shadow(color: palette.textShadow, radius: 2, y: 1)
            .shadow(color: palette.textShadow.opacity(0.5), radius: 6)
            .shadow(color: tint.opacity(isActive && isSupported ? 0.5 : 0), radius: 8)
        }
        .buttonStyle(.plain)
        .disabled(!isSupported)
        .help(unavailableReason ?? "")
        .onHover { isHovering = $0 }
        .animation(AppTheme.Motion.quick, value: isActive)
        .animation(AppTheme.Motion.quick, value: isHovering)
    }
}
