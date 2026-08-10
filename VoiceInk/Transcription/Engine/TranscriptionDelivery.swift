import AppKit
import Foundation
import SwiftData
import os

@MainActor
final class TranscriptionDelivery {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "TranscriptionDelivery")

    struct Request {
        let transcription: Transcription
        let text: String?
        let output: OutputRuntimeConfiguration
        let responseConfig: EnhancementRuntimeConfiguration?
        let responseError: String?
        let isAssistantFollowUp: Bool
    }

    struct Actions {
        let setState: @MainActor (RecordingState) -> Void
        let dismiss: @MainActor () async -> Void
        /// Called after a successful paste so the panel can offer undo and retry. The peek
        /// deliberately follows delivery rather than gating it — the text lands immediately.
        var presentResultPeek: @MainActor (RecorderResultPeek) -> Void = { _ in }
        let sendFollowUp: @MainActor (String, Transcription) async -> Void
        let showResponse: @MainActor (String, String?) async -> Void
        let failResponse: @MainActor (String) async -> Void
    }

    func deliver(_ request: Request, actions: Actions) async {
        guard request.transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue else {
            await actions.dismiss()
            return
        }

        if request.isAssistantFollowUp {
            await deliverFollowUp(request, actions: actions)
            return
        }

        if request.output.outputMode == .respond,
            request.responseConfig != nil || request.responseError != nil
        {
            await deliverResponse(request, actions: actions)
            return
        }

        if request.output.outputMode == .customCommand {
            await deliverCustomCommand(request, actions: actions)
            return
        }

        if let text = request.text {
            pendingPeekSource = request
            defer { pendingPeekSource = nil }
            await paste(text, output: request.output, actions: actions)
        } else {
            await actions.dismiss()
        }
    }

    private func deliverFollowUp(_ item: Request, actions: Actions) async {
        SoundManager.shared.playStopSound()

        guard let text = item.text?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return
        }

        actions.setState(.enhancing)
        await actions.sendFollowUp(text, item.transcription)
    }

    private func deliverResponse(_ item: Request, actions: Actions) async {
        SoundManager.shared.playStopSound()

        if let responseError = item.responseError {
            await actions.failResponse("Enhancement failed: \(responseError)")
        } else if let text = item.text,
            item.responseConfig != nil
        {
            await actions.showResponse(text, item.transcription.aiRequestSystemMessage)
        } else {
            await actions.failResponse("No response was generated.")
        }
    }

    private func deliverCustomCommand(_ item: Request, actions: Actions) async {
        guard let text = item.text else {
            notifyCustomCommandFailure(CustomCommandDeliveryError.noTextToDeliver)
            SoundManager.shared.playStopSound()
            await actions.dismiss()
            return
        }

        guard let customCommand = item.output.customCommand,
            let command = customCommand.trimmedCommand
        else {
            notifyCustomCommandFailure(CustomCommandDeliveryError.commandNotConfigured)
            SoundManager.shared.playStopSound()
            await actions.dismiss()
            return
        }

        let commandText = deliverableText(from: text)
        SoundManager.shared.playStopSound()
        await actions.dismiss()

        Task {
            await runCustomCommand(command: command, commandText: commandText)
        }
    }

    private func runCustomCommand(command: String, commandText: String) async {
        let startTime = Date()
        logger.notice("Custom command started")

        do {
            let result = try await CustomCommandDeliveryRunner.run(
                command: command,
                timeout: 10,
                context: CustomCommandDeliveryContext(transcript: commandText)
            )

            let duration = Date().timeIntervalSince(startTime)
            let stdoutBytes = result.stdout.utf8.count
            let stderrBytes = result.stderr.utf8.count

            if !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logger.notice(
                    "Custom command stdout bytes=\(stdoutBytes, privacy: .public): \(result.stdout, privacy: .public)")
            }

            if !result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                logger.notice(
                    "Custom command succeeded with stderr duration=\(Self.formattedDuration(duration), privacy: .public)s stdoutBytes=\(stdoutBytes, privacy: .public) stderrBytes=\(stderrBytes, privacy: .public): \(result.stderr, privacy: .public)"
                )
            } else {
                logger.notice(
                    "Custom command succeeded duration=\(Self.formattedDuration(duration), privacy: .public)s stdoutBytes=\(stdoutBytes, privacy: .public) stderrBytes=\(stderrBytes, privacy: .public)"
                )
            }
        } catch {
            notifyCustomCommandFailure(error, duration: Date().timeIntervalSince(startTime))
        }
    }

    private func notifyCustomCommandFailure(_ error: Error, duration: TimeInterval? = nil) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if let duration {
            logger.error(
                "Custom command failed duration=\(Self.formattedDuration(duration), privacy: .public)s: \(message, privacy: .public)"
            )
        } else {
            logger.error("Custom command failed: \(message, privacy: .public)")
        }
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        String(format: "%.3f", duration)
    }

    private func paste(_ text: String, output: OutputRuntimeConfiguration, actions: Actions) async {
        let textToPaste = deliverableText(from: text)
        let appendSpace = UserDefaults.standard.bool(forKey: "AppendTrailingSpace")
        let pastedText = textToPaste + (appendSpace ? " " : "")
        SoundManager.shared.playStopSound()
        await actions.dismiss()

        let pasteTask = CursorPaster.startPasteAtCursor(pastedText)

        let autoSendKey = output.outputMode == .paste ? output.autoSendKey : .none
        let peek = peek(for: textToPaste)
        Task { @MainActor in
            _ = await pasteTask.value

            if autoSendKey.isEnabled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                CursorPaster.performAutoSend(autoSendKey)
            }

            // Auto-send means the text is already committed elsewhere; offering undo there would
            // be misleading, so the peek is skipped.
            if !autoSendKey.isEnabled, let peek {
                actions.presentResultPeek(peek)
            }
        }
    }

    /// Built from the request currently being delivered, so the peek can offer the original text
    /// when enhancement changed it.
    private var pendingPeekSource: Request?

    /// Reads the reason back off the recorded session rather than threading it through delivery.
    ///
    /// The pipeline has already worked it out and written it down by this point, and re-deriving it
    /// here would mean two places deciding the same thing and eventually disagreeing.
    private func enhancementSkipExplanation(for transcription: Transcription) -> String? {
        let id = transcription.id
        let descriptor = FetchDescriptor<SessionMetric>(
            predicate: #Predicate<SessionMetric> { $0.transcriptionId == id }
        )
        // The transcript carries its own context; delivery has no separate handle on the store.
        guard let context = transcription.modelContext,
            let reason = try? context.fetch(descriptor).first?.enhancementSkipReason
        else { return nil }
        return Self.explanation(for: reason)
    }

    /// Persisted reasons are short and stable; the words shown to a person are neither.
    static func explanation(for reason: String) -> String? {
        switch reason {
        case "missing-api-key":
            return String(localized: "no API key for the selected provider")
        case "no-prompt":
            return String(localized: "this mode has no prompt")
        case "no-provider":
            return String(localized: "no AI provider selected")
        case "custom-provider-unavailable":
            return String(localized: "the custom provider isn't configured")
        case "refine-unavailable":
            return String(localized: "VoiceInk Refine is unavailable")
        case "short-transcript":
            return String(localized: "the transcript was too short")
        case "no-service":
            return String(localized: "the enhancement service wasn't available")
        case "failed":
            return String(localized: "the AI request failed or timed out")
        default:
            return nil
        }
    }

    private func peek(for pastedText: String) -> RecorderResultPeek? {
        guard let request = pendingPeekSource else { return nil }
        let transcription = request.transcription
        return RecorderResultPeek(
            transcriptionID: transcription.id,
            pastedText: pastedText,
            originalText: transcription.text,
            hasEnhancement: transcription.enhancedText != nil,
            enhancementSkipExplanation: enhancementSkipExplanation(for: transcription),
            duration: transcription.duration,
            modeName: transcription.modeName,
            targetBundleIdentifier: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
            appliedVocabularyTerms: WordReplacementService.shared.lastAppliedTerms
        )
    }

    private func deliverableText(from text: String) -> String {
        var textToDeliver = text
        if let restrictionMessage = LicenseViewModel.shared.usageRestrictionMessage {
            textToDeliver = """
                \(restrictionMessage)
                \n\(textToDeliver)
                """
        }

        return textToDeliver
    }
}
