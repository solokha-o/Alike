//
//  AlikeWidgetBundle.swift
//  AlikeWidgets
//

import SwiftUI
import WidgetKit

/// The extension's entry point.
///
/// One widget for now. The compositions from the design spec — "Можна очистити",
/// "Продовжити перегляд" and "Огляд бібліотеки" — arrive as additional members of
/// this bundle in the two follow-up cards; this one exists to prove the chain from
/// the app's snapshot write through to a deep link that lands back in the app.
@main
struct AlikeWidgetBundle: WidgetBundle {
    var body: some Widget {
        AlikeStatusWidget()
    }
}
