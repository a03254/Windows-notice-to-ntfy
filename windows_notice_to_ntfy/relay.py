from __future__ import annotations

import base64
import json
import socket
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib import request
from urllib.parse import urlparse

from .config import AppConfig
from .logging_utils import Logger


def _get_nested(payload: dict[str, Any], *names: str) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = [payload]
    for name in names:
        nested = payload.get(name)
        if isinstance(nested, dict):
            candidates.append(nested)
    return candidates


def _first_value(objects: list[dict[str, Any]], names: list[str]) -> Any:
    for item in objects:
        for name in names:
            value = item.get(name)
            if value is None:
                continue
            if isinstance(value, str):
                trimmed = value.strip()
                if trimmed:
                    return trimmed
                continue
            return value
    return None


def _string_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        stripped = value.strip()
        return [stripped] if stripped else []
    if isinstance(value, list):
        result: list[str] = []
        for item in value:
            if item is None:
                continue
            text = str(item).strip()
            if text:
                result.append(text)
        return result
    return [str(value).strip()]


def convert_payload(payload: dict[str, Any], config: AppConfig) -> dict[str, Any]:
    candidates = _get_nested(
        payload,
        "NotificationData",
        "notificationData",
        "Notification",
        "notification",
        "Toast",
        "toast",
        "Data",
        "data",
    )

    app_name = _first_value(
        candidates,
        [
            "AppDisplayName",
            "appDisplayName",
            "ApplicationDisplayName",
            "applicationDisplayName",
            "ApplicationName",
            "applicationName",
            "AppName",
            "appName",
            "Source",
            "source",
        ],
    )
    title = _first_value(
        candidates,
        [
            "Title",
            "title",
            "Heading",
            "heading",
            "Summary",
            "summary",
            "NotificationTitle",
            "notificationTitle",
        ],
    )
    content = _first_value(
        candidates,
        ["Content", "content", "Body", "body", "Message", "message", "Text", "text", "Description", "description"],
    )
    if not content:
        content = "\n".join(
            _string_list(_first_value(candidates, ["Texts", "texts", "Lines", "lines", "TextsArray", "textsArray"]))
        ).strip()

    when = _first_value(candidates, ["CreationTime", "creationTime", "Timestamp", "timestamp", "ArrivalTime", "arrivalTime"])

    lines: list[str] = []
    if config.forwarding.includeComputerNameInMessage:
        lines.append(f"Host: {socket.gethostname()}")
    if app_name:
        lines.append(f"App: {app_name}")
    if title:
        lines.append(f"Title: {title}")
    if content:
        lines.append(f"Content: {content}")
    if when:
        lines.append(f"Time: {when}")

    message = "\n".join(lines).strip()
    if not message:
        message = config.forwarding.fallbackMessage

    max_length = config.forwarding.maxMessageLength
    if max_length > 0 and len(message) > max_length:
        message = message[:max_length] + "\n...[truncated]"

    ntfy_title = config.forwarding.fallbackTitle
    if config.forwarding.includeAppNameInTitle and app_name:
        ntfy_title = str(app_name)
    elif title:
        ntfy_title = str(title)

    body: dict[str, Any] = {
        "topic": config.ntfy.topic,
        "title": ntfy_title,
        "message": message,
        "priority": config.ntfy.priority,
        "tags": config.ntfy.tags or ["windows"],
        "markdown": config.ntfy.markdown,
    }

    if config.ntfy.click:
        body["click"] = config.ntfy.click
    if config.ntfy.icon:
        body["icon"] = config.ntfy.icon

    return body


def publish_to_ntfy(body: dict[str, Any], config: AppConfig) -> dict[str, Any]:
    server = config.ntfy.server.rstrip("/") + "/"
    data = json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    headers = {"Content-Type": "application/json; charset=utf-8"}

    if config.ntfy.token:
        headers["Authorization"] = f"Bearer {config.ntfy.token}"
    elif config.ntfy.username and config.ntfy.password:
        raw = f"{config.ntfy.username}:{config.ntfy.password}".encode("utf-8")
        headers["Authorization"] = "Basic " + base64.b64encode(raw).decode("ascii")

    req = request.Request(server, data=data, headers=headers, method="POST")
    with request.urlopen(req, timeout=30) as response:
        raw = response.read().decode("utf-8")
    return json.loads(raw)


@dataclass(slots=True)
class RelayApp:
    config: AppConfig
    logger: Logger

    def handle_health(self) -> dict[str, Any]:
        return {"status": "ok", "topic": self.config.ntfy.topic}

    def handle_notification(self, raw_body: bytes) -> dict[str, Any]:
        payload = json.loads(raw_body.decode("utf-8"))
        ntfy_body = convert_payload(payload, self.config)
        if self.config.logging.logPayloadPreview:
            preview = ntfy_body["message"][:180]
            self.logger.log(f"Forwarding payload. Title={ntfy_body['title']} Preview={preview}")
        result = publish_to_ntfy(ntfy_body, self.config)
        self.logger.log(f"Published to ntfy successfully. Id={result.get('id')} Topic={result.get('topic')}")
        return {"status": "ok", "id": result.get("id"), "topic": result.get("topic")}


def create_handler(app: RelayApp):
    expected_path = urlparse(app.config.listenPrefix).path or "/notify/"

    class RelayHandler(BaseHTTPRequestHandler):
        server_version = "WindowsNoticeToNtfy/1.0"

        def _write_json(self, status: HTTPStatus, body: dict[str, Any]) -> None:
            data = json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            self.send_response(status.value)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, format: str, *args: Any) -> None:
            return

        def do_GET(self) -> None:
            if self.path.split("?", 1)[0] == "/health":
                app.logger.log("Health check from local client.")
                self._write_json(HTTPStatus.OK, app.handle_health())
                return
            self._write_json(HTTPStatus.NOT_FOUND, {"status": "error", "error": f"Unexpected path: {self.path}"})

        def do_POST(self) -> None:
            self._handle_write()

        def do_PUT(self) -> None:
            self._handle_write()

        def _handle_write(self) -> None:
            request_path = self.path.split("?", 1)[0]
            if request_path != expected_path:
                app.logger.log(f"Rejected unexpected path {request_path}.", "WARN")
                self._write_json(HTTPStatus.NOT_FOUND, {"status": "error", "error": f"Unexpected path: {request_path}"})
                return

            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0:
                app.logger.log("Rejected empty request body.", "WARN")
                self._write_json(HTTPStatus.BAD_REQUEST, {"status": "error", "error": "Empty request body."})
                return

            raw_body = self.rfile.read(length)
            try:
                app.logger.log(f"Incoming notification request on {request_path}.")
                result = app.handle_notification(raw_body)
                self._write_json(HTTPStatus.OK, result)
            except Exception as exc:  # pragma: no cover - runtime surface
                app.logger.log(str(exc), "ERROR")
                self._write_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"status": "error", "error": str(exc)})

    return RelayHandler


def serve_relay(config: AppConfig, log_path: str | Path) -> None:
    parsed = urlparse(config.listenPrefix)
    host = parsed.hostname or "127.0.0.1"
    port = parsed.port or 8787
    logger = Logger(log_path)
    logger.log(f"Starting relay on {config.listenPrefix}")
    logger.log(f"Publishing to {config.ntfy.server} topic {config.ntfy.topic}")
    app = RelayApp(config=config, logger=logger)
    server = ThreadingHTTPServer((host, port), create_handler(app))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        logger.log("Relay stopped.", "WARN")
    finally:
        server.server_close()

