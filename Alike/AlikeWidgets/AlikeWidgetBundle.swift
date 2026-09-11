//
//  AlikeWidgetBundle.swift
//  AlikeWidgets
//

import SwiftUI
import WidgetKit

/// The extension's entry point.
///
/// Two widgets, which is the whole of the chosen set. `AlikeStatusWidget` answers "is
/// there anything to do" — "Можна очистити" and "Продовжити перегляд", small and medium;
/// `AlikeLibraryWidget` answers "what is in there" — "Огляд бібліотеки", medium only.
/// They are separate entries in the gallery because they are separate questions, and
/// because three per-row `Link`s cannot live under the status widget's single
/// `widgetURL`.
@main
struct AlikeWidgetBundle: WidgetBundle {
    var body: some Widget {
        AlikeStatusWidget()
        AlikeLibraryWidget()
    }
}
