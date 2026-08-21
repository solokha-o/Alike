import SwiftUI
import DesignSystem
import NavigationKit

/// The guide hub. It owns no navigation of its own: the enclosing stack supplies the route type,
/// so the same hub can be pushed inside Settings and presented as a sheet from Scanner.
public struct UserGuideHubView<Route: Hashable>: View {
    @State private var query = ""

    private let route: (GuideTopicID) -> Route

    public init(route: @escaping (GuideTopicID) -> Route) {
        self.route = route
    }

    private var results: [GuideSearchResult] {
        GuideContent.search(query)
    }

    public var body: some View {
        List {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                topicsContent
            } else {
                resultsContent
            }
        }
        .searchable(text: $query, prompt: Text(UserGuideL10n.Hub.searchprompt))
        .navigationTitle(Text(UserGuideL10n.UserGuideHub.howToUse))
#if os(iOS)
        .navigationBarTitleDisplayMode(.large)
#endif
    }

    @ViewBuilder
    private var topicsContent: some View {
        Section {
            Text(UserGuideL10n.Hub.intro)
                .font(.appBody)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Spacing.xxxSmall)
        }

        Section {
            ForEach(GuideContent.topics) { topic in
                NavigationLink(value: route(topic.id)) {
                    GuideTopicRow(topic: topic)
                }
                .accessibilityHint(Text(UserGuideL10n.Hub.topicHint))
            }
        } header: {
            Text(UserGuideL10n.Hub.topicsHeader)
        } footer: {
            Text(UserGuideL10n.Hub.footer)
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if results.isEmpty {
            Section {
                ContentUnavailableView(
                    UserGuideL10n.Hub.noresults,
                    systemImage: "magnifyingglass",
                    description: Text(UserGuideL10n.Hub.noresultsMessage)
                )
            }
            .listRowBackground(Color.clear)
        } else {
            Section {
                ForEach(results) { result in
                    NavigationLink(value: route(result.topicID)) {
                        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                            Text(UserGuideL10n.string(result.item.titleKey))
                                .font(.appHeadline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(UserGuideL10n.string(result.topicTitleKey))
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
    RoutedNavigationStack { (_: StackRouter<GuideRoute>) in
        UserGuideHubView { GuideRoute.topic($0) }
    } destination: { (route: GuideRoute, _) in
        if case .topic(let id) = route {
            UserGuideTopicView(topicID: id)
        }
    }
}
