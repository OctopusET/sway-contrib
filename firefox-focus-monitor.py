"""
Utility to selectively disable keypresses to specific windows.

This program was written due to Firefox's pop-out video player closing when
the Escape key is pressed.  I use a modal text editor (Helix) that encourages
regularly pressing that key and it had a habit of going to the wrong window.

The easiest way I could find to make this window specific key-binding change was
via this code.  Specifically it watches focus changes until the "right" windowds
is focused, and then causes Sway to bind the Escape key before Firefox can see
it.  It continues to watch focus changes so that this binding can be disabled
when another window is selected.

This feels like a potentially useful pattern, please let us know:
  https://github.com/OctopusET/sway-contrib
of any other programs that this functionality would benefit.
"""

import argparse
import logging
import signal
from dataclasses import dataclass
from typing import Any

import i3ipc

logger = logging.getLogger(__name__)


@dataclass(slots=True)
class Watch:
    container_props: dict[str,str]
    binds: set[str]


class Monitor:
    _bound: set[str]
    watched: list[Watch]

    def __init__(self) -> None:
        self.ipc = i3ipc.Connection()
        self.ipc.on("window::focus", self.on_window_event)
        # firefox creates PIP window without title, so need to watch for changes
        self.ipc.on("window::title", self.on_window_event)
        self._bound = set()
        self.watched = []

    def bind(self, *binds: str, **props: str) -> None:
        self.watched.append(Watch(props, set(binds)))

    def run(self) -> None:
        "run main i3ipc event loop"
        ipc = self.ipc
        def sighandler(signum: int, frame: Any) -> None:
            logger.debug("exit signal received, stopping event loop")
            ipc.main_quit()

        # stop event loop when we get one of these
        for sig in signal.SIGINT, signal.SIGTERM:
            signal.signal(sig, sighandler)

        try:
            ipc.main()
        finally:
            # clean up
            self.bound = set()

    def on_window_event(self, ipc: i3ipc.Connection, event: i3ipc.WindowEvent) -> None:
        "respond to window events"
        container = event.container
        if not container.focused:
            return
        data = container.ipc_data
        logger.debug("window event %s", data)
        binds = set()
        for watch in self.watched:
            if all(data.get(k) == v for k, v in watch.container_props.items()):
                    binds.update(watch.binds)

        self.bound = binds

    @property
    def bound(self) -> set[str]:
        return self._bound

    @bound.setter
    def bound(self, binds: set[str]) -> None:
        if binds == self._bound:
            return
        to_del = self._bound - binds
        to_add = binds - self._bound
        if to_del:
            logger.info(f"removing binds {', '.join(to_del)}")
        if to_add:
            logger.info(f"adding binds {', '.join(to_add)}")
        for bind in to_del:
            self.ipc.command(f"unbindsym {bind}")
        for bind in to_add:
            msg = f"{bind} ignored due to focus monitor"
            self.ipc.command(f"bindsym {bind} exec echo '{msg}'")
        self._bound = binds


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="track active window to disable Esc key in Firefox popout media player",
    )
    parser.add_argument(
        "--verbose", "-v", help="Increase verbosity", action="store_true"
    )
    args = parser.parse_args()
    args.loglevel = logging.DEBUG if args.verbose else logging.INFO
    return args


KEY_ESCAPE = "Escape"


def main() -> None:
    args = parse_args()
    logging.basicConfig(
        level=args.loglevel,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    mon = Monitor()
    # block Escape key from reaching Firefox's popout window
    mon.bind(KEY_ESCAPE, app_id="firefox", name="Picture-in-Picture")
    mon.run()


if __name__ == "__main__":
    main()
