from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass(slots=True)
class NtfyConfig:
    server: str = "https://ntfy.sh/"
    topic: str = "replace-with-your-random-topic"
    token: str = ""
    username: str = ""
    password: str = ""
    priority: int = 3
    tags: list[str] = field(default_factory=lambda: ["windows", "desktop"])
    markdown: bool = False
    click: str = ""
    icon: str = ""


@dataclass(slots=True)
class ForwardingConfig:
    includeAppNameInTitle: bool = True
    includeComputerNameInMessage: bool = True
    fallbackTitle: str = "Windows Notification"
    fallbackMessage: str = "Received a Windows notification with no recognized text fields."
    appendRawJsonOnEmpty: bool = True
    maxMessageLength: int = 3500


@dataclass(slots=True)
class LoggingConfig:
    logPayloadPreview: bool = True


@dataclass(slots=True)
class AppConfig:
    listenPrefix: str = "http://127.0.0.1:8787/notify/"
    ntfy: NtfyConfig = field(default_factory=NtfyConfig)
    forwarding: ForwardingConfig = field(default_factory=ForwardingConfig)
    logging: LoggingConfig = field(default_factory=LoggingConfig)

    @classmethod
    def load(cls, path: str | Path) -> "AppConfig":
        config_path = Path(path)
        if not config_path.exists():
            raise FileNotFoundError(
                f"Config file not found: {config_path}. Copy config.example.json to config.json first."
            )

        raw: dict[str, Any] = json.loads(config_path.read_text(encoding="utf-8"))
        ntfy = NtfyConfig(**raw.get("ntfy", {}))
        forwarding = ForwardingConfig(**raw.get("forwarding", {}))
        logging = LoggingConfig(**raw.get("logging", {}))
        return cls(
            listenPrefix=raw.get("listenPrefix", cls.listenPrefix),
            ntfy=ntfy,
            forwarding=forwarding,
            logging=logging,
        )

