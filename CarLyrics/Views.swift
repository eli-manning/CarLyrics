import SwiftUI

private let lyricFont = Font.system(size: 30, weight: .bold)

/// Blurred album art over a color sampled from it, like the Apple Music lyrics screen.
struct ArtworkBackdrop: View {
    let image: UIImage?
    let tintHex: String

    var body: some View {
        ZStack {
            Color(hex: tintHex)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 70)
                    .opacity(0.45)
                    .scaleEffect(1.4)
            }
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

struct LoginView: View {
    @EnvironmentObject private var auth: SpotifyAuth
    @EnvironmentObject private var engine: LyricsEngine
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CarLyrics")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 24)

            Spacer()

            // A preview of what the lyrics screen does.
            VStack(alignment: .leading, spacing: 14) {
                Text("Lyrics for whatever").foregroundStyle(.white.opacity(0.3))
                Text("you're playing on Spotify,").foregroundStyle(.white)
                Text("one line at a time.").foregroundStyle(.white.opacity(0.3))
            }
            .font(lyricFont)

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Text("They follow along on your Lock Screen and in CarPlay.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))

                Button {
                    Task {
                        busy = true; defer { busy = false }
                        do {
                            try await auth.logIn()
                            engine.appBecameActive()
                        } catch { self.error = error.localizedDescription }
                    }
                } label: {
                    Text(busy ? "Connecting…" : "Connect Spotify")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white, in: .rect(cornerRadius: 14))
                        .foregroundStyle(.black)
                }
                .disabled(busy)

                if let error {
                    Text(error).font(.footnote).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ArtworkBackdrop(image: nil, tintHex: Color.defaultTintHex))
    }
}

struct NowPlayingView: View {
    @EnvironmentObject private var engine: LyricsEngine
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            LyricsScroller()
                .mask(LinearGradient(stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.85), .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom))
            footer
        }
        .background(ArtworkBackdrop(image: engine.artwork, tintHex: engine.tintHex))
        .sheet(isPresented: $showSettings) { SettingsView().presentationDetents([.medium, .large]) }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Group {
                if let art = engine.artwork {
                    Image(uiImage: art).resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.1)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(.rect(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(engine.track?.title ?? "Nothing playing")
                    .font(.system(size: 16, weight: .semibold))
                Text(engine.track?.artistLine ?? "Play something on Spotify")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)

            Spacer()

            Button { showSettings = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.12), in: .circle)
            }
            .accessibilityLabel("Settings")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let err = engine.errorMessage {
                Text(err).font(.footnote).foregroundStyle(.white.opacity(0.75))
            }
            Toggle(isOn: Binding(
                get: { engine.liveActivityOn },
                set: { $0 ? engine.startLiveActivity() : engine.stopLiveActivity() }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show in CarPlay").font(.system(size: 15, weight: .semibold))
                    Text("Also appears on your Lock Screen")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .tint(.white.opacity(0.35))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.black.opacity(0.2), in: .rect(cornerRadius: 14))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}

struct LyricsScroller: View {
    @EnvironmentObject private var engine: LyricsEngine

    var body: some View {
        switch engine.status {
        case .idle: message("Play something on Spotify and the lyrics will show up here.")
        case .loading: message("Looking up lyrics…")
        case .notFound: message("Couldn't find lyrics for this song.")
        case .instrumental: message("Instrumental")
        case .found: lyricsList
        }
    }

    private var lyricsList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    if engine.lyrics?.isSynced == false {
                        Text("These lyrics aren't synced, so the timing is a guess.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    ForEach(engine.lyrics?.lines ?? []) { line in
                        let isCurrent = line.id == engine.currentIndex
                        Text(line.text)
                            .font(lyricFont)
                            .foregroundStyle(.white.opacity(isCurrent ? 1 : 0.32))
                            .blur(radius: isCurrent ? 0 : 0.4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                            .animation(.easeOut(duration: 0.3), value: isCurrent)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 220)
            }
            .onChange(of: engine.currentIndex) { _, idx in
                withAnimation(.spring(duration: 0.5)) { proxy.scrollTo(idx ?? 0, anchor: UnitPoint(x: 0, y: 0.35)) }
            }
            .onAppear { proxy.scrollTo(engine.currentIndex ?? 0, anchor: UnitPoint(x: 0, y: 0.35)) }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(lyricFont)
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var engine: LyricsEngine
    @EnvironmentObject private var auth: SpotifyAuth

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Timing offset") {
                        Text(engine.offsetMs == 0 ? "None" : String(format: "%+.1f s", engine.offsetMs / 1000))
                            .monospacedDigit()
                    }
                    Slider(value: $engine.offsetMs, in: -2000...2000, step: 100)
                    if engine.offsetMs != 0 {
                        Button("Reset") { engine.offsetMs = 0 }
                    }
                } footer: {
                    Text("If lyrics show up after the singer, slide right. Bluetooth audio usually runs a little behind.")
                }
                Section {
                    Toggle("Start when I open the app", isOn: engine.$autoStartLiveActivity)
                } footer: {
                    Text("Turns on the CarPlay lyrics card automatically.")
                }
                Section {
                    Button("Log out of Spotify", role: .destructive) {
                        engine.stopLiveActivity()
                        auth.logOut()
                    }
                } footer: {
                    Text("Lyrics come from LRCLIB.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

