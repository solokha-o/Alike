import Foundation
import os

public enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.alike.app"

    public static let scan = Logger(subsystem: subsystem, category: "scan")
    public static let vision = Logger(subsystem: subsystem, category: "vision")
    public static let photoKit = Logger(subsystem: subsystem, category: "photokit")
    public static let clustering = Logger(subsystem: subsystem, category: "clustering")
    public static let storage = Logger(subsystem: subsystem, category: "storage")
    public static let ui = Logger(subsystem: subsystem, category: "ui")

    public enum Event {
        case start, finish, progress, cache, photokit, vision, clustering, storage, ui, error

        var emoji: String {
            switch self {
            case .start: return "🚀"
            case .finish: return "✅"
            case .progress: return "📈"
            case .cache: return "🗃️"
            case .photokit: return "🖼️"
            case .vision: return "🧠"
            case .clustering: return "🧩"
            case .storage: return "💾"
            case .ui: return "🧭"
            case .error: return "⚠️"
            }
        }
    }

    public static func tag(_ event: Event, _ message: String) -> String {
        "\(event.emoji) \(message)"
    }
}
