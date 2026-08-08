import AppKit
import Foundation

@MainActor
enum StarterModeFactory {
    static let defaultTranscriptionModelName = "parakeet-tdt-0.6b-v3"

    static func install(
        kinds: [StarterModeKind],
        provider: AIProvider,
        modelName: String?,
        transcriptionModelName: String = defaultTranscriptionModelName,
        isRealtimeTranscriptionEnabled: Bool = true,
        selectedLanguage: String = "auto",
        installedApps: [InstalledAppInfo]? = nil
    ) {
        let manager = ModeManager.shared
        let requestedKinds = Set(kinds)
        let availableInstalledApps =
            requestedKinds.contains(.email)
            ? (installedApps ?? InstalledApps.load())
            : []

        let starterConfigs = StarterModeCatalog.templates
            .filter { requestedKinds.contains($0.kind) }
            .map {
                makeConfig(
                    from: $0,
                    provider: provider,
                    modelName: modelName,
                    transcriptionModelName: transcriptionModelName,
                    isRealtimeTranscriptionEnabled: isRealtimeTranscriptionEnabled,
                    selectedLanguage: selectedLanguage,
                    installedApps: availableInstalledApps
                )
            }

        let nonStarterConfigs = manager.configurations
            .filter { !StarterModeCatalog.ids.contains($0.id) }
            .map { config -> ModeConfig in
                var config = config
                if starterConfigs.contains(where: \.isDefault) {
                    config.isDefault = false
                }
                return config
            }

        manager.replaceConfigurations(starterConfigs + nonStarterConfigs)

        for config in starterConfigs where config.isDefault {
            ShortcutStore.removeShortcutStorage(for: .mode(config.id))
        }

        if let defaultConfig = starterConfigs.first(where: \.isDefault) {
            manager.setActiveConfiguration(defaultConfig)
        }
    }

    /// Starter modes that ship with the app but are absent from this user's configuration.
    ///
    /// Almost always because they did not exist when the user onboarded. Starter modes are only
    /// installed during onboarding, so anything added afterwards is invisible forever to everyone
    /// who already set the app up — the Hinglish mode being the case that surfaced this.
    static var missingKinds: [StarterModeKind] {
        let installed = Set(ModeManager.shared.configurations.map(\.id))
        return StarterModeCatalog.templates
            .filter { !installed.contains($0.id) }
            .map(\.kind)
    }

    /// Adds the missing starter modes without touching anything the user already has.
    ///
    /// Deliberately *not* `install(kinds:)`, which replaces the whole configuration set and would
    /// reset any starter mode the user had since customised. This only appends.
    ///
    /// - Returns: the kinds actually added.
    @discardableResult
    static func installMissing(
        provider: AIProvider,
        modelName: String?,
        transcriptionModelName: String = defaultTranscriptionModelName,
        isRealtimeTranscriptionEnabled: Bool = true,
        selectedLanguage: String = "auto"
    ) -> [StarterModeKind] {
        let manager = ModeManager.shared
        let installed = Set(manager.configurations.map(\.id))
        let templates = StarterModeCatalog.templates.filter { !installed.contains($0.id) }
        guard !templates.isEmpty else { return [] }

        // Whatever is default today stays default. A mode arriving late has not earned the slot,
        // and silently moving it would change what every existing shortcut does.
        let hasDefault = manager.configurations.contains { $0.isDefault }

        let additions = templates.map { template -> ModeConfig in
            var config = makeConfig(
                from: template,
                provider: provider,
                modelName: modelName,
                transcriptionModelName: transcriptionModelName,
                isRealtimeTranscriptionEnabled: isRealtimeTranscriptionEnabled,
                selectedLanguage: selectedLanguage,
                installedApps: template.kind == .email ? InstalledApps.load() : []
            )
            if hasDefault { config.isDefault = false }
            return config
        }

        manager.replaceConfigurations(manager.configurations + additions)
        return templates.map(\.kind)
    }

    static func isInstalled(kind: StarterModeKind) -> Bool {
        guard let template = StarterModeCatalog.templates.first(where: { $0.kind == kind }) else {
            return false
        }

        return ModeManager.shared.configurations.contains { $0.id == template.id }
    }

    private static func makeConfig(
        from template: StarterModeTemplate,
        provider: AIProvider,
        modelName: String?,
        transcriptionModelName: String,
        isRealtimeTranscriptionEnabled: Bool,
        selectedLanguage: String,
        installedApps: [InstalledAppInfo]
    ) -> ModeConfig {
        ModeConfig(
            id: template.id,
            name: template.name,
            icon: template.icon,
            appConfigs: nil,
            urlConfigs: nil,
            triggerGroups: triggerGroups(for: template.kind, installedApps: installedApps),
            isAIEnhancementEnabled: template.usesAIEnhancement,
            selectedPrompt: template.promptId?.uuidString,
            selectedTranscriptionModelName: template.requiredTranscriptionModelName
                ?? transcriptionModelName,
            isRealtimeTranscriptionEnabled: isRealtimeTranscriptionEnabled,
            selectedLanguage: template.requiredLanguage ?? selectedLanguage,
            useClipboardContext: template.kind == .email,
            useSelectedTextContext: template.useSelectedTextContext,
            useScreenCapture: template.useScreenCapture,
            isTextFormattingEnabled: true,
            selectedAIProvider: template.usesAIEnhancement ? provider.rawValue : nil,
            selectedAIModel: template.usesAIEnhancement ? (modelName ?? provider.defaultModel) : nil,
            outputMode: template.outputMode,
            autoSendKey: .none,
            isEnabled: true,
            isDefault: template.isDefault
        )
    }

    private static func triggerGroups(
        for kind: StarterModeKind,
        installedApps: [InstalledAppInfo]
    ) -> [ModeTriggerGroup]? {
        guard kind == .email,
            let emailTemplate = TriggerTemplateCatalog.templates.first(where: { $0.id == "email" })
        else {
            return nil
        }

        let group = emailTemplate.availableGroup(
            installedApps: installedApps,
            existingAppBundleIds: [],
            existingWebsites: [],
            cleanURL: ModeManager.shared.cleanURL
        )

        return group.isEmpty ? nil : [group]
    }

}
