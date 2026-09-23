#!/usr/bin/env python3
"""Log in to Spotify on the Mac and hand the refresh token to CarLyrics on the iPhone.

Fallback for when Spotify's login page errors inside the app. Uses the
http://127.0.0.1:8888/callback redirect already registered on the Spotify app.

    python3 tools/login_on_mac.py <device-udid>
    python3 tools/login_on_mac.py --simulator <simulator-udid>
"""
import base64, hashlib, http.server, json, os, secrets, subprocess, sys, tempfile, urllib.parse, webbrowser

def read_config():
    """Reads CARLYRICS_* values from Config.xcconfig (falling back to Base.xcconfig)."""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    values = {}
    for name in ("Base.xcconfig", "Config.xcconfig"):
        path = os.path.join(root, name)
        if not os.path.exists(path): continue
        for line in open(path):
            line = line.split("//")[0].strip()
            if "=" in line and not line.startswith("#"):
                key, value = (part.strip() for part in line.split("=", 1))
                values[key] = value
    return values

config = read_config()
CLIENT_ID = config.get("CARLYRICS_SPOTIFY_CLIENT_ID", "")
BUNDLE_ID = config.get("CARLYRICS_BUNDLE_ID", "")
if not CLIENT_ID or CLIENT_ID == "your_spotify_client_id":
    sys.exit("Set CARLYRICS_SPOTIFY_CLIENT_ID in Config.xcconfig first (copy Config.example.xcconfig).")
REDIRECT = "http://127.0.0.1:8888/callback"
SCOPES = "user-read-currently-playing user-read-playback-state"

args = sys.argv[1:]
simulator = args[:1] == ["--simulator"]
if simulator: args = args[1:]
device = args[0] if args else sys.exit("usage: login_on_mac.py [--simulator] <udid>")
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

payload = json.dumps({"refresh_token": tokens["refresh_token"]})
if simulator:
    container = subprocess.run(["xcrun", "simctl", "get_app_container", device, BUNDLE_ID, "data"],
                               check=True, capture_output=True, text=True).stdout.strip()
    os.makedirs(os.path.join(container, "Documents"), exist_ok=True)
    with open(os.path.join(container, "Documents", "spotify_import.json"), "w") as f: f.write(payload)
    subprocess.run(["xcrun", "simctl", "launch", "--terminate-running-process", device, BUNDLE_ID],
                   check=True, stdout=subprocess.DEVNULL)
else:
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "spotify_import.json")
        with open(path, "w") as f: f.write(payload)
        subprocess.run(["xcrun", "devicectl", "device", "copy", "to", "--device", device, "--source", path,
                        "--destination", "Documents/spotify_import.json", "--domain-type", "appDataContainer",
                        "--domain-identifier", BUNDLE_ID], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["xcrun", "devicectl", "device", "process", "launch", "--terminate-existing", "--device", device, BUNDLE_ID],
                   check=True, stdout=subprocess.DEVNULL)
print("Done. Login copied over and CarLyrics relaunched.")
