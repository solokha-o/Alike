import Foundation

/// Stable identity for every guide topic. Drives routing, so it stays small and `Hashable`.
public enum GuideTopicID: String, CaseIterable, Hashable, Sendable {
    case gettingStarted
    case scanning
    case cleanupQueue
    case comparingPhotos
    case smartCategories
    case deletingSafely
    case settingsAndReminders
    case freeAndPro
    case privacy
}

/// Status chips the guide documents. Each maps to a colour the user already sees in Cleanup.
enum GuideLegendTint: Hashable, Sendable {
    case needsReview
    case inReview
    case reviewed
    case isNew
    case savings
}

/// How a single guide row presents itself.
enum GuideItemKind: Hashable, Sendable {
    /// Plain explanation: glyph, title, body.
    case fact
    /// Numbered walkthrough step.
    case step(number: Int, of: Int)
    /// Highlighted suggestion with a tinted row background.
    case tip
    /// Safety-critical or irreversible behaviour.
    case caution
    /// Feature that requires an Alike Pro subscription.
    case pro
    /// Documents a status badge shown elsewhere in the app.
    case legend(GuideLegendTint)
}

/// One row of guide content.
///
/// Localization keys are stored, not resolved: the app changes language through iOS Settings, so
/// resolving at `static let` initialization would freeze the copy at first access.
struct GuideItem: Identifiable, Sendable {
    let id: String
    let kind: GuideItemKind
    /// SF Symbol name. Never localized.
    let symbol: String
    let titleKey: String.LocalizationValue
    let bodyKey: String.LocalizationValue?

    init(
        id: String,
        kind: GuideItemKind = .fact,
        symbol: String,
        title: String.LocalizationValue,
        body: String.LocalizationValue? = nil
    ) {
        self.id = id
        self.kind = kind
        self.symbol = symbol
        self.titleKey = title
        self.bodyKey = body
    }
}

/// A group of rows inside a topic. Headers become VoiceOver rotor headings; footers carry caveats.
struct GuideSection: Identifiable, Sendable {
    let id: String
    let headerKey: String.LocalizationValue?
    let footerKey: String.LocalizationValue?
    let items: [GuideItem]

    init(
        id: String,
        header: String.LocalizationValue? = nil,
        footer: String.LocalizationValue? = nil,
        items: [GuideItem]
    ) {
        self.id = id
        self.headerKey = header
        self.footerKey = footer
        self.items = items
    }
}

/// A single guide topic, shown as one row on the hub and one pushed detail screen.
struct GuideTopic: Identifiable, Sendable {
    let id: GuideTopicID
    /// SF Symbol name, mirroring the app's own chrome wherever possible.
    let symbol: String
    let titleKey: String.LocalizationValue
    /// One-line summary shown under the title on the hub row.
    let summaryKey: String.LocalizationValue
    let sections: [GuideSection]

    init(
        id: GuideTopicID,
        symbol: String,
        title: String.LocalizationValue,
        summary: String.LocalizationValue,
        sections: [GuideSection]
    ) {
        self.id = id
        self.symbol = symbol
        self.titleKey = title
        self.summaryKey = summary
        self.sections = sections
    }
}
