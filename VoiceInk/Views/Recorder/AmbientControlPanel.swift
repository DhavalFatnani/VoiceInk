import AppKit
import SwiftUI

/// The clickable half of the ambient surface, in a window only as big as its contents.
///
/// Everything here used to live in the display-sized light panel, which meant that for the whole of
/// every take a window covering the entire screen was accepting mouse events. `ignoresMouseEvents`
/// is the only real passthrough macOS offers — a `hitTest` override stops a *view* handling a click
/// the window has already been handed, it does not return the click to the app underneath — so
/// every click landing on a painted pixel was swallowed. You could not click into the editor you
/// were dictating into.
///
/// Splitting the two is the fix, and it is a structural one rather than a tuning one: the light can
/// now ignore the mouse *permanently*, and the only window that accepts clicks is a few hundred
/// points wide and sits where you would expect a control to be. There is no configuration that can
/// bring the bug back.
@MainActor
final class AmbientControlPanel: NSPanel {
    /// Never key, for the same reason the light never is: clicking Undo must not pull focus off the
    /// app the text just landed in, or the synthesized Cmd+Z goes to this panel and does nothing.
    /// That exact bug cost an afternoon earlier; it is not being reintroduced through a new window.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        canHide = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Absent from screen recordings, exactly as the light is.
        sharingType = .none
    }
}

/// Sizes and positions the control panel, and keeps it under the notch as displays change.
@MainActor
final class AmbientControlWindowManager {
    private var panel: AmbientControlPanel?
    private let makeView: () -> AnyView
    /// Whether there is anything to show. Asked explicitly rather than inferred from the hosting
    /// view's fitting size: an empty SwiftUI view does not reliably measure as zero, and guessing
    /// wrong here leaves an invisible rectangle absorbing clicks — the precise failure this window
    /// exists to avoid.
    private let hasContent: () -> Bool

    private var isShowing = false
    private var observers: [NSObjectProtocol] = []

    /// Distance below the hardware edge, matched to where the caption sits in the light so the two
    /// read as one surface despite being two windows.
    private var topOffset: CGFloat { AmbientGeometry.current().captionY }

    init(hasContent: @escaping () -> Bool = { true }, content: @escaping () -> AnyView) {
        self.hasContent = hasContent
        self.makeView = content
    }

    // MARK: - Visible to tests

    var isPanelOnScreen: Bool { panel?.isVisible ?? false }
    var panelExists: Bool { panel != nil }
    var panelCanBecomeKey: Bool? { panel?.canBecomeKey }
    var panelSize: NSSize? { panel?.frame.size }

    func show() {
        isShowing = true
        if panel == nil { build() }
        startObserving()
        reposition()
    }

    func hide() {
        isShowing = false
        stopObserving()
        panel?.orderOut(nil)
    }

    func destroyWindow() {
        isShowing = false
        stopObserving()

        guard let doomed = panel else { return }
        panel = nil
        doomed.orderOut(nil)
        // Released a turn later with its content detached: a queued SwiftUI transaction landing on
        // a window mid-teardown throws from _postWindowNeedsUpdateConstraints.
        DispatchQueue.main.async { doomed.contentView = NSView(frame: .zero) }
    }

    /// Sizes the window to whatever SwiftUI wants and centres it under the notch.
    ///
    /// The window is deliberately never bigger than its content. That is the entire safety property
    /// here — a window that accepts clicks must not cover anything it does not draw.
    func reposition() {
        guard isShowing, let panel, let host = panel.contentView else { return }

        guard !AmbientAppExclusions.isFrontmostAppExcluded else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        guard let screen = NSScreen.main else { return }

        guard hasContent() else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }

        host.layoutSubtreeIfNeeded()
        let fitting = host.fittingSize
        guard fitting.width > 1, fitting.height > 1 else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }

        let origin = NSPoint(
            x: screen.frame.midX - fitting.width / 2,
            // AppKit's origin is bottom-left; the offset is measured from the top of the display.
            y: screen.frame.maxY - topOffset - fitting.height
        )
        let frame = NSRect(origin: origin, size: fitting)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter

        func observe(_ name: Notification.Name, on notificationCenter: NotificationCenter) {
            observers.append(
                notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated { self?.reposition() }
                })
        }

        observe(NSApplication.didChangeScreenParametersNotification, on: center)
        observe(NSWorkspace.activeSpaceDidChangeNotification, on: workspace)
        observe(NSWorkspace.didActivateApplicationNotification, on: workspace)
        observe(.ambientExclusionsChanged, on: center)
    }

    private func stopObserving() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func build() {
        let newPanel = AmbientControlPanel()
        // A plain hosting view: this window *should* take the clicks that land on it, and it only
        // ever covers what it draws.
        let host = NSHostingView(rootView: makeView())
        host.setContentHuggingPriority(.required, for: .horizontal)
        host.setContentHuggingPriority(.required, for: .vertical)
        newPanel.contentView = host
        panel = newPanel
    }
}
