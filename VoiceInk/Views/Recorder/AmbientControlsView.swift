import SwiftUI

/// Everything on the ambient surface you can click, hosted in its own content-sized window.
///
/// Split out of `AmbientRecorderView` so the light can ignore the mouse permanently. Reads the same
/// engine state, so the two windows stay in step without talking to each other; the only thing they
/// share is `AmbientGeometry`, which is why both put their content at the same distance below the
/// hardware edge and read as one surface.
///
/// Reports its own visibility upward. A window sized to its content still has to be *ordered out*
/// when there is nothing in it, or an empty rectangle sits over the user's work absorbing clicks —
/// exactly the failure this split exists to remove.
struct AmbientControlsView<S: RecorderStateProvider & Observable>: View {
    var stateProvider: S
    var recorder: Recorder
    var meter: AmbientMeter
    var healthMonitor: RecorderInputHealthMonitor
    var silenceWatch: RecorderSilenceWatch
    /// Fires whenever the content appears, disappears or resizes, so the window can refit.
    var onContentChange: () -> Void = {}

    @AppStorage(AmbientBackgroundMode.userDefaultsKey) private var backgroundMode =
        AmbientBackgroundMode.auto.rawValue
    @AppStorage(RecorderDisplaySettingsKeys.showLiveTranscript) private var showLiveTranscript = true

    @State private var background = AmbientBackgroundSensor()

    private var palette: AmbientPalette {
        .resolve(
            measuredLight: background.resolved,
            mode: AmbientBackgroundMode(rawValue: backgroundMode) ?? .auto
        )
    }

    private var presentation: AmbientPresentation {
        AmbientPresentation.resolve(
            AmbientInputs(
                recordingState: stateProvider.recordingState,
                health: healthMonitor.health,
                hasResultPeek: stateProvider.resultPeek != nil,
                silenceCountdown: silenceWatch.secondsRemaining,
                hasLiveTranscript: showLiveTranscript && !stateProvider.partialTranscript.isEmpty,
                hasContextMessage: false,
                hasShownContext: true,
                hasTake: meter.hasTake
            )
        )
    }

    private var state: AmbientState { presentation.state }
    private var tint: Color { palette.color(for: state) }

    /// Only the interactive captions live here. A problem message, a context line or a live
    /// transcript is *read*, not clicked, so those stay in the light where they cost nothing.
    private var interactiveCaption: AmbientCaptionKind? {
        switch presentation.captionSlot {
        case .result: return stateProvider.resultPeek.map { .result($0) }
        case .countdown: return silenceWatch.secondsRemaining.map { .countdown($0) }
        default: return nil
        }
    }

    private var showsTakeBar: Bool { stateProvider.recordingState == .recording }

    var body: some View {
        VStack(spacing: 12) {
            if let interactiveCaption {
                AmbientCaption(
                    kind: interactiveCaption,
                    tint: state == .hidden ? palette.color(for: .working) : tint,
                    palette: palette,
                    onUndo: { Task { await stateProvider.undoResultPeek() } },
                    onRetry: { stateProvider.retryResultPeek() },
                    onKeepRecording: { silenceWatch.reset() }
                )
            }

            if showsTakeBar {
                HStack(spacing: 16) {
                    AmbientModeStrip(tint: tint, palette: palette)

                    Rectangle()
                        .fill(palette.separator.opacity(0.7))
                        .frame(width: 1, height: 13)

                    AmbientTakeBar(
                        clock: { AmbientTakeClock(meter: meter, palette: palette) },
                        isEnhancementEnabled: ModeManager.shared.currentEffectiveConfiguration?
                            .isAIEnhancementEnabled ?? false,
                        deviceName: healthMonitor.health.isProblem
                            ? AudioDeviceManager.shared.currentInputDeviceName : nil,
                        tint: tint,
                        palette: palette,
                        onCancel: { Task { await stateProvider.cancelTakeFromPanel() } }
                    )
                }
                .ambientTextBloom(
                    tint: tint, fill: palette.bloomFill,
                    opacity: palette.isLight ? 0.85 : 0.62
                )
            }
        }
        .fixedSize()
        // Any change of shape has to reach the window, which cannot see SwiftUI's layout.
        .onChange(of: interactiveCaption) { _, _ in onContentChange() }
        .onChange(of: showsTakeBar) { _, _ in onContentChange() }
        .onChange(of: state) { _, _ in onContentChange() }
        .onAppear { onContentChange() }
        .task(id: stateProvider.recordingState) {
            guard stateProvider.recordingState == .recording else { return }
            background.sample()
        }
    }

    /// Whether there is anything at all to show. The window manager orders the panel out when this
    /// is false, so no empty rectangle is ever left sitting over the user's work.
    var hasContent: Bool { interactiveCaption != nil || showsTakeBar }
}
