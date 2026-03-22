from __future__ import annotations

import argparse
import asyncio
import threading
import time
from pathlib import Path

from .config import AppConfig
from .listener import monitor_notifications
from .relay import serve_relay
from .toast_test import send_test_toast


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="windows-notice-to-ntfy")
    subparsers = parser.add_subparsers(dest="command", required=True)

    relay = subparsers.add_parser("relay", help="Run only the local ntfy relay")
    relay.add_argument("--config", default="config.json", help="Path to config.json")
    relay.add_argument("--log", default="relay-events.log", help="Relay log path")

    listener = subparsers.add_parser("listener", help="Run only the Windows notification listener")
    listener.add_argument("--config", default="config.json", help="Path to config.json")
    listener.add_argument("--relay-url", default="http://127.0.0.1:8787/notify/", help="Relay target URL")
    listener.add_argument("--poll-interval", type=float, default=5.0, help="Polling interval in seconds")
    listener.add_argument("--log", default="windows-forwarder.log", help="Listener log path")

    run = subparsers.add_parser("run", help="Run relay and listener in one process")
    run.add_argument("--config", default="config.json", help="Path to config.json")
    run.add_argument("--relay-log", default="relay-events.log", help="Relay log path")
    run.add_argument("--listener-log", default="windows-forwarder.log", help="Listener log path")
    run.add_argument("--poll-interval", type=float, default=5.0, help="Polling interval in seconds")

    test = subparsers.add_parser("test-toast", help="Send a local Windows test toast")
    test.add_argument("--title", default="ntfy forwarder test", help="Toast title")
    test.add_argument(
        "--message",
        default="If this toast is forwarded to your phone, the Windows notification listener is working.",
        help="Toast message",
    )

    return parser


def run_relay_only(config_path: str, log_path: str) -> None:
    config = AppConfig.load(config_path)
    serve_relay(config, log_path)


def run_listener_only(config_path: str, relay_url: str, poll_interval: float, log_path: str) -> None:
    config = AppConfig.load(config_path)
    asyncio.run(monitor_notifications(config, relay_url, poll_interval, log_path))


def run_all(config_path: str, relay_log: str, listener_log: str, poll_interval: float) -> None:
    config = AppConfig.load(config_path)
    relay_thread = threading.Thread(
        target=serve_relay,
        args=(config, relay_log),
        daemon=True,
        name="ntfy-relay",
    )
    relay_thread.start()
    time.sleep(1.5)
    asyncio.run(monitor_notifications(config, config.listenPrefix, poll_interval, listener_log))


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command == "relay":
        run_relay_only(args.config, args.log)
        return 0

    if args.command == "listener":
        run_listener_only(args.config, args.relay_url, args.poll_interval, args.log)
        return 0

    if args.command == "run":
        run_all(args.config, args.relay_log, args.listener_log, args.poll_interval)
        return 0

    if args.command == "test-toast":
        send_test_toast(args.title, args.message)
        return 0

    parser.error(f"Unknown command: {args.command}")
    return 2
