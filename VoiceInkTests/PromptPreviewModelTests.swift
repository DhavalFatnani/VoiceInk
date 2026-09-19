import AnantaPrompting
import Foundation
import Testing

@testable import VoiceInk

@MainActor
struct PromptPreviewModelTests {
    func prompt(project: URL?) -> ComposeResult {
        .prompt(
            ComposedPrompt(
                text: "Fix the login bug.", profile: .repoAgent, project: project,
                provenance: Provenance(model: "qwen2.5:7b", instructionsVersion: "prompting-1", briefFingerprint: nil, latency: .seconds(2))))
    }

    @Test func promptShowsProfileAndProjectAndInsertsThePrompt() {
        let model = PromptPreviewModel(result: prompt(project: URL(filePath: "/Users/d/Code/ananta")), raw: "fix login")
        #expect(model.headline == "Repo agent · ananta")
        #expect(model.insertText == "Fix the login bug.")
        #expect(model.insertLabel == "Insert")
        #expect(model.hasPrompt && !model.canRetry)
    }

    @Test func missingProjectIsSaidOutLoud() {
        #expect(PromptPreviewModel(result: prompt(project: nil), raw: "x").headline == "Repo agent · No project")
    }

    @Test func passthroughInsertsTheCleanedWords() {
        let model = PromptPreviewModel(result: .passthrough(cleaned: "haan go ahead"), raw: "haan go ahead")
        #expect(model.headline == "Short reply — not expanded")
        #expect(model.insertText == "haan go ahead")
    }

    @Test func offlineOffersStartAndInsertMyWords() {
        let model = PromptPreviewModel(result: .unstructured(cleaned: "fix it", reason: .modelOffline), raw: "fix it")
        #expect(model.headline == "Model offline")
        #expect(model.isOffline && model.canRetry)
        #expect(model.insertLabel == "Insert my words")
        #expect(model.insertText == "fix it")
    }

    @Test(arguments: [FailureReason.timedOut, .invalidOutput])
    func failuresSayTheyCouldNotStructure(reason: FailureReason) {
        let model = PromptPreviewModel(result: .unstructured(cleaned: "fix it", reason: reason), raw: "fix it")
        #expect(model.headline == "Couldn't structure this")
        #expect(model.canRetry && !model.isOffline)
    }
}
