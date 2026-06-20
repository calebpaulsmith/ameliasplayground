import Foundation

/// Persists a `SaveSlot` to a local JSON file. Atomic writes; a corrupt or
/// missing file yields a fresh slot rather than crashing (privacy + no-failure
/// constraints, see docs/tvos/TECHNICAL_ARCHITECTURE.md "Save / persistence").
///
/// v1 uses a single slot; multiple named slots are a Phase 4 item (X4-04).
public final class SaveStore {
    private let url: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.url = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    /// Convenience pointing at the app's Application Support directory.
    public convenience init(fileName: String = "amelia_save.json") {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        self.init(fileURL: base.appendingPathComponent(fileName))
    }

    /// Loads the slot, or returns a fresh default if missing/corrupt.
    public func load() -> SaveSlot {
        guard let data = try? Data(contentsOf: url),
              let slot = try? decoder.decode(SaveSlot.self, from: data) else {
            return SaveSlot()
        }
        return slot
    }

    /// Writes atomically. Returns false on failure (never throws to the caller,
    /// so a bad write can't break play).
    @discardableResult
    public func save(_ slot: SaveSlot) -> Bool {
        guard let data = try? encoder.encode(slot) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }
}
