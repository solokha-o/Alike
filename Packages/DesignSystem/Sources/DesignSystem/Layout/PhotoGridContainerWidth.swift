import SwiftUI

extension EnvironmentValues {
    /// The width, in points, of the screen area that holds a photo grid.
    ///
    /// `PhotoGridColumnPreference` uses it to fit the column count to the width in
    /// regular size class. `nil` keeps the fixed regular range (2 to 5 columns).
    @Entry public var photoGridContainerWidth: CGFloat?
}

extension View {
    /// Measures this view's width and passes it to the photo grids inside, and to
    /// their toolbar column pickers, through ``EnvironmentValues/photoGridContainerWidth``.
    ///
    /// Apply it once per window or sheet, outside any `.toolbar`, so the picker and
    /// the grid agree on the column range.
    public func dsMeasuresPhotoGridWidth() -> some View {
        modifier(PhotoGridContainerWidthReader())
    }
}

private struct PhotoGridContainerWidthReader: ViewModifier {
    @State private var width: CGFloat?

    func body(content: Content) -> some View {
        content
            .environment(\.photoGridContainerWidth, width)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
    }
}
