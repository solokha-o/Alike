import SwiftUI
import DesignSystem
import NavigationKit

struct UserGuideTopicView: View {
    let topic: GuideTopic

    var body: some View {
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
        UserGuideTopicView(topic: GuideContent.topic(.cleanupQueue))
    }
}

#Preview("Topic — dark, large text") {
    RoutedNavigationStack {
        UserGuideTopicView(topic: GuideContent.topic(.comparingPhotos))
    }
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}
