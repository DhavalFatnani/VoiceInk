import Foundation
import Testing

@testable import VoiceInk

/// Language as a per-take choice rather than a property buried in mode configuration.
@MainActor
struct LanguageSessionTests {

    /// Its own defaults domain, so running the suite never touches the user's real recents.
    private func makeSession() -> LanguageSession {
        let suite = UserDefaults(suiteName: "LanguageSessionTests-\(UUID().uuidString)")!
        return LanguageSession(defaults: suite)
    }

    // MARK: - Following the mode versus overriding it

    @Test func nothingIsOverriddenToStartWith() {
        // Nil is not the same as "auto": auto is an explicit choice to let the model decide, and a
        // mode may not have made it.
        #expect(makeSession().override == nil)
    }

    @Test func selectingSetsTheOverride() {
        let session = makeSession()
        session.select("hi")
        #expect(session.override == "hi")
    }

    @Test func selectingNilGoesBackToFollowingTheMode() {
        let session = makeSession()
        session.select("hi")
        session.select(nil)
        #expect(session.override == nil)
    }

    @Test func clearingIsTheSameAsFollowingTheMode() {
        let session = makeSession()
        session.select("de")
        session.clearOverride()
        #expect(session.override == nil)
    }

    // MARK: - Recents

    @Test func choosingALanguageRemembersIt() {
        let session = makeSession()
        session.select("hi")
        #expect(session.recents == ["hi"])
    }

    @Test func mostRecentComesFirst() {
        let session = makeSession()
        session.select("hi")
        session.select("de")
        session.select("fr")
        #expect(session.recents == ["fr", "de", "hi"])
    }

    @Test func reselectingMovesToTheFrontRatherThanDuplicating() {
        let session = makeSession()
        session.select("hi")
        session.select("de")
        session.select("hi")
        #expect(session.recents == ["hi", "de"])
    }

    @Test func recentsAreCapped() {
        let session = makeSession()
        for code in ["hi", "de", "fr", "es", "it", "ja"] { session.select(code) }
        #expect(session.recents.count == LanguageSession.recentsLimit)
        #expect(session.recents.first == "ja")
        #expect(!session.recents.contains("hi"))
    }

    @Test func autoIsNeverARecent() {
        // It is always offered first anyway, so listing it twice wastes a slot in a short list.
        let session = makeSession()
        session.select("auto")
        session.select("hi")
        #expect(session.recents == ["hi"])
    }

    @Test func recentsSurviveAcrossSessionsButTheOverrideDoesNot() {
        // Recents are a convenience and persist. The override is a decision, and a decision still
        // silently in force a week later is invisible state governing the result.
        let suite = UserDefaults(suiteName: "LanguageSessionTests-\(UUID().uuidString)")!
        let first = LanguageSession(defaults: suite)
        first.select("hi")

        let second = LanguageSession(defaults: suite)
        #expect(second.recents == ["hi"])
        #expect(second.override == nil)
    }

    // MARK: - Seeding

    @Test func seedingUsesTheLanguagesTheModesAlreadyHave() {
        let session = makeSession()
        session.seedIfEmpty(with: ["auto", "hi", "de", "hi"])
        #expect(session.recents == ["hi", "de"])
    }

    @Test func seedingNeverOverwritesRealHistory() {
        let session = makeSession()
        session.select("fr")
        session.seedIfEmpty(with: ["hi", "de"])
        #expect(session.recents == ["fr"])
    }

    // MARK: - What the panel offers

    @Test func autoIsAlwaysFirst() {
        let session = makeSession()
        session.select("hi")
        #expect(session.offered(includingModeLanguage: nil).first == "auto")
    }

    @Test func theModesOwnLanguageIsAlwaysReachable() {
        // Without this, switching away from a Hindi mode would leave no way back to Hindi short of
        // opening the mode editor — the exact friction this feature removes.
        let session = makeSession()
        session.select("de")
        #expect(session.offered(includingModeLanguage: "hi").contains("hi"))
    }

    @Test func nothingIsOfferedTwice() {
        let session = makeSession()
        session.select("hi")
        let offered = session.offered(includingModeLanguage: "hi")
        #expect(offered.count == Set(offered).count)
    }

    @Test func aModeOnAutoAddsNothingExtra() {
        let session = makeSession()
        #expect(session.offered(includingModeLanguage: "auto") == ["auto"])
    }
}
