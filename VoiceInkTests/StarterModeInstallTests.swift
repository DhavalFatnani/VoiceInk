import Foundation
import Testing

@testable import VoiceInk

/// Installing a starter mode that shipped after the user onboarded.
///
/// The only route to a newly added starter mode used to be Reset Onboarding, which rebuilds the
/// whole set and throws away every customisation on the modes the user already had. These tests
/// pin the property that makes the additive path worth having: it must add, and do nothing else.
@MainActor
struct StarterModeInstallTests {

    private let manager = ModeManager.shared

    /// Restores whatever the user actually has, so running the suite is not destructive.
    private func withIsolatedModes(_ body: () -> Void) {
        let original = manager.configurations
        let originalActive = manager.activeConfiguration
        defer {
            manager.replaceConfigurations(original)
            manager.setActiveConfiguration(originalActive)
        }
        body()
    }

    private func template(_ kind: StarterModeKind) -> StarterModeTemplate {
        StarterModeCatalog.templates.first { $0.kind == kind }!
    }

    @Test func everythingInstalledMeansNothingMissing() {
        withIsolatedModes {
            manager.replaceConfigurations(
                StarterModeCatalog.templates.map { blankConfig(from: $0) })
            #expect(StarterModeFactory.missingKinds.isEmpty)
        }
    }

    @Test func aModeAddedAfterOnboardingIsReportedMissing() {
        withIsolatedModes {
            let withoutHinglish = StarterModeCatalog.templates
                .filter { $0.kind != .hinglish }
                .map { blankConfig(from: $0) }
            manager.replaceConfigurations(withoutHinglish)

            #expect(StarterModeFactory.missingKinds == [.hinglish])
        }
    }

    @Test func installingAddsOnlyWhatIsMissing() {
        withIsolatedModes {
            manager.replaceConfigurations(
                StarterModeCatalog.templates
                    .filter { $0.kind != .hinglish }
                    .map { blankConfig(from: $0) })
            let before = manager.configurations.count

            let added = StarterModeFactory.installMissing(provider: .openAI, modelName: nil)

            #expect(added == [.hinglish])
            #expect(manager.configurations.count == before + 1)
            #expect(StarterModeFactory.missingKinds.isEmpty)
        }
    }

    @Test func existingModesAreNotRebuilt() {
        // The whole reason this exists rather than reusing install(kinds:). A user who renamed a
        // starter mode, pointed it at a different model, or turned its AI off must keep all of it.
        withIsolatedModes {
            var customised = blankConfig(from: template(.enhance))
            customised.name = "My Tweaked Mode"
            customised.selectedTranscriptionModelName = "something-else"
            customised.isAIEnhancementEnabled = false
            manager.replaceConfigurations([customised])

            StarterModeFactory.installMissing(provider: .openAI, modelName: nil)

            let survivor = manager.configurations.first { $0.id == customised.id }
            #expect(survivor?.name == "My Tweaked Mode")
            #expect(survivor?.selectedTranscriptionModelName == "something-else")
            #expect(survivor?.isAIEnhancementEnabled == false)
        }
    }

    @Test func aLateArrivalDoesNotStealTheDefault() {
        // Default decides what a bare shortcut does. A mode the user has never seen must not
        // quietly take that over.
        withIsolatedModes {
            var existing = blankConfig(from: template(.clean))
            existing.isDefault = true
            manager.replaceConfigurations([existing])

            StarterModeFactory.installMissing(provider: .openAI, modelName: nil)

            #expect(manager.configurations.filter { $0.isDefault }.count == 1)
            #expect(manager.configurations.first { $0.isDefault }?.id == existing.id)
        }
    }

    @Test func installingTwiceIsHarmless() {
        withIsolatedModes {
            manager.replaceConfigurations([])
            StarterModeFactory.installMissing(provider: .openAI, modelName: nil)
            let afterFirst = manager.configurations.count

            let second = StarterModeFactory.installMissing(provider: .openAI, modelName: nil)
            #expect(second.isEmpty)
            #expect(manager.configurations.count == afterFirst)
        }
    }

    @Test func theHinglishModeCarriesItsOwnModelAndLanguage() {
        // Parakeet supports no Indic language at all, so this mode cannot take the install-wide
        // default the way every other starter mode does.
        withIsolatedModes {
            manager.replaceConfigurations([])
            StarterModeFactory.installMissing(
                provider: .openAI,
                modelName: nil,
                transcriptionModelName: "parakeet-tdt-0.6b-v3",
                selectedLanguage: "auto"
            )

            let hinglish = manager.configurations.first { $0.id == template(.hinglish).id }
            #expect(hinglish?.selectedTranscriptionModelName == "ggml-large-v3")
            #expect(hinglish?.selectedLanguage == "hi")
            #expect(hinglish?.isAIEnhancementEnabled == true)

            // Everything else still takes the default it was given.
            let dictation = manager.configurations.first { $0.id == template(.clean).id }
            #expect(dictation?.selectedTranscriptionModelName == "parakeet-tdt-0.6b-v3")
            #expect(dictation?.selectedLanguage == "auto")
        }
    }

    @Test func theHinglishModeNamesAPromptThatExists() {
        // A mode pointing at a prompt id nothing seeds falls back to whatever prompt happens to be
        // first, which looks like the mode simply not working.
        let promptId = template(.hinglish).promptId
        #expect(promptId == PromptTemplates.hinglishPromptId)
        #expect(PromptTemplates.seedPrompts.contains { $0.id == promptId })
    }

    // MARK: - Helper

    /// A config with the template's identity but none of the install-time choices, standing in for
    /// a mode the user already has.
    private func blankConfig(from template: StarterModeTemplate) -> ModeConfig {
        ModeConfig(
            id: template.id,
            name: template.name,
            icon: template.icon,
            appConfigs: nil,
            urlConfigs: nil,
            triggerGroups: nil,
            isAIEnhancementEnabled: template.usesAIEnhancement,
            selectedPrompt: template.promptId?.uuidString,
            selectedTranscriptionModelName: "parakeet-tdt-0.6b-v3",
            isRealtimeTranscriptionEnabled: true,
            selectedLanguage: "auto",
            useClipboardContext: false,
            useSelectedTextContext: template.useSelectedTextContext,
            useScreenCapture: template.useScreenCapture,
            isTextFormattingEnabled: true,
            selectedAIProvider: nil,
            selectedAIModel: nil,
            outputMode: template.outputMode,
            autoSendKey: .none,
            isEnabled: true,
            isDefault: false
        )
    }
}
