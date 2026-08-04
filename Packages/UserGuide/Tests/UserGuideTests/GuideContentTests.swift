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
    /// resolves — under `swift test`, `appLocalized` sees the test bundle rather than the app.
    @Test("Search finds a row by its own title and reports the owning topic")
    func searchFindsRowsByTitle() throws {
        let topic = GuideContent.topic(.comparingPhotos)
        let item = try #require(topic.sections.first?.items.first)

        let results = GuideContent.search(appLocalized(item.titleKey))

        #expect(results.contains { $0.id == item.id && $0.topicID == .comparingPhotos })
    }
}
