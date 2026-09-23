#!/usr/bin/env python3
"""Log in to Spotify on the Mac and hand the refresh token to CarLyrics on the iPhone.

Fallback for when Spotify's login page errors inside the app. Uses the
http://127.0.0.1:8888/callback redirect already registered on the Spotify app.

    python3 tools/login_on_mac.py <device-udid>
"""
import base64, hashlib, http.server, json, os, secrets, subprocess, sys, tempfile, urllib.parse, webbrowser

CLIENT_ID = "c74ded3599f44bdd9f7f187aab5a5beb"
REDIRECT = "http://127.0.0.1:8888/callback"
SCOPES = "user-read-currently-playing user-read-playback-state"
BUNDLE_ID = "com.elimanning.carlyrics"

device = sys.argv[1] if len(sys.argv) > 1 else sys.exit("usage: login_on_mac.py <device-udid>")
verifier = secrets.token_urlsafe(64)[:64]
challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
auth_url = "https://accounts.spotify.com/authorize?" + urllib.parse.urlencode({
    "client_id": CLIENT_ID, "response_type": "code", "redirect_uri": REDIRECT,
    "code_challenge_method": "S256", "code_challenge": challenge, "scope": SCOPES,
})

code = None
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        global code
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        code = q.get("code", [None])[0]
        self.send_response(200); self.send_header("Content-Type", "text/html"); self.end_headers()
        msg = "Logged in &mdash; you can close this tab." if code else f"Login failed: {q.get('error', ['?'])[0]}"
        self.wfile.write(f"<h2 style='font-family:sans-serif'>CarLyrics: {msg}</h2>".encode())
    def log_message(self, *a): pass

print("Opening Spotify login:\n" + auth_url, flush=True)
webbrowser.open(auth_url)
server = http.server.HTTPServer(("127.0.0.1", 8888), Handler)
while code is None:
    server.handle_request()
    if code is None: sys.exit("No code returned (login denied?)")

# curl uses the system trust store; some Python installs (e.g. PlatformIO's) have no CA certs.
body = urllib.parse.urlencode({"grant_type": "authorization_code", "code": code, "redirect_uri": REDIRECT,
                               "client_id": CLIENT_ID, "code_verifier": verifier})
tokens = json.loads(subprocess.run(["curl", "-sS", "https://accounts.spotify.com/api/token", "--data", body],
                                   check=True, capture_output=True, text=True).stdout)
if "refresh_token" not in tokens: sys.exit(f"Token exchange failed: {tokens}")

with tempfile.TemporaryDirectory() as d:
    path = os.path.join(d, "spotify_import.json")
    with open(path, "w") as f: json.dump({"refresh_token": tokens["refresh_token"]}, f)
    subprocess.run(["xcrun", "devicectl", "device", "copy", "to", "--device", device, "--source", path,
                    "--destination", "Documents/spotify_import.json", "--domain-type", "appDataContainer",
                    "--domain-identifier", BUNDLE_ID], check=True, stdout=subprocess.DEVNULL)
subprocess.run(["xcrun", "devicectl", "device", "process", "launch", "--terminate-existing", "--device", device, BUNDLE_ID],
               check=True, stdout=subprocess.DEVNULL)
print("Done — token copied to the phone and CarLyrics relaunched.")
