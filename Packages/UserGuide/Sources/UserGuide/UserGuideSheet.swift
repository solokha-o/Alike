import SwiftUI
import DesignSystem
import NavigationKit

/// Route type for the guide's own navigation stack, used when the guide is presented modally.
enum GuideRoute: Hashable {
    case topic(GuideTopicID)
}

/// The guide as a self-contained modal: hub at the root, topics pushed on top, and its own
/// dismissal. Callers only present it — they own no guide state.
public struct UserGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        RoutedNavigationStack { (_: StackRouter<GuideRoute>) in
            UserGuideHubView { GuideRoute.topic($0) }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(Text(UserGuideL10n.UserGuideSheet.close))
                    }
                }
        } destination: { route, _ in
            if case .topic(let id) = route {
                UserGuideTopicView(topicID: id)
            }
        }
#if os(iOS)
        .presentationDetents([.large])
#endif
    }
}

#Preview("Guide sheet") {
    Color.clear.sheet(isPresented: .constant(true)) {
        UserGuideSheet()
    }
}
