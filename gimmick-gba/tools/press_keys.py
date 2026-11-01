#!/usr/bin/env python3
"""Run out/gimmick.gba in mGBA and press its keys, to test the real controls.

    python3 tools/press_keys.py <out-dir>

Key events go to mGBA's window only, so nothing else on the screen sees them. It
takes a picture of the window after each step.
"""
import ctypes
import ctypes.util
import os
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
X = ctypes.CDLL(ctypes.util.find_library("X11"))
X.XOpenDisplay.restype = ctypes.c_void_p
X.XDefaultRootWindow.restype = ctypes.c_ulong
X.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
X.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
X.XKeysymToKeycode.restype = ctypes.c_ubyte
X.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_long, ctypes.c_void_p]
X.XFlush.argtypes = [ctypes.c_void_p]


class KeyEvent(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong), ("send_event", ctypes.c_int),
                ("display", ctypes.c_void_p), ("window", ctypes.c_ulong), ("root", ctypes.c_ulong),
                ("subwindow", ctypes.c_ulong), ("time", ctypes.c_ulong), ("x", ctypes.c_int), ("y", ctypes.c_int),
                ("x_root", ctypes.c_int), ("y_root", ctypes.c_int), ("state", ctypes.c_uint),
                ("keycode", ctypes.c_uint), ("same_screen", ctypes.c_int), ("pad", ctypes.c_long * 16)]


KEYS = {"start": 0xFF0D, "select": 0xFF08, "a": ord("x"), "b": ord("z"),
        "right": 0xFF53, "left": 0xFF51, "up": 0xFF52, "down": 0xFF54}
display = X.XOpenDisplay(None)
root = X.XDefaultRootWindow(display)


def send(window, key, press):
    e = KeyEvent(type=2 if press else 3, display=display, window=window, root=root, subwindow=0,
                 time=0, same_screen=1, keycode=X.XKeysymToKeycode(display, KEYS[key]))
    X.XSendEvent(display, window, 1, 1 if press else 2, ctypes.byref(e))
    X.XFlush(display)


def window_id():
    tree = subprocess.run(["xwininfo", "-root", "-tree"], capture_output=True, text=True).stdout
    for line in tree.splitlines():
        if "GIMMICK" in line:
            return int(line.split()[0], 16)
    return None


def shot(out, name):
    w = window_id()
    raw = os.path.join(out, name + ".xwd")
    subprocess.run(["xwd", "-silent", "-id", hex(w), "-out", raw])
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", raw, os.path.join(out, name + ".png")])
    os.remove(raw)


def tap(w, key, seconds=0.15):
    send(w, key, True)
    time.sleep(seconds)
    send(w, key, False)


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    p = subprocess.Popen(["flatpak", "run", "--filesystem=" + REPO, "io.mgba.mGBA", os.path.join(REPO, "out", "gimmick.gba")],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(6)
        w = window_id()
        shot(out, "a_boot")
        tap(w, "start")
        time.sleep(1.5)
        shot(out, "a_title")
        time.sleep(4)
        shot(out, "a_title_later")
        tap(w, "start")  # START on the title
        time.sleep(4)
        shot(out, "b_map")
        tap(w, "start")  # leave the world map
        time.sleep(5)
        shot(out, "c_stage")
        send(w, "right", True)
        time.sleep(2)
        shot(out, "e_walk_right")
        tap(w, "a", 0.4)
        time.sleep(0.1)
        shot(out, "f_jump")
        send(w, "right", False)
        send(w, "b", True)
        time.sleep(1.2)
        shot(out, "g_charging")
        send(w, "b", False)
        time.sleep(0.3)
        shot(out, "h_thrown")
        tap(w, "start")  # pause
        time.sleep(0.5)
        shot(out, "i_paused")
        time.sleep(1)
        shot(out, "j_still_paused")
    finally:
        subprocess.run(["flatpak", "kill", "io.mgba.mGBA"], stderr=subprocess.DEVNULL)
        p.wait()


if __name__ == "__main__":
    main()
