import Foundation
import AoxiangCore

#if os(iOS) && canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers

public struct AoxiangRootView: View {
    @StateObject private var model: OfflineAppViewModel

    public init(model: OfflineAppViewModel) {
        _model = StateObject(wrappedValue: model)
    }

    public var body: some View {
        TabView(selection: $model.selectedTab) {
            HomeScreen(model: model).tabItem { Label("首页", systemImage: "house") }.tag(OfflineAppViewModel.Tab.home)
            GradesScreen(model: model).tabItem { Label("成绩", systemImage: "chart.bar") }.tag(OfflineAppViewModel.Tab.grades)
            ScheduleScreen(model: model).tabItem { Label("课表", systemImage: "calendar") }.tag(OfflineAppViewModel.Tab.schedule)
            ManagementScreen(model: model).tabItem { Label("管理", systemImage: "slider.horizontal.3") }.tag(OfflineAppViewModel.Tab.management)
        }
        .alert("操作未完成", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("确定", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
    }
}

public struct HomeScreen: View {
    @ObservedObject var model: OfflineAppViewModel
    public init(model: OfflineAppViewModel) { self.model = model }

    private var todayCourses: [OfflineCourse] {
        let calendar = OfflineDatePolicy.businessCalendar
        let weekday = calendar.component(.weekday, from: Date())
        let day = weekday == 1 ? 7 : weekday - 1
        guard let semester = model.state.semesters.first(where: {
            $0.id == model.state.selectedSemesterId
        }), let week = OfflineScheduleService.academicWeek(
            for: Date(), semester: semester, calendar: calendar
        ) else {
            return []
        }
        return OfflineScheduleService.courses(on: day, week: week, in: model.state)
    }

    public var body: some View {
        NavigationView {
            List {
                Section("当前学期") {
                    Text(model.state.semesters.first { $0.id == model.state.selectedSemesterId }?.name ?? "未选择学期")
                    Text("课程 \(model.state.courses.count) 门 · 成绩 \(model.state.grades.count) 门")
                        .foregroundColor(.secondary)
                }
                Section("今日课程") {
                    if todayCourses.isEmpty { Text("暂无本地课程").foregroundColor(.secondary) }
                    ForEach(todayCourses.prefix(5)) { course in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(course.name).font(.headline)
                            Text([course.teacher, course.location].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("翱翔助手")
        }
    }
}

public struct GradesScreen: View {
    @ObservedObject var model: OfflineAppViewModel
    @State private var showingImporter = false
    @State private var showingGradeEditor = false
    @State private var editingGrade: OfflineGrade?
    public init(model: OfflineAppViewModel) { self.model = model }

    public var body: some View {
        NavigationView {
            List {
                if model.state.grades.isEmpty {
                    Text("暂无本地成绩").foregroundColor(.secondary)
                } else {
                    ForEach(model.state.grades) { grade in
                        Button { editingGrade = grade } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(grade.course)
                                    Text(grade.category).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(grade.score.map { String(format: "%.0f", $0) } ?? "--")
                                    .font(.headline)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        let ids = offsets.compactMap { index in
                            model.state.grades.indices.contains(index)
                                ? model.state.grades[index].id
                                : nil
                        }
                        ids.forEach { model.deleteGrade(id: $0) }
                    }
                }
            }
            .navigationTitle("成绩")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showingGradeEditor = true } label: {
                        Label("新增成绩", systemImage: "plus")
                    }
                    Button { showingImporter = true } label: {
                        Label("导入成绩", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                do {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    model.importGrades(data: try Data(contentsOf: url))
                } catch {
                    model.importGrades(data: Data())
                }
            }
            .sheet(isPresented: $showingGradeEditor) {
                GradeEditorSheet(model: model, grade: nil)
            }
            .sheet(item: $editingGrade) { grade in
                GradeEditorSheet(model: model, grade: grade)
            }
        }
    }
}

public struct ScheduleScreen: View {
    @ObservedObject var model: OfflineAppViewModel
    public init(model: OfflineAppViewModel) { self.model = model }

    public var body: some View {
        NavigationView {
            List {
                let courses = model.state.courses.filter { $0.semesterId == model.state.selectedSemesterId }
                if courses.isEmpty {
                    Text("暂无本地课表").foregroundColor(.secondary)
                } else {
                    ForEach(courses) { course in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(course.name).font(.headline)
                            ForEach(Array(course.timeSlots.enumerated()), id: \.offset) { _, slot in
                                Text("周\(slot.dayOfWeek) · 第\(slot.classSections.map(String.init).joined(separator: ","))节 · \(slot.repeatRule.rawValue.isEmpty ? "每周" : slot.repeatRule.rawValue)")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("课表")
        }
    }
}

public struct ManagementScreen: View {
    @ObservedObject var model: OfflineAppViewModel
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingAddCourse = false
    @State private var editingCourse: OfflineCourse?
    @State private var exportDocument = BackupFileDocument(data: Data())
    @State private var showingAuthentication = false
    @State private var collectionTask: Task<Void, Never>?
    @State private var collectionStatus: String?
    @State private var isCollecting = false
    @StateObject private var authenticationModel: VisibleAuthenticationViewModel

    public init(model: OfflineAppViewModel) {
        self.model = model
        _authenticationModel = StateObject(wrappedValue: VisibleAuthenticationViewModel(
            loginURL: URL(string: "https://jwxt.nwpu.edu.cn/student/sso-login")!,
            successRule: .jwxtStudentHome,
            sessionStore: model.authenticationStore
        ))
    }

    public var body: some View {
        NavigationView {
            List {
                Section("认证") {
                    HStack {
                        Text(authenticationStatusText)
                        Spacer()
                        Button("打开统一认证") { showingAuthentication = true }
                    }
                    if let collectionStatus {
                        Text(collectionStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if authenticationModel.state == .authenticated || authenticationModel.state == .readyToCollect {
                        Button {
                            beginCollection()
                        } label: {
                            Label(
                                isCollecting ? "正在采集" : "开始采集",
                                systemImage: isCollecting ? "hourglass" : "arrow.clockwise"
                            )
                        }
                        .disabled(isCollecting)
                    }
                }
                Section("数据") {
                    Button { showingImporter = true } label: { Label("导入 Android 备份", systemImage: "square.and.arrow.down") }
                    Button {
                        guard let data = model.exportBackup() else { return }
                        exportDocument = BackupFileDocument(data: data)
                        showingExporter = true
                    } label: { Label("导出可移植备份", systemImage: "square.and.arrow.up") }
                }
                Section("学期") {
                    if model.state.semesters.isEmpty {
                        Text("暂无学期").foregroundColor(.secondary)
                    } else {
                        ForEach(model.state.semesters) { semester in
                            Button {
                                model.setSelectedSemester(semester.id)
                            } label: {
                                HStack {
                                    Text(semester.name)
                                    Spacer()
                                    if semester.id == model.state.selectedSemesterId { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    }
                }
                Section("本地编辑") {
                    Button { showingAddCourse = true } label: { Label("新增课程", systemImage: "plus") }
                    ForEach(model.state.courses) { course in
                        HStack {
                            Button { editingCourse = course } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(course.name)
                                    Text(course.semesterId).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button(role: .destructive) { model.deleteCourse(id: course.id) } label: { Image(systemName: "trash") }
                        }
                    }
                }
            }
            .navigationTitle("管理")
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                do {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    model.importBackup(data: try Data(contentsOf: url))
                } catch { model.importBackup(data: Data()) }
            }
            .fileExporter(isPresented: $showingExporter, document: exportDocument, contentType: .json, defaultFilename: "aoxiang-backup") { _ in }
            .sheet(isPresented: $showingAddCourse) { AddCourseSheet(model: model) }
            .sheet(item: $editingCourse) { course in EditCourseSheet(model: model, course: course) }
            .sheet(isPresented: $showingAuthentication) {
                AuthenticationScreen(model: authenticationModel, onPrepareToCollect: beginCollection)
            }
            .onDisappear {
                collectionTask?.cancel()
            }
        }
    }

    private func beginCollection() {
        guard !isCollecting else { return }
        if authenticationModel.state == .authenticated {
            authenticationModel.prepareToCollect()
        }
        guard authenticationModel.state == .readyToCollect else {
            collectionStatus = "请先完成统一认证"
            return
        }
        isCollecting = true
        collectionStatus = "正在读取成绩、课表和电费…"
        let cookieStore = authenticationModel.webView.configuration.websiteDataStore.httpCookieStore
        let collector = PortalForegroundCollector(
            transport: PortalCollectionTransportAdapter(
                port: URLSessionHTTPCollectionAdapter(cookieStore: cookieStore)
            ),
            electricityProvider: { try await authenticationModel.collectElectricityBalance() },
            portraitProvider: { try await authenticationModel.collectPortraitHTML() }
        )
        collectionTask?.cancel()
        collectionTask = Task { @MainActor in
            defer {
                isCollecting = false
                collectionTask = nil
            }
            do {
                let result = try await collector.collect(state: .readyToCollect)
                guard !Task.isCancelled else { return }
                if model.applyPortalCollection(result) {
                    collectionStatus = "采集完成，已更新本地数据和小组件快照"
                } else {
                    collectionStatus = "采集结果未能保存；原有数据保持不变"
                }
            } catch let failure as PortalCollectionFailure {
                authenticationModel.recordCollectionFailure(failure)
                collectionStatus = failure.localizedDescription
            } catch {
                collectionStatus = error.localizedDescription
            }
        }
    }

    private var authenticationStatusText: String {
        switch authenticationModel.state {
        case .needsLogin: return "需要登录"
        case .needsSMS: return "需要短信验证"
        case .authenticated: return "认证成功，待准备采集"
        case .readyToCollect: return "可继续采集"
        case .retryableFailure: return "可重试失败"
        case .needsUserAttention: return "需要处理"
        }
    }
}

private struct AddCourseSheet: View {
    @ObservedObject var model: OfflineAppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedSemesterID = ""

    var body: some View {
        NavigationView {
            Form {
                TextField("课程名称", text: $name)
                Picker("所属学期", selection: $selectedSemesterID) {
                    ForEach(model.state.semesters) { Text($0.name).tag($0.id) }
                }
            }
            .navigationTitle("新增课程")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              !selectedSemesterID.isEmpty else { return }
                        if model.addCourse(name: name, semesterId: selectedSemesterID) {
                            dismiss()
                        }
                    }
                }
            }
            .onAppear { selectedSemesterID = model.state.selectedSemesterId }
        }
    }
}

private struct EditCourseSheet: View {
    @ObservedObject var model: OfflineAppViewModel
    @Environment(\.dismiss) private var dismiss
    private let course: OfflineCourse
    @State private var name: String
    @State private var semesterID: String

    init(model: OfflineAppViewModel, course: OfflineCourse) {
        self.model = model
        self.course = course
        _name = State(initialValue: course.name)
        _semesterID = State(initialValue: course.semesterId)
    }

    var body: some View {
        NavigationView {
            Form {
                TextField("课程名称", text: $name)
                Picker("所属学期", selection: $semesterID) {
                    ForEach(model.state.semesters) { Text($0.name).tag($0.id) }
                }
            }
            .navigationTitle("编辑课程")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              !semesterID.isEmpty else { return }
                        var updated = course
                        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.semesterId = semesterID
                        if model.updateCourse(updated) { dismiss() }
                    }
                }
            }
        }
    }
}

private struct GradeEditorSheet: View {
    @ObservedObject var model: OfflineAppViewModel
    @Environment(\.dismiss) private var dismiss
    private let existingGrade: OfflineGrade?
    @State private var course: String
    @State private var credits: String
    @State private var score: String
    @State private var point: String
    @State private var validationMessage: String?

    init(model: OfflineAppViewModel, grade: OfflineGrade?) {
        self.model = model
        self.existingGrade = grade
        _course = State(initialValue: grade?.course ?? "")
        _credits = State(initialValue: grade.map { String($0.credits) } ?? "0")
        _score = State(initialValue: grade?.score.map { String($0) } ?? "")
        _point = State(initialValue: grade?.point.map { String($0) } ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                TextField("课程名称", text: $course)
                TextField("学分", text: $credits)
                    .keyboardType(.decimalPad)
                TextField("成绩（可留空）", text: $score)
                    .keyboardType(.decimalPad)
                TextField("绩点（可留空）", text: $point)
                    .keyboardType(.decimalPad)
                if let validationMessage {
                    Text(validationMessage).foregroundColor(.red)
                }
            }
            .navigationTitle(existingGrade == nil ? "新增成绩" : "编辑成绩")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
        }
    }

    private func save() {
        let name = course.trimmingCharacters(in: .whitespacesAndNewlines)
        let scoreResult = optionalNumber(score)
        let pointResult = optionalNumber(point)
        guard !name.isEmpty,
              let creditValue = Double(credits.trimmingCharacters(in: .whitespacesAndNewlines)),
              scoreResult.isValid,
              pointResult.isValid else {
            validationMessage = "请填写有效的课程名称、学分、成绩和绩点。"
            return
        }
        let scoreValue = scoreResult.value
        let pointValue = pointResult.value
        let didSave: Bool
        if var grade = existingGrade {
            grade.course = name
            grade.credits = creditValue
            grade.score = scoreValue
            grade.point = pointValue
            didSave = model.updateGrade(grade)
        } else {
            didSave = model.addGrade(
                course: name,
                score: scoreValue,
                point: pointValue,
                credits: creditValue
            )
        }
        if didSave { dismiss() }
    }

    private func optionalNumber(_ text: String) -> (isValid: Bool, value: Double?) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return (true, nil) }
        guard let value = Double(normalized) else { return (false, nil) }
        return (true, value)
    }
}

public struct BackupFileDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.json] }
    public var data: Data

    public init(data: Data) { self.data = data }
    public init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
#endif
