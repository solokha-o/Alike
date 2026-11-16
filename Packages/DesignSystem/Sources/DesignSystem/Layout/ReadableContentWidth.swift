import SwiftUI

/// The widest a column of cards, lists or text should get on iPad.
///
/// The iPad audit showed Cleanup, History, Details, Settings and the guide
/// stretching to the full window, up to 1376 pt. Scanner (620 pt) and the
/// onboarding pages (560 pt) already keep a narrower column.
public enum ReadableContentWidth {
    public static let maximum: CGFloat = 720

#if os(iOS)
    /// The column width for a size class: ``maximum`` in regular width, no limit
    /// in compact width, so iPhone layout does not change.
    public static func maximum(for sizeClass: UserInterfaceSizeClass?) -> CGFloat? {
        sizeClass == .regular ? maximum : nil
    }

    /// The side margin that keeps scroll content, such as `List` rows, at most
    /// ``maximum`` wide in a container of `containerWidth`. `nil` keeps the system
    /// margin: in compact width, and when the container is not wider than the
    /// column plus the system margin.
    public static func scrollContentMargin(
        containerWidth: CGFloat?,
        sizeClass: UserInterfaceSizeClass?
    ) -> CGFloat? {
        guard sizeClass == .regular, let containerWidth, containerWidth.isFinite else { return nil }
        let margin = ((containerWidth - maximum) / 2).rounded(.down)
        return margin > minimumScrollContentMargin ? margin : nil
    }

    /// Below this, the system margin of a list is wider, so it stays.
    static let minimumScrollContentMargin: CGFloat = 20
#endif
}

extension View {
    /// Keeps the content at most ``ReadableContentWidth/maximum`` wide and centred
    /// in regular width. In compact width both frames are unconstrained, so the
    /// layout is the same as without the modifier.
    public func dsReadableContentWidth() -> some View {
        modifier(ReadableContentWidthModifier())
    }
}

#if os(iOS)
extension View {
    /// Keeps the rows of a `List` or `ScrollView` at most
    /// ``ReadableContentWidth/maximum`` wide in regular width with side margins,
    /// so the scroll area and its indicator still use the full width. In compact
    /// width the system margins stay, so iPhone layout does not change.
    public func dsReadableScrollContentMargins() -> some View {
        modifier(ReadableScrollContentMarginsModifier())
    }
}

private struct ReadableScrollContentMarginsModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var width: CGFloat?

    func body(content: Content) -> some View {
        content
            .contentMargins(
                .horizontal,
                ReadableContentWidth.scrollContentMargin(containerWidth: width, sizeClass: horizontalSizeClass),
                for: .scrollContent
            )
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
    }
}
#endif

private struct ReadableContentWidthModifier: ViewModifier {
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var limit: CGFloat? {
        ReadableContentWidth.maximum(for: horizontalSizeClass)
    }
#else
    private var limit: CGFloat? {
        ReadableContentWidth.maximum
    }
#endif

    func body(content: Content) -> some View {
        let maximum = limit
        content
            .frame(maxWidth: maximum)
            .frame(maxWidth: maximum == nil ? nil : .infinity)
    }
}
