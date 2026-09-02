import Foundation
import Testing

@testable import VoiceInk

/// Whether a local model fits in this Mac's memory.
///
/// A 26B model whose weights are 16.75 GiB was selected on a 16 GiB laptop. Ollama could not hold
/// it, so every enhancement paged the weights in and out of disk: the machine stalled, the request
/// timed out after three retries, and the message that came back said to check the internet
/// connection. The size was knowable the whole time — Ollama reports it — and these cover reading
/// it correctly, because the boundary is exactly where the real case sat.
struct LocalModelFootprintTests {

    private let sixteenGiB: UInt64 = 16 * 1024 * 1024 * 1024

    private func footprint(_ bytes: Int64, memory: UInt64? = nil) -> LocalModelFootprint {
        LocalModelFootprint(
            modelName: "test-model",
            modelSizeBytes: bytes,
            physicalMemoryBytes: memory ?? sixteenGiB
        )
    }

    @Test func weightsLargerThanMemoryCannotLoad() {
        // gemma4:26b, as Ollama reports it, against the machine that stalled on it.
        let gemma = footprint(17_987_581_215)
        #expect(gemma.fit == .exceedsMemory)
    }

    @Test func halfOfMemoryIsTight() {
        let qwen14b = footprint(8_988_124_069)
        #expect(qwen14b.fit == .tight)
    }

    @Test func smallModelsAreComfortable() {
        #expect(footprint(2_019_393_189).fit == .comfortable)
        #expect(footprint(4_683_087_332).fit == .comfortable)
    }

    @Test func exactlyMemoryStillExceedsIt() {
        // Nothing else would be left to run, so it is a refusal, not a squeeze.
        #expect(footprint(Int64(sixteenGiB)).fit == .exceedsMemory)
    }

    @Test func unknownSizeIsNotTreatedAsAProblem() {
        // A missing size means Ollama has not been asked yet, which is not evidence of a bad fit.
        #expect(footprint(0).fit == .comfortable)
        #expect(footprint(0).warning == nil)
    }

    @Test func onlyPoorFitsWarn() {
        #expect(footprint(2_019_393_189).warning == nil)
        #expect(footprint(8_988_124_069).warning != nil)
        #expect(footprint(17_987_581_215).warning != nil)
    }

    @Test func theWarningNamesTheModelAndBothSizes() {
        let warning = footprint(17_987_581_215).warning
        #expect(warning?.contains("test-model") == true)
        #expect(warning?.contains("16") == true)
    }

    @Test func moreMemoryChangesTheVerdict() {
        let gemma: Int64 = 17_987_581_215
        #expect(footprint(gemma, memory: 64 * 1024 * 1024 * 1024).fit == .comfortable)
        #expect(footprint(gemma, memory: 32 * 1024 * 1024 * 1024).fit == .tight)
    }
}
