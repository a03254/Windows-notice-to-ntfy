from __future__ import annotations

from windows11toast import toast


def send_test_toast(title: str, message: str) -> None:
    toast(title, message)
    print("Test toast sent.")
    print(f"Title: {title}")
    print(f"Message: {message}")

