"""Minimal greetd IPC client (https://man.sr.ht/~kennylevinsen/greetd/): logs a profile in with its PIN."""
import json
import os
import socket
import struct


class LoginError(Exception):
    pass


class Greetd:
    def __init__(self):
        path = os.environ.get("GREETD_SOCK")
        if not path:
            raise LoginError("Not running under greetd")
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(path)

    def _send(self, msg):
        data = json.dumps(msg).encode()
        self.sock.sendall(struct.pack("=I", len(data)) + data)
        header = self._recv(4)
        (length,) = struct.unpack("=I", header)
        return json.loads(self._recv(length))

    def _recv(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise LoginError("greetd closed the connection")
            buf += chunk
        return buf

    def login(self, user, pin, command):
        """Authenticates and starts the session. Raises LoginError (wrong PIN, locked) on failure."""
        resp = self._send({"type": "create_session", "username": user})
        while resp["type"] == "auth_message":
            # Secret prompts get the PIN (empty for profiles without one); info/error prompts get nothing.
            answer = pin if resp.get("auth_message_type") == "secret" else ""
            resp = self._send({"type": "post_auth_message_response", "response": answer})
        if resp["type"] == "error":
            self._send({"type": "cancel_session"})
            raise LoginError("Wrong PIN" if resp.get("error_type") == "auth_error" else resp.get("description", "Can't sign in"))
        resp = self._send({"type": "start_session", "cmd": command, "env": []})
        if resp["type"] == "error":
            self._send({"type": "cancel_session"})
            raise LoginError(resp.get("description", "Can't start the profile"))
