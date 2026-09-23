import SwiftUI

@main
struct CarLyricsApp: App {
    @StateObject private var auth: SpotifyAuth
    @StateObject private var engine: LyricsEngine
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let auth = SpotifyAuth()
        _auth = StateObject(wrappedValue: auth)
        _engine = StateObject(wrappedValue: LyricsEngine(auth: auth))
    }

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
