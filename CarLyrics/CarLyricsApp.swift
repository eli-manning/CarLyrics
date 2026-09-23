import SwiftUI

@main
struct CarLyricsApp: App {
    @ObservedObject private var auth = AppModel.auth
    @ObservedObject private var engine = AppModel.engine
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isLoggedIn {
                    NowPlayingView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(auth)
            .environmentObject(engine)
            .preferredColorScheme(.dark)
            .onOpenURL { auth.handle($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: engine.appBecameActive()
            case .background: engine.appEnteredBackground()
            default: break
            }
        }
    }
}
