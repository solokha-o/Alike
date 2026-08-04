import Foundation
import DesignSystem

struct GuideSearchResult: Identifiable, Sendable {
    let id: String
    let topicID: GuideTopicID
    let topicTitleKey: String.LocalizationValue
    let item: GuideItem
}

extension GuideContent {
    /// Case- and diacritic-insensitive match over every row title and body.
    ///
    /// The catalog is a handful of static arrays, so this stays a plain synchronous filter — there
    /// is nothing to index and nothing to cache.
    static func search(_ query: String) -> [GuideSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return topics.flatMap { topic in
            topic.sections.flatMap { section in
                section.items.compactMap { item in
                    guard matches(item: item, query: trimmed) else { return nil }
                    return GuideSearchResult(
                        id: item.id,
                        topicID: topic.id,
                        topicTitleKey: topic.titleKey,
                        item: item
                    )
                }
            }
        }
    }

    private static func matches(item: GuideItem, query: String) -> Bool {
        let haystack = [appLocalized(item.titleKey), item.bodyKey.map(appLocalized) ?? ""]
        return haystack.contains { $0.localizedStandardContains(query) }
    }
}
