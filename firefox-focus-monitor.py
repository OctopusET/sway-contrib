import argparse
import logging
import signal

import i3ipc

logger = logging.getLogger(__name__)


def should_bind(event: i3ipc.WindowEvent) -> bool:
    "determine whether we should bind Escape key"
    logging.debug("received event %s", event.ipc_data)
    match event.container:
        case i3ipc.Con(app_id="firefox", name="Picture-in-Picture"):
            return True
    return False


class Monitor:
    def __init__(self) -> None:
        self.ipc = i3ipc.Connection()
        self.ipc.on("window::focus", self.on_window_event)
        # firefox creates PIP window without title, so need to watch for changes
        self.ipc.on("window::title", self.on_window_event)
        self.bound = False

    def run(self) -> None:
        "run main i3ipc event loop"
        ipc = self.ipc

        def sighandler(signum, frame):
            logging.debug("signal received, stopping event loop")
            ipc.main_quit()

        # stop event loop when we get one of these
        for sig in signal.SIGINT, signal.SIGTERM:
            signal.signal(sig, sighandler)

        try:
            ipc.main()
        finally:
            # clean up
            self.do_unbind()

    def on_window_event(self, ipc, event):
        "respond to window events"
        if should_bind(event):
            self.do_bind()
        else:
            self.do_unbind()

    def do_bind(self) -> None:
        "bind Escape key so it doesn't get seen outside WM"
        if self.bound:
            return
        logger.info("ignoring escape")
        msg = "escape ignored in firefox pip video player"
        self.ipc.command(f"bindsym Escape exec echo '{msg}'")
        self.bound = True

    def do_unbind(self) -> None:
        "reset binding to hopefully restore default behaviour"
        if not self.bound:
            return
        logger.info("resetting escape")
        self.ipc.command("unbindsym Escape")
        self.bound = False


def parse_args():
    parser = argparse.ArgumentParser(
        description="track active window to disable Esc key in Firefox popout media player",
    )
    parser.add_argument(
        "--verbose", "-v", help="Increase verbosity", action="store_true"
    )
    args = parser.parse_args()
    args.loglevel = logging.DEBUG if args.verbose else logging.INFO
    return args


def main() -> None:
    args = parse_args()
    logging.basicConfig(
        level=args.loglevel,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    mon = Monitor()
    mon.run()


if __name__ == "__main__":
    main()
