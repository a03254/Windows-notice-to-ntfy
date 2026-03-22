from __future__ import annotations

import asyncio
import os
import re
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any
from urllib import request

from winrt.windows.ui.notifications import NotificationKinds
from winrt.windows.ui.notifications.management import (
    UserNotificationListener,
    UserNotificationListenerAccessStatus,
)

from .config import AppConfig
from .logging_utils import Logger

MAX_FIELD_LENGTH = 1500


def normalize_text(text: str | None) -> str:
    if text is None:
        return ""
    value = re.sub(r"[\x00-\x08\x0B\x0C\x0E-\x1F]", " ", text)
    value = re.sub(r"\s+", " ", value).strip()
    if len(value) > MAX_FIELD_LENGTH:
        value = value[:MAX_FIELD_LENGTH] + "...[truncated]"
    return value


def get_notification_texts(notification: Any) -> list[str]:
    texts: list[str] = []
    visual = notification.notification.visual
    if visual is None:
        return texts
    for binding in visual.bindings:
        for text_element in binding.get_text_elements():
            text = normalize_text(text_element.text)
            if text:
                texts.append(text)
    return texts


def convert_notification(notification: Any) -> dict[str, str]:
    texts = get_notification_texts(notification)
    app_name = normalize_text(str(notification.app_info.display_info.display_name or "Windows"))
    title = texts[0] if texts else ""
    content = "\n".join(texts[1:]) if len(texts) > 1 else (texts[0] if texts else "")
    return {
        "AppDisplayName": app_name,
        "Title": normalize_text(title),
        "Content": normalize_text(content),
        "CreationTime": str(notification.creation_time),
        "NotificationId": str(notification.id),
    }


async def ensure_access(logger: Logger) -> None:
    listener = UserNotificationListener.current
    status = listener.get_access_status()
    logger.log(f"Current notification access status: {status.name}")

    if status != UserNotificationListenerAccessStatus.ALLOWED:
        status = await listener.request_access_async()
        logger.log(f"RequestAccessAsync result: {status.name}")

    if status == UserNotificationListenerAccessStatus.DENIED:
        logger.log(
            "Notification access is denied. Opening Windows settings. Allow notification access and rerun.",
            "ERROR",
        )
        os.startfile("ms-settings:privacy-notifications")
        raise SystemExit(1)


def send_to_relay(payload: dict[str, str], relay_url: str) -> dict[str, Any]:
    data = __import__("json").dumps(payload, ensure_ascii=False).encode("utf-8")
    req = request.Request(
        relay_url,
        data=data,
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    with request.urlopen(req, timeout=30) as response:
        raw = response.read().decode("utf-8")
    return __import__("json").loads(raw)


async def monitor_notifications(
    config: AppConfig,
    relay_url: str,
    poll_interval: float,
    log_path: str | Path,
) -> None:
    logger = Logger(log_path)
    listener = UserNotificationListener.current

    logger.log("Starting Windows notification forwarder.")
    logger.log(f"Relay target: {relay_url}")
    await ensure_access(logger)

    notifications = await listener.get_notifications_async(NotificationKinds.TOAST)
    seen: dict[str, datetime] = {
        f"{item.id}:{item.creation_time.isoformat()}": datetime.now() for item in notifications
    }
    logger.log(f"Seeded {len(seen)} existing notifications. New notifications will be forwarded.")
    logger.log("Monitoring Windows toast notifications. Press Ctrl+C to stop.")

    while True:
        try:
            now = datetime.now()
            stale_before = now - timedelta(hours=12)
            seen = {key: value for key, value in seen.items() if value > stale_before}

            notifications = await listener.get_notifications_async(NotificationKinds.TOAST)
            for notification in notifications:
                key = f"{notification.id}:{notification.creation_time.isoformat()}"
                if key in seen:
                    continue

                seen[key] = now
                payload = convert_notification(notification)
                if not payload["Title"] and not payload["Content"]:
                    logger.log(
                        f"Skipping notification {payload['NotificationId']} because no text content was extracted.",
                        "WARN",
                    )
                    continue

                try:
                    result = send_to_relay(payload, relay_url)
                    logger.log(
                        f"Forwarded notification {payload['NotificationId']} from {payload['AppDisplayName']}. "
                        f"ntfy id={result.get('id')}"
                    )
                except Exception as exc:  # pragma: no cover - runtime surface
                    logger.log(
                        f"Failed to forward notification {payload['NotificationId']} from {payload['AppDisplayName']}: {exc}",
                        "ERROR",
                    )
        except Exception as exc:  # pragma: no cover - runtime surface
            logger.log(str(exc), "ERROR")

        await asyncio.sleep(poll_interval)

