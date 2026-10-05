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
        let now = Date()
        let nextRefresh = now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [readEntry(at: now)], policy: .after(nextRefresh)))
    }

    private func readEntry(at date: Date = Date()) -> AoxiangWidgetEntry {
        AoxiangWidgetEntry(date: date, snapshot: try? reader.read())
    }
}

private enum AoxiangWidgetStyle {
    static let pagePadding: CGFloat = 14
    static let surfaceRadius: CGFloat = 22
    static let courseRadius: CGFloat = 14
    static let accent = Color(red: 0.10, green: 0.48, blue: 0.92)
    static let secondary = Color.primary.opacity(0.58)
    static let railColors: [Color] = [
        Color(red: 0.18, green: 0.55, blue: 0.95),
        Color(red: 0.18, green: 0.72, blue: 0.48),
        Color(red: 0.95, green: 0.56, blue: 0.18),
        Color(red: 0.88, green: 0.34, blue: 0.56),
        Color(red: 0.20, green: 0.68, blue: 0.68),
    ]
}

private struct AoxiangWidgetSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
#if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: AoxiangWidgetStyle.surfaceRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AoxiangWidgetStyle.surfaceRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: AoxiangWidgetStyle.surfaceRadius)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
                }
        }
#else
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AoxiangWidgetStyle.surfaceRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AoxiangWidgetStyle.surfaceRadius)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
            }
#endif
    }
}

private extension View {
    @ViewBuilder
    func aoxiangWidgetContainerBackground() -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget) { Color.clear }
        } else {
            self
        }
    }
}

private struct AoxiangWidgetCourseSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: AoxiangWidgetStyle.courseRadius))
    }
}

private func stableColor(for course: WidgetCourseSnapshot) -> Color {
    let value = course.name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
    return AoxiangWidgetStyle.railColors[abs(value) % AoxiangWidgetStyle.railColors.count]
}

private func weekdayName(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "zh_CN")
    let weekday = calendar.component(.weekday, from: date)
    return ["", "周日", "周一", "周二", "周三", "周四", "周五", "周六"][weekday]
}

private func contractDay(for date: Date) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    let weekday = calendar.component(.weekday, from: date)
    return weekday == 1 ? 7 : weekday - 1
}

private func courseTime(_ course: WidgetCourseSnapshot) -> String {
    if let timeRange = course.timeRange, !timeRange.isEmpty { return timeRange }
    guard !course.sections.isEmpty else { return "时间待定" }
    return "第\(course.sections.map(String.init).joined(separator: "、"))节"
}

private func courseMetadata(_ course: WidgetCourseSnapshot) -> String {
    let section = course.sections.isEmpty
        ? ""
        : "第\(course.sections.map(String.init).joined(separator: "、"))节"
    let values = [section, course.location, course.teacher].compactMap { value in
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
    return values.isEmpty ? "课程详情待更新" : values.joined(separator: " · ")
}

private struct WidgetCourseRow: View {
    let course: WidgetCourseSnapshot
    let compact: Bool

    var body: some View {
        AoxiangWidgetCourseSurface {
            HStack(spacing: compact ? 8 : 10) {
                Text(courseTime(course))
                    .font(compact ? .system(size: 10, weight: .medium) : .system(size: 11, weight: .medium))
                    .foregroundStyle(AoxiangWidgetStyle.secondary)
                    .monospacedDigit()
                    .frame(width: compact ? 48 : 54, alignment: .leading)
                    .lineLimit(2)
                RoundedRectangle(cornerRadius: 2)
                    .fill(stableColor(for: course))
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: compact ? 2 : 3) {
                    Text(course.name)
                        .font(compact ? .system(size: 12, weight: .semibold) : .system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(courseMetadata(course))
                        .font(compact ? .system(size: 9) : .system(size: 10))
                        .foregroundStyle(AoxiangWidgetStyle.secondary)
                        .lineLimit(compact ? 1 : 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 7 : 10)
        }
    }
}

private struct EmptyWidgetState: View {
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.title3)
                .foregroundStyle(AoxiangWidgetStyle.accent)
            Text(message)
                .font(.caption)
                .foregroundStyle(AoxiangWidgetStyle.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WidgetHeader: View {
    let title: String
    let trailing: String?
    let symbol: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AoxiangWidgetStyle.accent)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AoxiangWidgetStyle.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct DailyLargeWidgetView: View {
    let entry: AoxiangWidgetEntry

    var body: some View {
        AoxiangWidgetSurface {
            VStack(alignment: .leading, spacing: 10) {
                if let snapshot = entry.snapshot {
                    WidgetHeader(
                        title: "今天 / \(weekdayName(entry.date))",
                        trailing: snapshot.activeWeek.map { "第\($0)周" },
                        symbol: "calendar"
                    )
                    let courses = snapshot.todayCourses
                    if courses.isEmpty {
                        EmptyWidgetState(message: "今天没有安排课程")
                    } else {
                        VStack(spacing: 7) {
                            ForEach(Array(courses.prefix(4))) { course in
                                WidgetCourseRow(course: course, compact: false)
                            }
                        }
                        if courses.count > 4 {
                            Text("其他 \(courses.count - 4) 节课程")
                                .font(.caption)
                                .foregroundStyle(AoxiangWidgetStyle.secondary)
                        }
                    }
                } else {
                    EmptyWidgetState(message: "打开 App 导入数据")
                }
            }
            .padding(AoxiangWidgetStyle.pagePadding)
        }
        .aoxiangWidgetContainerBackground()
    }
}

private struct DailyMediumWidgetView: View {
    let entry: AoxiangWidgetEntry

    var body: some View {
        AoxiangWidgetSurface {
            VStack(alignment: .leading, spacing: 7) {
                if let snapshot = entry.snapshot {
                    WidgetHeader(
                        title: "今天 / \(weekdayName(entry.date))",
                        trailing: snapshot.activeWeek.map { "第\($0)周" },
                        symbol: "calendar"
                    )
                    let courses = snapshot.todayCourses
                    ForEach(Array(courses.prefix(2))) { course in
                        WidgetCourseRow(course: course, compact: true)
                    }
                    if courses.isEmpty {
                        Text("今天没有安排课程")
                            .font(.caption)
                            .foregroundStyle(AoxiangWidgetStyle.secondary)
                    } else if courses.count > 2 {
                        Text("其他 \(courses.count - 2) 节课程")
                            .font(.caption)
                            .foregroundStyle(AoxiangWidgetStyle.secondary)
                    }
                } else {
                    EmptyWidgetState(message: "打开 App 导入数据")
                }
            }
            .padding(AoxiangWidgetStyle.pagePadding)
        }
        .aoxiangWidgetContainerBackground()
    }
}

private struct WeeklyGridCell: View {
    let course: WidgetCourseSnapshot?

    var body: some View {
        Group {
            if let course {
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.name)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(2)
                    Text(course.location ?? "")
                        .font(.system(size: 8))
                        .foregroundStyle(AoxiangWidgetStyle.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(5)
                .background(stableColor(for: course).opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(stableColor(for: course))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.035))
            }
        }
        .frame(minHeight: 42, maxHeight: .infinity)
    }
}

private struct WeeklyLargeWidgetView: View {
    let entry: AoxiangWidgetEntry

    private var displayedDays: [Int] {
        let current = contractDay(for: entry.date)
        let start = min(max(current - 1, 1), 4)
        return Array(start...(start + 3))
    }

    private func courses(for day: Int) -> [WidgetCourseSnapshot] {
        entry.snapshot?.weekCourses.filter { $0.dayOfWeek == day }
            .sorted { ($0.sections.min() ?? Int.max) < ($1.sections.min() ?? Int.max) } ?? []
    }

    private func deepLink(day: Int, delta: Int) -> URL {
        var components = URLComponents()
        components.scheme = "aoxiang"
        components.host = "widget"
        components.path = "/week"
        components.queryItems = [
            URLQueryItem(name: "day", value: String(day)),
            URLQueryItem(name: "delta", value: String(delta)),
        ]
        return components.url!
    }

    var body: some View {
        AoxiangWidgetSurface {
            VStack(spacing: 7) {
                if let snapshot = entry.snapshot {
                    WidgetHeader(
                        title: snapshot.selectedSemesterName ?? "一周课表",
                        trailing: snapshot.activeWeek.map { "第\($0)周" },
                        symbol: "calendar"
                    )
                    HStack(spacing: 3) {
                        Text("时间")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(AoxiangWidgetStyle.secondary)
                            .frame(width: 34)
                        ForEach(displayedDays, id: \.self) { day in
                            Text(["一", "二", "三", "四", "五", "六", "日"][day - 1])
                                .font(.system(size: 10, weight: day == contractDay(for: entry.date) ? .bold : .medium))
                                .foregroundStyle(day == contractDay(for: entry.date) ? AoxiangWidgetStyle.accent : AoxiangWidgetStyle.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(0..<4, id: \.self) { row in
                        HStack(spacing: 3) {
                            Text("第\(row + 1)段")
                                .font(.system(size: 8))
                                .foregroundStyle(AoxiangWidgetStyle.secondary)
                                .frame(width: 34, alignment: .leading)
                            ForEach(displayedDays, id: \.self) { day in
                                WeeklyGridCell(course: courses(for: day).dropFirst(row).first)
                            }
                        }
                    }
                    HStack(spacing: 9) {
                        Link(destination: deepLink(day: displayedDays.first ?? 1, delta: -1)) {
                            Image(systemName: "chevron.left")
                        }
                        Link(destination: deepLink(day: displayedDays.first ?? 1, delta: -7)) {
                            Image(systemName: "chevron.up")
                        }
                        Link(destination: deepLink(day: displayedDays.last ?? 7, delta: 7)) {
                            Image(systemName: "chevron.down")
                        }
                        Link(destination: deepLink(day: displayedDays.last ?? 7, delta: 1)) {
                            Image(systemName: "chevron.right")
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AoxiangWidgetStyle.secondary)
                    .frame(maxWidth: .infinity)
                } else {
                    EmptyWidgetState(message: "打开 App 导入数据")
                }
            }
            .padding(11)
        }
        .aoxiangWidgetContainerBackground()
    }
}

private struct SummaryWidgetView: View {
    let entry: AoxiangWidgetEntry

    var body: some View {
        AoxiangWidgetSurface {
            VStack(alignment: .leading, spacing: 9) {
                WidgetHeader(title: entry.snapshot?.selectedSemesterName ?? "翱翔助手", trailing: nil, symbol: "sparkles")
                if let snapshot = entry.snapshot {
                    HStack(spacing: 7) {
                        SummaryMetric(title: "今日", value: "\(snapshot.todayCourses.count) 节", symbol: "calendar")
                        SummaryMetric(title: "成绩", value: "\(snapshot.gradeSummary.count) 门", symbol: "chart.bar")
                    }
                    HStack(spacing: 7) {
                        SummaryMetric(title: "GPA", value: snapshot.gradeSummary.gpa.map { String(format: "%.2f", $0) } ?? "--", symbol: "graduationcap")
                        SummaryMetric(title: "电费", value: snapshot.electricityBalance.map { String(format: "%.2f", $0) } ?? "--", symbol: "bolt")
                    }
                } else {
                    EmptyWidgetState(message: "打开 App 导入数据")
                }
            }
            .padding(AoxiangWidgetStyle.pagePadding)
        }
        .aoxiangWidgetContainerBackground()
    }
}

private struct SummaryMetric: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AoxiangWidgetStyle.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 9)).foregroundStyle(AoxiangWidgetStyle.secondary)
                Text(value).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AoxiangWidget: Widget {
    let kind = "AoxiangWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AoxiangWidgetProvider()) { entry in
            SummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("翱翔助手概览")
        .description("显示主 App 最近一次写入的本地快照")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct AoxiangDailyWidget: Widget {
    let kind = "AoxiangDailyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AoxiangWidgetProvider()) { entry in
            DailyLargeWidgetView(entry: entry)
        }
        .configurationDisplayName("每日课程纵览")
        .description("查看今天的课程、时间、地点和教师")
        .supportedFamilies([.systemLarge])
    }
}

struct AoxiangWeeklyWidget: Widget {
    let kind = "AoxiangWeeklyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AoxiangWidgetProvider()) { entry in
            WeeklyLargeWidgetView(entry: entry)
        }
        .configurationDisplayName("一周课程总览")
        .description("查看当前学周课程并打开 App 调整视图")
        .supportedFamilies([.systemLarge])
    }
}

struct AoxiangDailyMediumWidget: Widget {
    let kind = "AoxiangDailyMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AoxiangWidgetProvider()) { entry in
            DailyMediumWidgetView(entry: entry)
        }
        .configurationDisplayName("每日课程双行")
        .description("用两行显示今天最近的课程")
        .supportedFamilies([.systemMedium])
    }
}
