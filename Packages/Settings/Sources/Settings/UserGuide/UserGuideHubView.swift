import SwiftUI
import DesignSystem
import NavigationKit

struct UserGuideHubView: View {
    @State private var query = ""

    private var results: [GuideSearchResult] {
        GuideContent.search(query)
    }

    var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                topicsContent
            } else {
                resultsContent
            }
        }
        .searchable(text: $query, prompt: Text(appLocalized("guide.hub.searchPrompt")))
        .navigationTitle(Text(appLocalized("How to Use")))
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
    }

    @ViewBuilder
    private var topicsContent: some View {
        Section {
            Text(appLocalized("guide.hub.intro"))
                .font(.appBody)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Spacing.xxxSmall)
        }

        Section {
            ForEach(GuideContent.topics) { topic in
                NavigationLink(value: SettingsRoute.userGuideTopic(topic.id)) {
                    GuideTopicRow(topic: topic)
                }
                .accessibilityHint(Text(appLocalized("guide.hub.topic.hint")))
            }
        } header: {
            Text(appLocalized("guide.hub.topics.header"))
        } footer: {
            Text(appLocalized("guide.hub.footer"))
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if results.isEmpty {
            Section {
                ContentUnavailableView(
                    appLocalized("guide.hub.noResults"),
                    systemImage: "magnifyingglass",
                    description: Text(appLocalized("guide.hub.noResults.message"))
                )
            }
            .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(results) { result in
                    NavigationLink(value: SettingsRoute.userGuideTopic(result.topicID)) {
                        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                            Text(appLocalized(result.item.titleKey))
                                .font(.appHeadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(appLocalized(result.topicTitleKey))
                                .font(.appCaption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, Spacing.xxxSmall)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

#Preview("Guide hub") {
    RoutedNavigationStack { (_: StackRouter<SettingsRoute>) in
        UserGuideHubView()
    } destination: { (route: SettingsRoute, _) in
        if case .userGuideTopic(let id) = route {
            UserGuideTopicView(topic: GuideContent.topic(id))
        }
    }
}
