#!/usr/bin/env python3
"""ProxyCommand fixture: relays ssh to HOST:PORT, optionally throttled or cut.

PROXY_RATE       bytes per second toward the server (0 = unlimited)
PROXY_DOWN_FILE  while this file exists, refuse to connect and drop live connections
"""
import os
import socket
import sys
import threading
import time

host, port = sys.argv[1], int(sys.argv[2])
rate = int(os.environ.get("PROXY_RATE", "0"))
down = os.environ.get("PROXY_DOWN_FILE", "")


def is_down():
    return bool(down) and os.path.exists(down)


if is_down():
    sys.exit(1)

sock = socket.create_connection((host, port), timeout=10)
sock.settimeout(None)
done = threading.Event()


def upstream():
    chunk = 65536 if rate == 0 else max(1024, rate // 20)
    stdin = sys.stdin.buffer
    while not done.is_set():
        data = stdin.read1(chunk)
        if not data:
            break
        sock.sendall(data)
        if rate:
            time.sleep(len(data) / rate)
    done.set()
    try:
        sock.shutdown(socket.SHUT_WR)
    except OSError:
        pass


def downstream():
    stdout = sys.stdout.buffer
    while not done.is_set():
        data = sock.recv(65536)
        if not data:
            break
        stdout.write(data)
        stdout.flush()
    done.set()


def watch():
    while not done.is_set():
        if is_down():
            os._exit(1)
        time.sleep(0.1)


for fn in (upstream, downstream, watch):
    threading.Thread(target=fn, daemon=True).start()
done.wait()
