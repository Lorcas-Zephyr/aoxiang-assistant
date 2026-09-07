import SwiftUI
import AoxiangApp
import AoxiangCore

@main
@MainActor
struct AoxiangAssistantEntryPoint: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: OfflineAppViewModel
    @StateObject private var lifecycle: IOSApplicationLifecycle

    init() {
        let authenticationStore = AuthenticationSessionStore()
        let model = OfflineAppViewModel.makeDefault(authenticationStore: authenticationStore)
        _model = StateObject(wrappedValue: model)
        _lifecycle = StateObject(wrappedValue: IOSApplicationLifecycle(authenticationStore: authenticationStore))
    }

    var body: some Scene {
        WindowGroup {
            AoxiangRootView(model: model)
        }
        .onChange(of: scenePhase) { phase in
            lifecycle.scenePhaseChanged(phase)
        }
    }
}
