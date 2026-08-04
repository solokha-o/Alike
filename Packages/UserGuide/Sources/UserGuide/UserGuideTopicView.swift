import SwiftUI
import DesignSystem
import NavigationKit

public struct UserGuideTopicView: View {
    private let topic: GuideTopic

    public init(topicID: GuideTopicID) {
        self.topic = GuideContent.topic(topicID)
    }

    public var body: some View {
        List {
            ForEach(topic.sections) { section in
                Section {
                    ForEach(section.items) { item in
                        GuideItemRow(item: item)
                    }
                } header: {
                    if let headerKey = section.headerKey {
                        Text(appLocalized(headerKey))
                    }
                } footer: {
                    if let footerKey = section.footerKey {
                        Text(appLocalized(footerKey))
                    }
                }
            }
        }
        .navigationTitle(Text(appLocalized(topic.titleKey)))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

#Preview("Topic — Cleanup") {
    RoutedNavigationStack {
        UserGuideTopicView(topicID: .cleanupQueue)
    }
}

#Preview("Topic — dark, large text") {
    RoutedNavigationStack {
        UserGuideTopicView(topicID: .comparingPhotos)
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}
