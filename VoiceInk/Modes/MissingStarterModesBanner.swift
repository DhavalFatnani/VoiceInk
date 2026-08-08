import SwiftUI

/// Offers the starter modes this user never received.
///
/// Starter modes are only installed during onboarding, so any mode added to the app afterwards is
/// invisible forever to everyone who already set it up. Until now the only route to a new one was
/// Reset Onboarding, which rebuilds the whole set and discards every customisation the user has
/// made to the modes they already had — a bad trade for gaining one.
///
/// Shown only when something is genuinely missing, so for most people it never appears at all.
struct MissingStarterModesBanner: View {
    var enhancementService: AIEnhancementService
    var aiService: AIService

    @State private var missing: [StarterModeKind] = StarterModeFactory.missingKinds
    @State private var isInstalling = false

    private var templates: [StarterModeTemplate] {
        StarterModeCatalog.templates.filter { missing.contains($0.kind) }
    }

    var body: some View {
        if !templates.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(
                            templates.count == 1
                                ? "A new starter mode is available"
                                : "New starter modes are available"
                        )
                        .font(.system(size: 13, weight: .medium))

                        Text("Added since you set VoiceInk up. Your existing modes are untouched.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 12)

                    Button(templates.count == 1 ? "Add" : "Add All") { install() }
                        .disabled(isInstalling)
                        .controlSize(.small)
                }

                ForEach(templates) { template in
                    HStack(alignment: .top, spacing: 8) {
                        ModeIconView(icon: template.icon)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .font(.system(size: 12, weight: .medium))
                            Text(template.description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private func install() {
        isInstalling = true
        defer { isInstalling = false }

        let kinds = StarterModeFactory.missingKinds
        guard !kinds.isEmpty else { return }

        // Prompts first. A mode installed without the prompt it names would silently fall back to
        // whatever prompt happens to be first, which looks like the mode simply not working.
        let seeded = StarterModePromptSeeder.ensurePrompts(
            for: kinds, in: enhancementService.customPrompts)
        if seeded.didChange {
            enhancementService.customPrompts = seeded.prompts
        }

        // The provider the user already enhances with, rather than a default they never chose.
        let provider = aiService.selectedProvider
        StarterModeFactory.installMissing(
            provider: provider,
            modelName: aiService.currentModel
        )

        missing = StarterModeFactory.missingKinds
    }
}
