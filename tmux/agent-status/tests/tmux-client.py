#!/usr/bin/env python3
"""Drive a real tmux terminal client for focus and mouse tests."""

import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time


def attach(socket, session):
    pid, fd = pty.fork()
    if pid == 0:
        os.environ["TERM"] = "xterm-256color"
        os.execvp("tmux", ["tmux", "-L", socket, "attach", "-t", session])
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    drain(fd, 0.3)
    return pid, fd


def drain(fd, quiet):
    end = time.time() + 3
    while time.time() < end:
        if not select.select([fd], [], [], quiet)[0]:
            return
        try:
            os.read(fd, 65536)
        except OSError:
            return


def close(pid, fd):
    try:
        os.write(fd, b"\x1b[O")
        os.kill(pid, signal.SIGTERM)
        os.waitpid(pid, 0)
    except (ChildProcessError, OSError):
        pass


def hold(socket, session, path, focus):
    pid, fd = attach(socket, session)
    os.write(fd, b"\x1b[I" if focus == "focused" else b"\x1b[O")
    while os.path.exists(path):
        drain(fd, 0.1)
    close(pid, fd)


def click(socket, session, text, target):
    pid, fd = attach(socket, session)
    column = text.index(target) + 1
    os.write(fd, f"\x1b[<0;{column};24M\x1b[<0;{column};24m".encode())
    drain(fd, 0.3)
    close(pid, fd)


command, socket, session, *args = sys.argv[1:]
if command == "hold":
    hold(socket, session, *args)
elif command == "click":
    click(socket, session, *args)
else:
    raise SystemExit(f"unknown command: {command}")
