#!/usr/bin/env python3
"""Edit SUPER in the title screen's logo, in a browser, over a picture of the title.

    python3 tools/super_edit.py         # opens http://localhost:8765 (--port for another)

It edits src/logo_super.txt, and saving builds the ROM. The picture is the title screen of
out/gimmick.sfc, taken with Mesen; the page draws the box being edited over it.
"""

import http.server
import json
import os
import subprocess
import sys
import webbrowser

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, "tools"))
import build  # noqa: E402

PORT = 8765
OUT = os.path.join(REPO, "out", "super_edit") + "/"
PAGE = os.path.join(REPO, "tools", "super_edit.html")
SHOT_LUA = """
local frame = 0
emu.addEventCallback(function()
  frame = frame + 1
  if frame == 240 then
    local h = io.open(OUT .. "title.png", "wb"); h:write(emu.takeScreenshot()); h:close()
    emu.stop(0)
  end
end, emu.eventType.endFrame)
emu.addEventCallback(function()
  emu.setInput({start = frame >= 90 and frame < 94}, 0)
end, emu.eventType.inputPolled)
"""


def take_title():
    os.makedirs(OUT, exist_ok=True)
    script = OUT + "title.lua"
    with open(script, "w") as f:
        f.write("OUT = %r\n" % OUT + SHOT_LUA)
    rom = os.path.join(REPO, "out", "gimmick.sfc")
    if not os.path.exists(rom):
        build_rom()
    subprocess.run([os.path.join(REPO, "Mesen"), "--testRunner", "--timeout=60", rom, script], cwd=REPO,
                   timeout=90, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def build_rom():
    r = subprocess.run([sys.executable, os.path.join(REPO, "tools", "build.py")], cwd=REPO,
                       capture_output=True, text=True)
    return r.returncode, (r.stdout + r.stderr).strip().splitlines()[-1:]


def settings():
    x0, y0, x1, y1 = build.LOGO_BOX
    return {"box": [x0, y0, x1, y1], "rowTop": build.NOTICE_DOWN - 1,
            # what BG2 has left once OPTIONS's letters are in
            "budget": build.TILE_NONE - build.TILE_LOGO - len(set("OPTIONS")),
            "rows": open(build.LOGO_FILE).read().split()}


class Handler(http.server.BaseHTTPRequestHandler):
    def reply(self, body, kind="application/json", code=200):
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/":
            self.reply(open(PAGE, "rb").read(), "text/html; charset=utf-8")
        elif self.path == "/api/settings":
            self.reply(json.dumps(settings()).encode())
        elif self.path.startswith("/title.png"):
            if "retake" in self.path or not os.path.exists(OUT + "title.png"):
                take_title()
            if not os.path.exists(OUT + "title.png"):
                self.reply(b"Mesen took no picture", "text/plain", 500)
                return
            self.reply(open(OUT + "title.png", "rb").read(), "image/png")
        else:
            self.reply(b"not found", "text/plain", 404)

    def do_POST(self):
        if self.path != "/api/save":
            self.reply(b"not found", "text/plain", 404)
            return
        rows = json.loads(self.rfile.read(int(self.headers["Content-Length"])))["rows"]
        x0, y0, x1, y1 = build.LOGO_BOX
        if len(rows) != y1 - y0 or any(len(r) != x1 - x0 or set(r) - set("#DL.") for r in rows):
            self.reply(json.dumps({"ok": False, "log": ["the drawing is not the box's size"]}).encode())
            return
        with open(build.LOGO_FILE, "w") as f:
            f.write("".join(r + "\n" for r in rows))
        code, log = build_rom()
        self.reply(json.dumps({"ok": code == 0, "log": log}).encode())

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    if "--port" in sys.argv:
        PORT = int(sys.argv[sys.argv.index("--port") + 1])
    url = "http://localhost:%d" % PORT
    print("SUPER editor at %s (Ctrl+C to stop)" % url)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    if "--no-browser" not in sys.argv:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
