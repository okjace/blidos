#!/usr/bin/env python3
"""Drive a headless QEMU over QMP.

usage:
  qm.py shot out.png            screenshot
  qm.py key ret | key ctrl-alt-f2   press keys (QEMU qcode names, '-' joins a chord)
  qm.py type "some text"        type ASCII text
  qm.py click X Y [W H]         left-click at pixel X,Y on a W x H screen (default 1024x768)
"""
import json, socket, sys, time

SOCK = "/tmp/claude-1000/blidos-qmp.sock"

def qmp(cmds):
    s = socket.socket(socket.AF_UNIX)
    s.connect(SOCK)
    f = s.makefile("rw")
    f.readline()
    def send(obj):
        f.write(json.dumps(obj) + "\n"); f.flush()
        while True:
            r = json.loads(f.readline())
            if "return" in r or "error" in r:
                return r
    send({"execute": "qmp_capabilities"})
    out = [send(c) for c in cmds]
    s.close()
    for r in out:
        if "error" in r:
            print(r["error"], file=sys.stderr)
    return out

def keys(chord):
    return [{"type": "qcode", "data": k} for k in chord.split("-")]

SHIFTED = {'!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6', '&': '7', '*': '8', '(': '9', ')': '0',
           '_': 'minus', '+': 'equal', ':': 'semicolon', '"': 'apostrophe', '<': 'comma', '>': 'dot', '?': 'slash'}
PLAIN = {' ': 'spc', '-': 'minus', '=': 'equal', ';': 'semicolon', "'": 'apostrophe', ',': 'comma', '.': 'dot',
         '/': 'slash', '\n': 'ret', '\\': 'backslash', '[': 'bracket_left', ']': 'bracket_right'}

def type_text(text):
    for ch in text:
        if ch.isupper():
            k = [{"type": "qcode", "data": "shift"}, {"type": "qcode", "data": ch.lower()}]
        elif ch in SHIFTED:
            k = [{"type": "qcode", "data": "shift"}, {"type": "qcode", "data": SHIFTED[ch]}]
        else:
            k = [{"type": "qcode", "data": PLAIN.get(ch, ch)}]
        qmp([{"execute": "send-key", "arguments": {"keys": k}}])
        time.sleep(0.05)

def click(x, y, w=1024, h=768):
    ax, ay = int(x * 32767 / (w - 1)), int(y * 32767 / (h - 1))
    move = {"execute": "input-send-event", "arguments": {"events": [
        {"type": "abs", "data": {"axis": "x", "value": ax}},
        {"type": "abs", "data": {"axis": "y", "value": ay}}]}}
    def btn(down):
        return {"execute": "input-send-event", "arguments": {"events": [
            {"type": "btn", "data": {"down": down, "button": "left"}}]}}
    qmp([move])
    time.sleep(0.1)
    qmp([btn(True)])
    time.sleep(0.08)
    qmp([btn(False)])

cmd, args = sys.argv[1], sys.argv[2:]
if cmd == "shot":
    qmp([{"execute": "screendump", "arguments": {"filename": args[0], "format": "png"}}])
elif cmd == "key":
    for chord in args:
        qmp([{"execute": "send-key", "arguments": {"keys": keys(chord)}}])
        time.sleep(0.15)
elif cmd == "type":
    type_text(args[0])
elif cmd == "reset":
    qmp([{"execute": "system_reset"}])
elif cmd == "click":
    click(*[int(a) for a in args])
