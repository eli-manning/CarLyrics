import SwiftUI

enum Theme {
    static let accent = Color(red: 1.0, green: 0.82, blue: 0.25)
    static let background = Color(red: 0.05, green: 0.05, blue: 0.08)
}

struct LoginView: View {
    @EnvironmentObject private var auth: SpotifyAuth
    @EnvironmentObject private var engine: LyricsEngine
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "music.mic")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(Theme.accent)
            VStack(spacing: 8) {
                Text("CarLyrics").font(.largeTitle.bold())
                Text("Karaoke lyrics for whatever's playing on Spotify — on your Lock Screen and CarPlay.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task {
                    busy = true; defer { busy = false }
                    do {
                        try await auth.logIn()
                        engine.appBecameActive()
                    } catch { self.error = error.localizedDescription }
                }
            } label: {
                Label(busy ? "Connecting…" : "Connect Spotify", systemImage: "link")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green, in: .capsule)
                    .foregroundStyle(.black)
            }
            .disabled(busy)
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .background(Theme.background.ignoresSafeArea())
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var engine: LyricsEngine
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            LyricsScroller()
            controls
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showSettings) { SettingsView().presentationDetents([.medium]) }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AsyncImage(url: engine.track?.artworkURL) { img in
                img.resizable().scaledToFill()
            } placeholder: {
                Color.white.opacity(0.08).overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(engine.track?.title ?? "Nothing playing").font(.headline).lineLimit(1)
                Text(engine.track?.artistLine ?? "Play something in Spotify").font(.subheadline)
                    .foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3").font(.title3)
            }
            .tint(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if let err = engine.errorMessage {
                Text(err).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
            Button {
                engine.liveActivityOn ? engine.stopLiveActivity() : engine.startLiveActivity()
            } label: {
                Label(engine.liveActivityOn ? "Showing on CarPlay & Lock Screen" : "Show on CarPlay & Lock Screen",
                      systemImage: engine.liveActivityOn ? "car.fill" : "car")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(engine.liveActivityOn ? Theme.accent : Color.white.opacity(0.1), in: .capsule)
                    .foregroundStyle(engine.liveActivityOn ? .black : .primary)
            }
        }
        .padding(16)
    }
}

struct LyricsScroller: View {
    @EnvironmentObject private var engine: LyricsEngine

    var body: some View {
        Group {
            switch engine.status {
            case .idle: placeholder("Play a song in Spotify", icon: "play.circle")
            case .loading: ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notFound: placeholder("No lyrics found for this song", icon: "text.badge.xmark")
            case .instrumental: placeholder("Instrumental", icon: "pianokeys")
            case .found: lyricsList
            }
        }
    }

    private var lyricsList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    if engine.lyrics?.isSynced == false {
                        Label("Timing estimated — no synced lyrics for this song", systemImage: "clock.badge.questionmark")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(engine.lyrics?.lines ?? []) { line in
                        let state = lineState(line.id)
                        Text(line.text)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(state == .current ? Theme.accent : .white.opacity(state == .past ? 0.3 : 0.55))
                            .scaleEffect(state == .current ? 1.04 : 1, anchor: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                            .animation(.easeOut(duration: 0.25), value: state)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 200)
            }
            .onChange(of: engine.currentIndex) { _, idx in
                withAnimation(.easeInOut(duration: 0.4)) { proxy.scrollTo(idx ?? 0, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(engine.currentIndex ?? 0, anchor: .center) }
        }
    }

    private enum LineState { case past, current, upcoming }
    private func lineState(_ id: Int) -> LineState {
        guard let cur = engine.currentIndex else { return .upcoming }
        return id < cur ? .past : (id == cur ? .current : .upcoming)
    }

    private func placeholder(_ text: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40))
            Text(text)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var engine: LyricsEngine
    @EnvironmentObject private var auth: SpotifyAuth

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Text("Lyrics offset: \(engine.offsetMs >= 0 ? "+" : "")\(Int(engine.offsetMs)) ms")
                        Slider(value: $engine.offsetMs, in: -2000...2000, step: 100)
                    }
                    Button("Reset offset") { engine.offsetMs = 0 }
                } footer: {
                    Text("Positive shows lyrics earlier. Useful over Bluetooth, which adds audio delay.")
                }
                Section {
                    Toggle("Auto-show on CarPlay when app opens", isOn: engine.$autoStartLiveActivity)
                }
                Section {
                    Button("Log out of Spotify", role: .destructive) {
                        engine.stopLiveActivity()
                        auth.logOut()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
