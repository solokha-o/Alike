import SwiftUI

public struct PhotoLoadFailureView: View {
    private let retry: () -> Void

    public init(retry: @escaping () -> Void) {
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: Spacing.xxSmall) {
            Image(systemName: "icloud.slash")
                .font(.title3)
                .accessibilityHidden(true)

            Text(appLocalized("Photo preview unavailable"))
                .font(.caption2)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Button(action: retry) {
                Label(appLocalized("Retry"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint(Text(appLocalized("Try loading the photo again")))
        }
        .foregroundStyle(.secondary)
        .padding(Spacing.xxSmall)
        .accessibilityElement(children: .contain)
    }
}
