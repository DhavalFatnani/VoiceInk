import Foundation
import Testing

@testable import VoiceInk

/// Why enhancement can or cannot run.
///
/// This was a `Bool`, and all five ways it could be false collapsed into one answer. The pipeline
/// then skipped enhancement with no error, no notification and nothing recorded, so a take that
/// should have been rewritten came back raw and looked exactly like a take that never wanted
/// enhancement. An app-wide outage ran for hours before anyone could tell the difference.
///
/// These cover the reason itself — the strings shown to a person, and the short codes written to
/// the store. The codes are the part that must not drift: they are persisted, and a rename would
/// silently orphan every row already written.
@MainActor
struct EnhancementReadinessTests {

    private typealias Readiness = AIEnhancementService.Readiness

    @Test func onlyReadyIsReady() {
        #expect(Readiness.ready.isReady)
        #expect(!Readiness.noProvider.isReady)
        #expect(!Readiness.noPrompt.isReady)
        #expect(!Readiness.missingAPIKey(provider: "Groq").isReady)
        #expect(!Readiness.customProviderUnavailable(model: "x").isReady)
        #expect(!Readiness.refineUnavailable.isReady)
    }

    @Test func readyExplainsNothing() {
        // There is nothing to say when it worked, and a status line that always speaks is noise.
        #expect(Readiness.ready.explanation == nil)
        #expect(Readiness.ready.recordedReason == nil)
    }

    @Test func everyFailureExplainsItself() {
        let failures: [Readiness] = [
            .noProvider, .noPrompt, .missingAPIKey(provider: "Groq"),
            .customProviderUnavailable(model: "gpt-4"), .refineUnavailable,
        ]
        for failure in failures {
            #expect(failure.explanation?.isEmpty == false, "\(failure) has no explanation")
            #expect(failure.recordedReason?.isEmpty == false, "\(failure) records nothing")
        }
    }

    @Test func theProviderIsNamedInTheExplanation() {
        // "No API key" is not actionable; "No API key for Groq" is.
        let explanation = Readiness.missingAPIKey(provider: "Groq").explanation
        #expect(explanation?.contains("Groq") == true)
    }

    @Test func aMissingCustomModelStillExplainsItself() {
        // The model name is optional, and a nil must not produce "The custom provider for  isn't".
        let explanation = Readiness.customProviderUnavailable(model: nil).explanation
        #expect(explanation?.isEmpty == false)
        #expect(explanation?.contains("  ") == false)
    }

    // MARK: - Persisted codes
    //
    // Written to SessionMetric and read back by the peek and by Settings. They are contract, not
    // presentation: renaming one orphans every row already written, and the reason silently
    // disappears from the UI instead of failing loudly.

    @Test func recordedReasonsAreStable() {
        #expect(Readiness.noProvider.recordedReason == "no-provider")
        #expect(Readiness.noPrompt.recordedReason == "no-prompt")
        #expect(Readiness.missingAPIKey(provider: "Groq").recordedReason == "missing-api-key")
        #expect(
            Readiness.customProviderUnavailable(model: "x").recordedReason
                == "custom-provider-unavailable")
        #expect(Readiness.refineUnavailable.recordedReason == "refine-unavailable")
    }

    @Test func theProviderIsNotBakedIntoTheStoredCode() {
        // Otherwise every provider becomes its own reason and the codes cannot be grouped.
        #expect(
            Readiness.missingAPIKey(provider: "Groq").recordedReason
                == Readiness.missingAPIKey(provider: "OpenAI").recordedReason)
    }

    @Test func everyStoredCodeCanBeTurnedBackIntoWords() {
        // The peek and Settings both round-trip through this. A code with no mapping shows nothing
        // at all, which is the silence being fixed.
        let codes = [
            "no-provider", "no-prompt", "missing-api-key",
            "custom-provider-unavailable", "refine-unavailable",
            "short-transcript", "no-service",
        ]
        for code in codes {
            #expect(
                TranscriptionDelivery.explanation(for: code)?.isEmpty == false,
                "no wording for \(code)")
        }
    }

    @Test func anUnknownCodeIsSilentRatherThanWrong() {
        // Older rows, or a future reason on an older build. Better to say nothing than to invent.
        #expect(TranscriptionDelivery.explanation(for: "something-else") == nil)
    }

    @Test func theShortTranscriptSkipIsNotAFault() {
        // It has a code because it explains a raw result, but it is a setting working as asked and
        // must read that way rather than as a breakage.
        let wording = TranscriptionDelivery.explanation(for: "short-transcript")
        #expect(wording?.isEmpty == false)
        #expect(wording?.lowercased().contains("short") == true)
    }
}
