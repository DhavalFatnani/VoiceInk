import AnantaPrompting
import Foundation
import Testing

@testable import VoiceInk

/// Prompting mode shows its result for approval and must never reach `paste()`. These exercise
/// `TranscriptionDelivery.deliver` directly with spy `Actions` closures, so neither test drives a
/// real paste (which would post a Cmd+V into whatever app has focus in the test host).
@MainActor
struct TranscriptionDeliveryPromptingTests {
    private final class Spy {
        var dismissCalled = false
        var presentPromptPreviewCalls: [ComposeResult] = []
        var presentResultPeekCalled = false
    }

    private func makeActions(_ spy: Spy) -> TranscriptionDelivery.Actions {
        TranscriptionDelivery.Actions(
            setState: { _ in },
            dismiss: { spy.dismissCalled = true },
            presentResultPeek: { _ in spy.presentResultPeekCalled = true },
            sendFollowUp: { _, _ in },
            showResponse: { _, _ in },
            failResponse: { _ in },
            presentPromptPreview: { result in spy.presentPromptPreviewCalls.append(result) }
        )
    }

    private func makePromptingOutput() -> OutputRuntimeConfiguration {
        OutputRuntimeConfiguration(mode: nil, outputMode: .prompting, autoSendKey: .none, customCommand: nil)
    }

    private func makeCompletedTranscription() -> Transcription {
        Transcription(text: "hello", duration: 1, transcriptionStatus: .completed)
    }

    @Test func aComposedResultIsPreviewedNotPasted() async {
        let spy = Spy()
        let result = ComposeResult.passthrough(cleaned: "x")
        let request = TranscriptionDelivery.Request(
            transcription: makeCompletedTranscription(), text: "hello", output: makePromptingOutput(),
            responseConfig: nil, responseError: nil, isAssistantFollowUp: false, prompting: result)

        await TranscriptionDelivery().deliver(request, actions: makeActions(spy))

        #expect(spy.dismissCalled)
        #expect(spy.presentPromptPreviewCalls == [result])
        #expect(!spy.presentResultPeekCalled)
    }

    @Test func aMissingComposeResultStillDismissesWithoutPreviewingOrPasting() async {
        let spy = Spy()
        let request = TranscriptionDelivery.Request(
            transcription: makeCompletedTranscription(), text: "hello", output: makePromptingOutput(),
            responseConfig: nil, responseError: nil, isAssistantFollowUp: false, prompting: nil)

        await TranscriptionDelivery().deliver(request, actions: makeActions(spy))

        #expect(spy.dismissCalled)
        #expect(spy.presentPromptPreviewCalls.isEmpty)
        #expect(!spy.presentResultPeekCalled)
    }
}
