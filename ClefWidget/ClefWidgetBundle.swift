import WidgetKit
import SwiftUI

@main
struct ClefWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecentScoresWidget()
        FolderWidget()
    }
}
