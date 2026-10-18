#!/usr/bin/env python3
"""Run a shell command on the VM's serial console and print its output.
usage: serial.py "command" [timeout_seconds]"""
import socket, sys, time
cmd, timeout = sys.argv[1], float(sys.argv[2]) if len(sys.argv) > 2 else 20
s = socket.socket(socket.AF_UNIX); s.connect("/tmp/claude-1000/blidos-serial.sock"); s.settimeout(0.5)
def drain(t):
    out = b""; end = time.time() + t
    while time.time() < end:
        try:
            d = s.recv(65536)
            if d: out += d
        except socket.timeout: pass
    return out
drain(0.5)
marker = "__END_%d__" % int(time.time())
s.send(("\n%s; echo %s\n" % (cmd, marker)).encode())
out = b""; end = time.time() + timeout
while time.time() < end and (marker.encode() + b"\r\n") not in out and (marker.encode() + b"\n") not in out:
    try:
        d = s.recv(65536)
        if d: out += d
    except socket.timeout: pass
text = out.decode(errors="replace")
# drop the echoed command line, keep output
lines = [l for l in text.splitlines() if marker not in l]
print("\n".join(lines[1:] if lines else lines))
