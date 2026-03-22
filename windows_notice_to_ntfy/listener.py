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
    try:
        notification_obj = notification.notification
        visual = notification_obj.visual if notification_obj is not None else None
    except Exception:
        return texts

    if visual is None:
        return texts
    try:
        for binding in visual.bindings:
            for text_element in binding.get_text_elements():
                text = normalize_text(text_element.text)
                if text:
                    texts.append(text)
    except Exception:
        return texts
    return texts


def get_app_name(notification: Any) -> str:
    try:
        app_info = getattr(notification, "app_info", None)
    except Exception:
        return "Windows"

    if app_info is None:
        return "Windows"

    candidates: list[str] = []

    try:
        display_info = getattr(app_info, "display_info", None)
        if display_info is not None:
            display_name = getattr(display_info, "display_name", None)
            if display_name:
                candidates.append(str(display_name))
    except Exception:
        pass

    for attr in ("package_family_name", "app_user_model_id"):
        try:
            value = getattr(app_info, attr, None)
            if value:
                candidates.append(str(value))
        except Exception:
            continue

    for candidate in candidates:
        normalized = normalize_text(candidate)
        if normalized:
            return normalized

    return "Windows"


def get_notification_id(notification: Any) -> str:
    try:
        return str(notification.id)
    except Exception:
        return "unknown"


def get_creation_time(notification: Any) -> str:
    try:
        return notification.creation_time.isoformat()
    except Exception:
        return "unknown"


def convert_notification(notification: Any) -> dict[str, str]:
    texts = get_notification_texts(notification)
    app_name = get_app_name(notification)
    title = texts[0] if texts else ""
    content = "\n".join(texts[1:]) if len(texts) > 1 else (texts[0] if texts else "")
    return {
        "AppDisplayName": app_name,
        "Title": normalize_text(title),
        "Content": normalize_text(content),
        "CreationTime": get_creation_time(notification),
        "NotificationId": get_notification_id(notification),
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
        f"{get_notification_id(item)}:{get_creation_time(item)}": datetime.now() for item in notifications
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
                try:
                    key = f"{get_notification_id(notification)}:{get_creation_time(notification)}"
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

                    result = send_to_relay(payload, relay_url)
                    logger.log(
                        f"Forwarded notification {payload['NotificationId']} from {payload['AppDisplayName']}. "
                        f"ntfy id={result.get('id')}"
                    )
                except Exception as exc:  # pragma: no cover - runtime surface
                    logger.log(f"Failed to process notification {get_notification_id(notification)}: {exc}", "ERROR")
        except Exception as exc:  # pragma: no cover - runtime surface
            logger.log(str(exc), "ERROR")

        await asyncio.sleep(poll_interval)
