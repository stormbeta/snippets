# CREDIT: https://stackoverflow.com/a/510404
# We don't use the getch in pypi as it's unmaintained and its installer is very fragile
class _Getch:
    """Gets a single character from standard input.  Does not echo to the screen."""
    def __init__(self):
        try:
            self.impl = _GetchWindows()
        except ImportError:
            self.impl = _GetchUnix()

    def __call__(self): return self.impl()


class _GetchUnix:
    def __init__(self):
        import tty, sys

    def __call__(self):
        import sys, tty, termios
        fd = sys.stdin.fileno()
        old_settings = termios.tcgetattr(fd)
        try:
            tty.setraw(sys.stdin.fileno())
            ch = sys.stdin.read(1)
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)
        return ch


class _GetchWindows:
    def __init__(self):
        import msvcrt

    def __call__(self):
        import msvcrt
        return msvcrt.getch()

getch = _Getch()

def confirm(msg: str) -> str:
    """
    Accepts one character without newline, to mimic Bash 'prompt' command behavior,
    since the decommission script is a mixture of Python and Bash scripts.

    If some prompts require enter, and some don't, the extraneous enters will be
    read into the following script prompt, which interpret the input as '!y' and the decommission
    script will only do a dry run for the next stage.
    """
    print(msg + "  ", end='', flush=True)
    choice = str(getch.getche()).lower()
    print("\n")
    return choice
