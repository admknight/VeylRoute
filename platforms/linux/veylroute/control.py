"""Tor SAFECOOKIE-authenticated UNIX ControlSocket support.

Protocol reference: https://spec.torproject.org/control-spec/commands.html
"""
from __future__ import annotations

import hashlib
import hmac
import os
import re
import socket
from pathlib import Path

KEY_SERVER = b"Tor safe cookie authentication server-to-controller hash"
KEY_CLIENT = b"Tor safe cookie authentication controller-to-server hash"


class ControlError(RuntimeError):
    pass


def hmac_pair(cookie: bytes, client_nonce: bytes, server_nonce: bytes) -> tuple[bytes, bytes]:
    if not all(len(v) == 32 for v in (cookie, client_nonce, server_nonce)):
        raise ControlError("Invalid SAFECOOKIE nonce or cookie length")
    payload = cookie + client_nonce + server_nonce
    return (hmac.new(KEY_SERVER, payload, hashlib.sha256).digest(),
            hmac.new(KEY_CLIENT, payload, hashlib.sha256).digest())


def _reply(sock: socket.socket) -> str:
    # Control replies can be multiline; this helper is intentionally limited
    # to the single-line 250 responses used by AUTHCHALLENGE and NEWNYM.
    data = bytearray()
    while not data.endswith(b"\r\n"):
        chunk = sock.recv(1)
        if not chunk or len(data) > 8192:
            raise ControlError("Tor control reply was closed or oversized")
        data.extend(chunk)
    line = data.decode("ascii", "strict").strip()
    if not line.startswith("250 "):
        raise ControlError("Tor control request was rejected")
    return line[4:]


def request_new_circuit(socket_path: str, cookie_path: str) -> str:
    """Request clean circuits for NEW streams. Not guaranteed a new exit IP."""
    cookie = Path(cookie_path).read_bytes()
    if len(cookie) != 32:
        raise ControlError("Tor control authentication cookie is invalid")
    nonce = os.urandom(32)
    client_hex = nonce.hex().upper()
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.settimeout(6.0)
        sock.connect(socket_path)
        sock.sendall(f"AUTHCHALLENGE SAFECOOKIE {client_hex}\r\n".encode("ascii"))
        challenge = _reply(sock)
        match = re.fullmatch(r"AUTHCHALLENGE SERVERHASH=([A-Fa-f0-9]{64}) SERVERNONCE=([A-Fa-f0-9]{64})", challenge)
        if not match:
            raise ControlError("Unexpected Tor SAFECOOKIE challenge format")
        server_hash = bytes.fromhex(match.group(1))
        server_nonce = bytes.fromhex(match.group(2))
        expected, proof = hmac_pair(cookie, nonce, server_nonce)
        if not hmac.compare_digest(server_hash, expected):
            raise ControlError("Tor SAFECOOKIE server proof mismatch")
        sock.sendall(b"AUTHENTICATE " + proof.hex().upper().encode("ascii") + b"\r\n")
        if _reply(sock) != "OK":
            raise ControlError("Tor SAFECOOKIE authentication failed")
        sock.sendall(b"SIGNAL NEWNYM\r\n")
        if _reply(sock) != "OK":
            raise ControlError("Tor rejected NEWNYM")
    return "Tor acknowledged NEWNYM; only new connections use fresh circuits, and an IP change is not guaranteed."
