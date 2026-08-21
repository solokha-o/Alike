import Core
import SwiftUI

/// The photo-grid column count, resolved for the current horizontal size class
/// and persisted so the choice survives navigation and relaunch.
///
/// Every photo grid declares its own instance; because they all read the same
/// `UserDefaults` keys, a change made from one screen's toolbar is picked up by
/// the others.
@propertyWrapper
@MainActor
public struct PhotoGridColumnPreference: DynamicProperty {
    @AppStorage(AppPreferenceKey.PhotoGrid.compactColumns)
    private var compactColumns = AdaptivePhotoGridLayoutPolicy.compact.defaultColumnCount
    @AppStorage(AppPreferenceKey.PhotoGrid.regularColumns)
    private var regularColumns = AdaptivePhotoGridLayoutPolicy.regular.defaultColumnCount
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif

    public init() {}

    public var layoutPolicy: AdaptivePhotoGridLayoutPolicy {
#if os(iOS)
        .forHorizontalSizeClass(horizontalSizeClass)
#else
        .regular
#endif
    }

    public var wrappedValue: Int {
        get { layoutPolicy.clampedColumnCount(storedValue) }
        nonmutating set { storedValue = layoutPolicy.clampedColumnCount(newValue) }
    }

    public var projectedValue: Binding<Int> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }

    private var storedValue: Int {
        get {
#if os(iOS)
            horizontalSizeClass == .regular ? regularColumns : compactColumns
#else
            regularColumns
#endif
        }
        nonmutating set {
#if os(iOS)
            if horizontalSizeClass == .regular {
                regularColumns = newValue
            } else {
                compactColumns = newValue
            }
#else
            regularColumns = newValue
#endif
        }
    }
}

/// Toolbar control for choosing the photo-grid column count.
public struct PhotoGridColumnsMenu: View {
    @PhotoGridColumnPreference private var columns

    public init() {}

    public var body: some View {
        Menu {
            Picker(selection: $columns) {
                ForEach(_columns.layoutPolicy.columnCounts, id: \.self) { count in
                    Text(count, format: .number).tag(count)
                }
            } label: {
                Text(DesignSystemL10n.PhotoGridColumnPreference.columns2)
            }
        } label: {
            Image(systemName: "square.grid.3x2")
        }
        .accessibilityLabel(Text(DesignSystemL10n.PhotoGridColumnPreference.gridColumns))
        .accessibilityHint(Text(DesignSystemL10n.PhotoGridColumnPreference.chooseHowManyColumnsUsed))
    }
}

/// Picker-only variant of ``PhotoGridColumnsMenu`` for use inside an existing menu.
public struct PhotoGridColumnsPicker: View {
    @PhotoGridColumnPreference private var columns

    public init() {}

    public var body: some View {
        Picker(selection: $columns) {
            ForEach(_columns.layoutPolicy.columnCounts, id: \.self) { count in
                Text(String(format: DesignSystemL10n.PhotoGridColumnPreference.columns, count)).tag(count)
            }
        } label: {
            Label(DesignSystemL10n.PhotoGridColumnPreference.columns2, systemImage: "square.grid.3x2")
        }
        .pickerStyle(.menu)
    }
}
