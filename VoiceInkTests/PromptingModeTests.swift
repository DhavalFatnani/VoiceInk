import Foundation
import Testing

@testable import VoiceInk

@MainActor
struct PromptingModeTests {
    @Test func promptingIsOfferedAsAnOutputModeWithoutPasteOptions() {
        #expect(ModeOutputMode.choices(canRespond: true).contains(.prompting))
        #expect(ModeOutputMode.choices(canRespond: false).contains(.prompting))
        #expect(!ModeOutputMode.prompting.usesPasteOptions)
    }

    @Test func promptingStarterModeUsesTheComposerNotEnhancement() throws {
        let template = try #require(StarterModeCatalog.templates.first { $0.kind == .prompting })
        #expect(template.id == UUID(uuidString: "10000000-0000-0000-0000-000000000007"))
        #expect(template.outputMode == .prompting)
        #expect(!template.usesAIEnhancement)
        #expect(template.featureLabels.contains("Prompt"))
    }

    @Test func promptingSurvivesACodableRoundTrip() throws {
        let config = ModeConfig(name: "Prompting", isAIEnhancementEnabled: false, outputMode: .prompting)
        let decoded = try JSONDecoder().decode(ModeConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded.outputMode == .prompting)
    }
}
