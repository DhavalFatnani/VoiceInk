import Foundation

/// What a local model's weights cost, next to the memory this Mac actually has.
///
/// Ollama reports the on-disk size of every model it has pulled, and loading one costs at least
/// that much resident memory before the KV cache is counted. When the weights alone reach the
/// machine's RAM, macOS pages the model in and out for every token: the request appears to hang,
/// the whole system stalls behind the swap, and enhancement eventually times out having produced
/// nothing. Nothing in that sequence looks like a memory problem from the outside — the app blames
/// the request, the user blames the app — so the numbers are worth carrying to the message.
struct LocalModelFootprint: Sendable, Equatable {
    /// Above half of RAM the model still loads, but leaves little room for the KV cache, the
    /// window server, and whatever else is already open. Below it, a laptop copes.
    private static let comfortableFraction = 0.5

    let modelName: String
    let modelSizeBytes: Int64
    let physicalMemoryBytes: UInt64

    init(
        modelName: String,
        modelSizeBytes: Int64,
        physicalMemoryBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) {
        self.modelName = modelName
        self.modelSizeBytes = modelSizeBytes
        self.physicalMemoryBytes = physicalMemoryBytes
    }

    enum Fit: Sendable {
        /// Loads and answers without disturbing the rest of the machine.
        case comfortable
        /// Loads, but competes with everything else for memory.
        case tight
        /// Cannot be held in memory at all; every token costs a trip to disk.
        case exceedsMemory
    }

    var fit: Fit {
        guard modelSizeBytes > 0, physicalMemoryBytes > 0 else { return .comfortable }

        if UInt64(modelSizeBytes) >= physicalMemoryBytes {
            return .exceedsMemory
        }
        if Double(modelSizeBytes) > Double(physicalMemoryBytes) * Self.comfortableFraction {
            return .tight
        }
        return .comfortable
    }

    var formattedModelSize: String {
        Self.format(bytes: modelSizeBytes)
    }

    var formattedPhysicalMemory: String {
        Self.format(bytes: Int64(clamping: physicalMemoryBytes))
    }

    /// The one line worth putting in front of someone before they wait on this model, or `nil`
    /// when the model fits and there is nothing to warn about.
    var warning: String? {
        switch fit {
        case .comfortable:
            return nil
        case .tight:
            return String(
                format: String(
                    localized:
                        "%1$@ needs about %2$@ of the %3$@ on this Mac. It will run, but slowly while other apps are open."
                ),
                modelName,
                formattedModelSize,
                formattedPhysicalMemory
            )
        case .exceedsMemory:
            return String(
                format: String(
                    localized:
                        "%1$@ needs about %2$@ but this Mac has %3$@ of memory. It cannot be held in memory, so every request pages to disk and stalls the whole machine. Choose a smaller model."
                ),
                modelName,
                formattedModelSize,
                formattedPhysicalMemory
            )
        }
    }

    private static func format(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB]
        formatter.countStyle = .memory
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}
