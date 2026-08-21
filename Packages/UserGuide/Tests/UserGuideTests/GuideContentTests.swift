import Testing
import DesignSystem
@testable import UserGuide

@Suite("Guide content")
struct GuideContentTests {
    @Test("Every topic id resolves to itself")
    func topicLookupIsTotal() {
        for id in GuideTopicID.allCases {
            #expect(GuideContent.topic(id).id == id)
        }
    }

    @Test("The catalog covers every topic id exactly once")
    func catalogCoversAllTopics() {
        let ids = GuideContent.topics.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set(ids) == Set(GuideTopicID.allCases))
    }

    @Test("Item ids are unique across the whole guide")
    func itemIdentifiersAreUnique() {
        let ids = GuideContent.topics.flatMap { topic in
            topic.sections.flatMap { $0.items.map(\.id) }
        }
        #expect(Set(ids).count == ids.count)
    }

    @Test("Section ids are unique across the whole guide")
    func sectionIdentifiersAreUnique() {
        let ids = GuideContent.topics.flatMap { $0.sections.map(\.id) }
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every topic has content and a symbol")
    func topicsAreNonEmpty() {
        for topic in GuideContent.topics {
            #expect(!topic.symbol.isEmpty)
            #expect(!topic.sections.isEmpty)
            for section in topic.sections {
                #expect(!section.items.isEmpty)
                for item in section.items {
                    #expect(!item.symbol.isEmpty)
                }
            }
        }
    }

    @Test("Numbered steps are consecutive and agree on their total")
    func stepsAreWellFormed() {
        for topic in GuideContent.topics {
            for section in topic.sections {
                let steps = section.items.compactMap { item -> (Int, Int)? in
                    guard case .step(let number, let total) = item.kind else { return nil }
                    return (number, total)
                }
                guard !steps.isEmpty else { continue }
                #expect(steps.map(\.0) == Array(1...steps.count))
                #expect(steps.allSatisfy { $0.1 == steps.count })
            }
        }
    }

    @Test("Blank queries return nothing")
    func searchIgnoresBlankQueries() {
        #expect(GuideContent.search("").isEmpty)
        #expect(GuideContent.search("   ").isEmpty)
    }

    /// The query is the row's own rendered title, so this holds whether or not the string catalog
    /// resolves — SwiftPM copies `.xcstrings` verbatim instead of compiling it, so under
    /// `swift test` the lookup falls back to the key itself.
    @Test("Search finds a row by its own title and reports the owning topic")
    func searchFindsRowsByTitle() throws {
        let topic = GuideContent.topic(.comparingPhotos)
        let item = try #require(topic.sections.first?.items.first)

        let results = GuideContent.search(UserGuideL10n.string(item.titleKey))

        #expect(results.contains { $0.id == item.id && $0.topicID == .comparingPhotos })
    }

    /// `GuideContent.search` accepts an injectable localizer precisely so this test can supply
    /// fixed EN/UK strings and exercise the displayed text, not the dotted fallback key the string
    /// catalog resolves to under the SwiftPM test runner. This is what actually proves the search
    /// is case-folded and diacritic-insensitive across scripts.
    @Test("Search matches localized EN/UK text case- and diacritic-insensitively")
    func searchMatchesFixedLocalizedTextCaseAndDiacriticInsensitively() throws {
        let topic = GuideContent.topic(.comparingPhotos)
        let item = try #require(topic.sections.first?.items.first)
        let bodyKey = try #require(item.bodyKey)

        let fixedTitle = "Café Tap to Select"
        let fixedBody = "Торкніться, щоб вибрати фото"

        func fixedLocalizer(_ key: String.LocalizationValue) -> String {
            if key == item.titleKey { return fixedTitle }
            if key == bodyKey { return fixedBody }
            return "unrelated placeholder text"
        }

        // Case-folded English match against the diacritic-bearing title.
        let caseFolded = GuideContent.search("CAFE", localize: fixedLocalizer)
        #expect(caseFolded.contains { $0.id == item.id && $0.topicID == .comparingPhotos })

        // Diacritic-insensitive match: the query has no accent, the title does.
        let diacriticInsensitive = GuideContent.search("cafe", localize: fixedLocalizer)
        #expect(diacriticInsensitive.contains { $0.id == item.id })

        // Case-folded Ukrainian match against the body text.
        let ukrainianMatch = GuideContent.search("ТОРКНІТЬСЯ", localize: fixedLocalizer)
        #expect(ukrainianMatch.contains { $0.id == item.id })

        // A query absent from both fixed strings must not match.
        let noMatch = GuideContent.search("no-such-substring", localize: fixedLocalizer)
        #expect(!noMatch.contains { $0.id == item.id })
    }
}
