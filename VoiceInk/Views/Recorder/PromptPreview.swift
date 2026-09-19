import AnantaPrompting
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// What the preview shows for one composed result.
@MainActor
@Observable
final class PromptPreviewModel {
    var result: ComposeResult
    let raw: String
    var showingRaw = false
    var isRetrying = false

    init(result: ComposeResult, raw: String) {
        self.result = result
        self.raw = raw
    }

    var hasPrompt: Bool {
        if case .prompt = result { return true }
        return false
    }

    var isOffline: Bool {
        if case .unstructured(_, .modelOffline) = result { return true }
        return false
    }

    var canRetry: Bool {
        if case .unstructured = result { return true }
        return false
    }

    var insertText: String {
        switch result {
        case .prompt(let prompt): prompt.text
        case .passthrough(let cleaned), .unstructured(let cleaned, _): cleaned
        }
    }

    var insertLabel: String { hasPrompt ? "Insert" : "Insert my words" }

    var headline: String {
        switch result {
        case .prompt(let prompt):
            "\(Self.label(prompt.profile)) · \(prompt.project?.lastPathComponent ?? "No project")"
        case .passthrough:
            "Short reply — not expanded"
        case .unstructured(_, .modelOffline):
            "Model offline"
        case .unstructured:
            "Couldn't structure this"
        }
    }

    static func label(_ kind: TargetProfile.Kind) -> String {
        switch kind {
        case .repoAgent: "Repo agent"
        case .chat: "Chat"
        case .builder: "Builder"
        case .research: "Research"
        case .generic: "General"
        }
    }
}

struct PromptPreviewView: View {
    let model: PromptPreviewModel
    let insert: () -> Void
    let cancel: () -> Void
    let retry: () -> Void
    let startOllama: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.headline).font(.headline)
            ScrollView {
                Text(model.showingRaw ? model.raw : model.insertText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if model.hasPrompt {
                    Button(model.showingRaw ? "Show prompt" : "Show what I said") { model.showingRaw.toggle() }
                }
                if model.isOffline { Button("Start Ollama", action: startOllama) }
                if model.canRetry { Button("Retry", action: retry).disabled(model.isRetrying) }
                Spacer()
                Button("Cancel  esc", action: cancel)
                Button("\(model.insertLabel)  ⏎", action: insert).buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 560, height: 360)
    }
}

/// A floating panel that never takes focus, so the app being dictated into stays frontmost and the
/// paste lands there. Return and Esc are captured by a shortcut monitor and swallowed while it is open.
@MainActor
final class PromptPreviewController {
    private var panel: NSPanel?
    private let monitor = ShortcutMonitor()
    private var model: PromptPreviewModel?
    private var retryCompose: (() async -> ComposeResult)?
    /// The app captured at recording start. Insert pastes there and nowhere else.
    private var targetBundleID: String?

    func present(
        _ result: ComposeResult, raw: String, targetBundleID: String?,
        retry: @escaping () async -> ComposeResult
    ) {
        let model = PromptPreviewModel(result: result, raw: raw)
        self.model = model
        self.targetBundleID = targetBundleID
        retryCompose = retry

        let panel = panel ?? Self.makePanel()
        panel.contentView = NSHostingView(
            rootView: PromptPreviewView(
                model: model,
                insert: { [weak self] in self?.insert() },
                cancel: { [weak self] in self?.close() },
                retry: { [weak self] in self?.retry() },
                startOllama: Self.startOllama))
        panel.setContentSize(NSSize(width: 560, height: 360))
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.midX - 280, y: screen.minY + 120))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        // Act on key-up, not key-down: the monitor suppresses the key-down, every auto-repeat
        // while the key stays held, and the key-up. Acting on key-down instead would leave that
        // key-up (and any auto-repeat) unsuppressed once `insert()`/`close()` stop the monitor,
        // so it would leak to the app the paste just landed in.
        let started = monitor.start(
            shortcuts: [
                .promptPreviewInsert: .key(keyCode: UInt16(kVK_Return), modifierFlags: []),
                .promptPreviewInsertKeypad: .key(keyCode: UInt16(kVK_ANSI_KeypadEnter), modifierFlags: []),
                .promptPreviewCancel: .key(keyCode: UInt16(kVK_Escape), modifierFlags: []),
            ],
            onKeyDown: { _, _ in },
            onKeyUp: { [weak self] action, _ in
                switch action {
                case .promptPreviewInsert, .promptPreviewInsertKeypad: self?.insert()
                case .promptPreviewCancel: self?.close()
                default: break
                }
            })

        guard started else {
            close()
            NotificationManager.shared.showNotification(
                title: String(localized: "Prompt preview needs Accessibility access to capture Return and Esc."),
                type: .error)
            return
        }
    }

    func insert() {
        guard let text = model?.insertText, !text.isEmpty else { return close() }
        let target = targetBundleID
        close()
        if Self.shouldPaste(target: target, frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) {
            CursorPaster.startPasteAtCursor(text)
        } else {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            NotificationManager.shared.showNotification(
                title: String(
                    localized: "The app you dictated into isn't in front, so the prompt was copied instead of pasted."
                ),
                type: .info)
        }
    }

    /// True when it is safe to paste into whatever is frontmost now: either nothing was captured
    /// at recording start, or the app that was captured is still the one in front.
    static func shouldPaste(target: String?, frontmost: String?) -> Bool {
        target == nil || target == frontmost
    }

    func close() {
        monitor.stop()
        panel?.orderOut(nil)
        model = nil
        retryCompose = nil
        targetBundleID = nil
    }

    private func retry() {
        guard let model, let retryCompose else { return }
        model.isRetrying = true
        Task {
            model.result = await retryCompose()
            model.isRetrying = false
        }
    }

    /// Opens Ollama without bringing it forward, so the insert still goes to the original app.
    static func startOllama() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(
            at: URL(filePath: "/Applications/Ollama.app"), configuration: configuration)
    }

    static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}
