import Foundation
import SwiftUI
import WidgetKit
import AoxiangCore

/// The extension has a deliberately narrow dependency: it reads the last
/// sanitized snapshot written by the main app and never imports AoxiangApp.
struct AoxiangWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct AoxiangWidgetProvider: TimelineProvider {
    private let reader: WidgetSnapshotReader

    init(reader: WidgetSnapshotReader? = nil) {
        if let reader {
            self.reader = reader
        } else if let fileURL = AoxiangSharedContainer.sharedSnapshotURL() {
            self.reader = FileWidgetSnapshotStore(fileURL: fileURL)
        } else {
            self.reader = UnavailableWidgetSnapshotStore()
        }
    }

    func placeholder(in context: Context) -> AoxiangWidgetEntry {
        AoxiangWidgetEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (AoxiangWidgetEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AoxiangWidgetEntry>) -> Void) {
        let nextRefresh = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [readEntry()], policy: .after(nextRefresh)))
    }

    private func readEntry() -> AoxiangWidgetEntry {
        let snapshot = try? reader.read()
        return AoxiangWidgetEntry(date: Date(), snapshot: snapshot ?? nil)
    }
}

struct AoxiangWidgetView: View {
    let entry: AoxiangWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.snapshot?.selectedSemesterName ?? "翱翔助手")
                .font(.headline)
            if let snapshot = entry.snapshot {
                Text("今日课程 \(snapshot.todayCourses.count) 门")
                Text("成绩 \(snapshot.gradeSummary.count) 门")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("打开 App 导入数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

struct AoxiangWidget: Widget {
    let kind = "AoxiangWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AoxiangWidgetProvider()) { entry in
            AoxiangWidgetView(entry: entry)
        }
        .configurationDisplayName("翱翔助手")
        .description("显示主 App 最近一次写入的本地快照")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
