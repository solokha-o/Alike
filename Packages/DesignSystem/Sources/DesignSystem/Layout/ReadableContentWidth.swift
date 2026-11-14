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
