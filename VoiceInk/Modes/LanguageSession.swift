import Foundation

/// The language for the take you are about to make, separate from the mode you are making it in.
///
/// Modes are actions — Dictation, Email, Rewrite. Language is a property of the take. Keeping it
/// only inside mode configuration conflated the two, and the consequences were concrete: changing
/// language meant opening the mode editor, which nobody does mid-flow, so in practice people had
/// exactly one language. It also multiplies badly — Hindi times five actions is five more modes.
///
/// Precedence is `session override → mode's language → the model's own fallback`. A mode's language
/// stays meaningful as a *default* rather than a lock: "this mode is usually Hindi", with the panel
/// able to say "but not this time" without editing anything.
@MainActor
@Observable
final class LanguageSession {
    static let shared = LanguageSession()

    /// Nil means "follow the mode", which is not the same as `auto` — `auto` is an explicit choice
    /// to let the model decide, and one a mode may not have made.
    private(set) var override: String?

    /// Languages picked before, most recent first. Persisted; the override is not.
    private(set) var recents: [String] = []

    /// Beyond this the panel stops being a quick switch and becomes a list.
    static let recentsLimit = 4

    static let recentsKey = "LanguageSessionRecents"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recents = defaults.stringArray(forKey: Self.recentsKey) ?? []
    }

    private let defaults: UserDefaults

    /// - Parameter code: nil to stop overriding and follow the mode again.
    func select(_ code: String?) {
        override = code
        guard let code, code != "auto" else { return }
        remember(code)
    }

    /// Deliberately not persisted across launches.
    ///
    /// A language chosen last week and still silently in force is the same class of problem as a
    /// mode quietly pointing at a model that cannot serve it: invisible state governing the result.
    /// Recents persist because they are a convenience; the override does not because it is a
    /// decision, and decisions should expire.
    func clearOverride() {
        override = nil
    }

    private func remember(_ code: String) {
        var updated = recents.filter { $0 != code }
        updated.insert(code, at: 0)
        recents = Array(updated.prefix(Self.recentsLimit))
        defaults.set(recents, forKey: Self.recentsKey)
    }

    /// Seeds the list from the languages the user's modes are already configured with, so the panel
    /// is useful on the first take rather than after a week of teaching it.
    func seedIfEmpty(with modeLanguages: [String]) {
        guard recents.isEmpty else { return }
        var seen = Set<String>()
        recents = modeLanguages
            .filter { $0 != "auto" && seen.insert($0).inserted }
            .prefix(Self.recentsLimit)
            .map { $0 }
        defaults.set(recents, forKey: Self.recentsKey)
    }

    /// What the panel offers: auto first, then the languages actually used.
    func offered(includingModeLanguage modeLanguage: String?) -> [String] {
        var codes = ["auto"]
        for code in recents where code != "auto" && !codes.contains(code) {
            codes.append(code)
        }
        // The mode's own language belongs on the list even if it was never picked by hand —
        // otherwise a mode configured for Hindi shows no way back to Hindi after switching away.
        if let modeLanguage, modeLanguage != "auto", !codes.contains(modeLanguage) {
            codes.append(modeLanguage)
        }
        return codes
    }
}
