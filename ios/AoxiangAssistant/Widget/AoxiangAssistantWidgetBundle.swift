import WidgetKit
import SwiftUI

@main
struct AoxiangAssistantWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        AoxiangWidget()
        AoxiangDailyWidget()
        AoxiangWeeklyWidget()
        AoxiangDailyMediumWidget()
    }
}
