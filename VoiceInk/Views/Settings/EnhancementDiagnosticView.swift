import SwiftData
import SwiftUI

/// Whether AI enhancement can actually run right now, and if not, why.
///
/// Enhancement stopped working app-wide and nothing said so — not the recorder, not Settings, not a
/// notification. Every take came back raw, which is indistinguishable from a mode that never wanted
/// enhancement, and the only way to establish otherwise was to query the store by hand.
///
/// Every value here comes from the same accessors the pipeline uses, so this cannot drift into
/// reporting health the pipeline disagrees with.
struct EnhancementDiagnosticView: View {
    var enhancementService: AIEnhancementService

    @Environment(\.modelContext) private var modelContext
    @State private var lastSuccess: Date?
    @State private var lastSkipReason: String?

    private var mode: ModeConfig? { ModeManager.shared.currentEffectiveConfiguration }

    private var readiness: AIEnhancementService.Readiness? {
        // Taken from the enhancement service rather than the environment: Settings does not carry
        // AIService, and the two must be the same instance the pipeline uses or this reports health
        // for a different object than the one doing the work.
        guard let aiService = enhancementService.getAIService() else { return nil }
        let configuration = ModeRuntimeResolver.currentEnhancementConfiguration(
            mode: mode,
            enhancementService: enhancementService,
            aiService: aiService
        )
        guard configuration.isEnabled else { return nil }
        return enhancementService.readiness(for: configuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Enhancement status")
                    .font(.system(size: 13))
                InfoTip("Whether the active mode can enhance right now, checked the same way a take checks it.")
                Spacer()
            }

            statusLine

            if let lastSuccess {
                detail(
                    String(
                        format: String(localized: "Last successful enhancement: %@"),
                        lastSuccess.formatted(date: .abbreviated, time: .shortened)))
            } else {
                detail(String(localized: "No enhancement has ever completed on this Mac."))
            }

            if let lastSkipReason,
                let explanation = TranscriptionDelivery.explanation(for: lastSkipReason)
            {
                detail(
                    String(format: String(localized: "Most recent skip: %@"), explanation))
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var statusLine: some View {
        if mode?.isAIEnhancementEnabled != true {
            label("minus.circle", String(localized: "Off for this mode"), .secondary)
        } else if let readiness, !readiness.isReady {
            label(
                "exclamationmark.triangle.fill",
                readiness.explanation ?? String(localized: "Unavailable"),
                .orange)
        } else {
            label("checkmark.circle.fill", String(localized: "Ready"), .green)
        }
    }

    private func label(_ symbol: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Read from history rather than tracked live: "it worked at some point" is only answerable by
    /// looking at what actually happened.
    private func load() async {
        var succeeded = FetchDescriptor<Transcription>(
            predicate: #Predicate { $0.enhancedText != nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        succeeded.fetchLimit = 1
        lastSuccess = (try? modelContext.fetch(succeeded))?.first?.timestamp

        var skipped = FetchDescriptor<SessionMetric>(
            predicate: #Predicate { $0.enhancementSkipReason != nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        skipped.fetchLimit = 1
        lastSkipReason = (try? modelContext.fetch(skipped))?.first?.enhancementSkipReason
    }
}
