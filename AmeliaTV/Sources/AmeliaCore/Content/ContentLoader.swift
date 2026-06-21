import Foundation

/// Loads and decodes the data-driven content from a directory of JSON files.
/// Used by the app at launch (pointed at the bundle's Content/ folder) and by
/// unit tests (pointed at the repo's AmeliaTV/Content/ folder).
public enum ContentLoader {

    public enum LoadError: Error, Equatable {
        case missingFile(String)
        case decodeFailed(String)
    }

    /// Expects this layout under `directory`:
    ///   strings/en.json, strings/es.json   (id -> text)
    ///   places.json                         ([Place])
    ///   passengers.json                     ([Passenger])
    ///   vehicles.json                       ([Vehicle], optional)
    ///   episodes/*.json                     (Episode each)
    public static func load(from directory: URL) throws -> GameContent {
        let fm = FileManager.default
        let decoder = JSONDecoder()

        // Strings: merge per-language files into id -> (lang -> text).
        var strings: [String: [String: String]] = [:]
        for lang in Language.allCases {
            let url = directory.appendingPathComponent("strings/\(lang.rawValue).json")
            guard let data = try? Data(contentsOf: url) else {
                throw LoadError.missingFile("strings/\(lang.rawValue).json")
            }
            guard let map = try? decoder.decode([String: String].self, from: data) else {
                throw LoadError.decodeFailed("strings/\(lang.rawValue).json")
            }
            for (id, text) in map {
                strings[id, default: [:]][lang.rawValue] = text
            }
        }

        let places: [Place] = try decodeArray(at: directory.appendingPathComponent("places.json"),
                                              name: "places.json", decoder: decoder)
        let passengers: [Passenger] = try decodeArray(at: directory.appendingPathComponent("passengers.json"),
                                                      name: "passengers.json", decoder: decoder)

        // Vehicles are optional (the Rescue Team is set dressing / future cast).
        var vehicles: [Vehicle] = []
        let vehiclesURL = directory.appendingPathComponent("vehicles.json")
        if let data = try? Data(contentsOf: vehiclesURL) {
            guard let decoded = try? decoder.decode([Vehicle].self, from: data) else {
                throw LoadError.decodeFailed("vehicles.json")
            }
            vehicles = decoded
        }

        // Lights are optional (an episode may not use a traffic light).
        var lights: [Light] = []
        let lightsURL = directory.appendingPathComponent("lights.json")
        if let data = try? Data(contentsOf: lightsURL) {
            guard let decoded = try? decoder.decode([Light].self, from: data) else {
                throw LoadError.decodeFailed("lights.json")
            }
            lights = decoded
        }

        // Collectibles are optional (balloons / coins scattered along routes).
        var collectibles: [Collectible] = []
        let collectiblesURL = directory.appendingPathComponent("collectibles.json")
        if let data = try? Data(contentsOf: collectiblesURL) {
            guard let decoded = try? decoder.decode([Collectible].self, from: data) else {
                throw LoadError.decodeFailed("collectibles.json")
            }
            collectibles = decoded
        }

        // Episodes: every *.json in episodes/.
        var episodes: [Episode] = []
        let episodesDir = directory.appendingPathComponent("episodes")
        if let files = try? fm.contentsOfDirectory(at: episodesDir,
                                                   includingPropertiesForKeys: nil) {
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file) else {
                    throw LoadError.missingFile("episodes/\(file.lastPathComponent)")
                }
                guard let ep = try? decoder.decode(Episode.self, from: data) else {
                    throw LoadError.decodeFailed("episodes/\(file.lastPathComponent)")
                }
                episodes.append(ep)
            }
        }

        return GameContent(strings: strings, places: places,
                           passengers: passengers, vehicles: vehicles,
                           lights: lights, collectibles: collectibles, episodes: episodes)
    }

    private static func decodeArray<T: Decodable>(at url: URL, name: String,
                                                  decoder: JSONDecoder) throws -> [T] {
        guard let data = try? Data(contentsOf: url) else { throw LoadError.missingFile(name) }
        guard let value = try? decoder.decode([T].self, from: data) else {
            throw LoadError.decodeFailed(name)
        }
        return value
    }
}
