# Copyright (C) 2026 Shitty team
# MIT licensed
# See the file LICENSE.MIT for the full license.

import os
import sys
import unittest

from harness import PRETTY, Shitty


class StartupTest(unittest.TestCase):
    def test_pretty_child_gets_pretty_version(self):
        program = "import os; os.write(1, (os.environ.get('PRETTY_VERSION') + '\\r\\n').encode())"
        with Shitty(columns=16, rows=2, binary=PRETTY) as terminal:
            terminal.spawn(sys.executable, "-c", program)
            terminal.wait_read_pty()
            status, _ = terminal.wait_child()
            self.assertEqual(status, 0)
            self.assertEqual(
                terminal.snapshot().lines[0].rstrip(),
                os.environ["SHITTY_TEST_VERSION"],
            )

    def test_spawned_child_uses_normal_tty_output_processing(self):
        with Shitty(columns=8, rows=2) as terminal:
            terminal.spawn(
                sys.executable,
                "-c",
                "import os; os.write(1, b'A\\nB')",
            )
            status, _ = terminal.wait_child()
            self.assertEqual(status, 0)
            self.assertEqual(terminal.snapshot().lines, ["A       ", "B       "])

    def test_child_environment_winsize_and_sigwinch(self):
        program = r'''
import fcntl, os, signal, struct, termios

def size():
    rows, columns, _, _ = struct.unpack(
        "HHHH", fcntl.ioctl(0, termios.TIOCGWINSZ, b"\0" * 8)
    )
    return f"{columns}x{rows}"

def emit(prefix):
    os.write(1, f"{prefix}|{size()}\r\n".encode())

def resized(signum, frame):
    emit("SIGWINCH")
    raise SystemExit(0)

signal.signal(signal.SIGWINCH, resized)
os.write(
    1,
    f"{os.environ.get('TERM')}|{os.environ.get('SHITTY_VERSION')}|{size()}\r\n".encode(),
)
signal.pause()
'''
        with Shitty(columns=72, rows=3) as terminal:
            terminal.resize(80, 4)
            terminal.spawn(sys.executable, "-c", program)
            terminal.wait_read_pty()
            self.assertEqual(
                terminal.snapshot().lines[0].rstrip(),
                f"xterm-256color|{os.environ['SHITTY_TEST_VERSION']}|80x4",
            )

            terminal.resize(80, 5)
            terminal.wait_read_pty()
            status, _ = terminal.wait_child()
            self.assertEqual(status, 0)
            self.assertEqual(
                terminal.snapshot().lines[1].rstrip(),
                "SIGWINCH|80x5",
            )

    def test_fullscreen_startup_survives_the_inline_transition_frame(self):
        # Entering fullscreen delivers a frame from inside the request -
        # on macOS the transition's Core Animation transaction commits
        # inline, and the headless window mirrors that - before the
        # renderer and the sessions exist. Startup must skip that frame
        # instead of crashing on it (issue 116); reaching READY at all is
        # the point, and the geometry report shows the terminal parsing
        # and replying on the fullscreen grid afterwards.
        with Shitty(
            columns=10,
            rows=4,
            extra_arguments=("-fullscreen", "-allowWindowOps", "true"),
        ) as terminal:
            terminal.write(b"\x1b[18t")
            self.assertEqual(terminal.read_input(), b"\x1b[8;1076;1916t")


if __name__ == "__main__":
    unittest.main()
