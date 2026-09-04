import Core
import Foundation

/// Loads a `BestShotCalibrationCorpus` export from disk for the offline harness.
///
/// The exporter (in-app) and this loader must agree on the wire format, so both
/// sides pin the same `JSONEncoder`/`JSONDecoder` date strategy here rather than
/// relying on `Codable`'s default (which is not ISO 8601).
public enum CorpusLoader {
    public enum LoaderError: Error, CustomStringConvertible, Equatable {
        case schemaTooNew(found: Int, supported: Int)

        public var description: String {
            switch self {
            case let .schemaTooNew(found, supported):
                return """
                Corpus schemaVersion \(found) is newer than this tool understands \
                (supports up to \(supported)). Update BestShotCalibration before \
                reading this export.
                """
            }
        }
    }

    /// Shared so the exporter and the harness can never drift on date encoding.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// A corpus plus any non-fatal warnings the caller should surface.
    public struct LoadResult {
        public let corpus: BestShotCalibrationCorpus
        public let warnings: [String]
    }

    public static func load(
        from url: URL,
        currentConfig: PhotoQualityScoringConfig = .current
    ) throws -> LoadResult {
        let data = try Data(contentsOf: url)
        return try load(data: data, currentConfig: currentConfig)
    }

    public static func load(
        data: Data,
        currentConfig: PhotoQualityScoringConfig = .current
    ) throws -> LoadResult {
        let corpus = try makeDecoder().decode(BestShotCalibrationCorpus.self, from: data)

        guard corpus.schemaVersion <= BestShotCalibrationCorpus.currentSchemaVersion else {
            throw LoaderError.schemaTooNew(
                found: corpus.schemaVersion,
                supported: BestShotCalibrationCorpus.currentSchemaVersion
            )
        }

        var warnings: [String] = []
        if corpus.thumbnailConfigVersion != currentConfig.thumbnailConfigVersion {
            warnings.append("""
            Corpus was exported with thumbnailConfigVersion \(corpus.thumbnailConfigVersion), \
            but the current scoring config uses thumbnailConfigVersion \
            \(currentConfig.thumbnailConfigVersion). The raw signals in this corpus were \
            measured on a different analysis geometry and are not directly comparable to \
            today's scoring; re-export before trusting these numbers.
            """)
        }

        return LoadResult(corpus: corpus, warnings: warnings)
    }
}
