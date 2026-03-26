"""notifier 模块的单元测试 — 验证 CLI osascript fallback 仍正常工作"""

from __future__ import annotations

import json
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch, call

from cc_stats.notifier import (
    _send_osascript,
    _escape_applescript,
    send_notification,
    load_config,
)


class TestEscapeApplescript(unittest.TestCase):
    """AppleScript 字符串转义"""

    def test_escape_backslash(self) -> None:
        assert _escape_applescript("a\\b") == "a\\\\b"

    def test_escape_double_quote(self) -> None:
        assert _escape_applescript('say "hi"') == 'say \\"hi\\"'

    def test_escape_combined(self) -> None:
        result = _escape_applescript('path\\to\\"file"')
        assert "\\\\" in result
        assert '\\"' in result

    def test_escape_safe_string(self) -> None:
        safe = "Hello World"
        assert _escape_applescript(safe) == safe


class TestSendOsascript(unittest.TestCase):
    """osascript 通知发送"""

    @patch("cc_stats.notifier.subprocess.run")
    def test_sends_correct_command(self, mock_run: MagicMock) -> None:
        mock_run.return_value = MagicMock(returncode=0)
        result = _send_osascript("Title", "Body")
        assert result is True
        args = mock_run.call_args
        assert args[0][0][0] == "/usr/bin/osascript"
        script = args[0][0][2]
        assert "Title" in script
        assert "Body" in script

    @patch("cc_stats.notifier.subprocess.run")
    def test_returns_false_on_failure(self, mock_run: MagicMock) -> None:
        mock_run.return_value = MagicMock(returncode=1)
        result = _send_osascript("T", "B")
        assert result is False

    @patch("cc_stats.notifier.subprocess.run", side_effect=OSError("not found"))
    def test_returns_false_on_os_error(self, mock_run: MagicMock) -> None:
        result = _send_osascript("T", "B")
        assert result is False

    @patch("cc_stats.notifier.subprocess.run")
    def test_escapes_injection(self, mock_run: MagicMock) -> None:
        mock_run.return_value = MagicMock(returncode=0)
        _send_osascript('Title"', 'Body\\')
        script = mock_run.call_args[0][0][2]
        assert '\\"' not in script or '\\\\"' in script  # quotes escaped


class TestSendNotification(unittest.TestCase):
    """send_notification 集成路径"""

    @patch("cc_stats.notifier._send_osascript", return_value=True)
    @patch("cc_stats.notifier.load_config")
    @patch("cc_stats.notifier.is_terminal_focused", return_value=False)
    def test_sends_when_enabled(
        self, mock_focus: MagicMock, mock_config: MagicMock, mock_send: MagicMock
    ) -> None:
        mock_config.return_value = {
            "enabled": True,
            "session_complete": True,
            "smart_suppress": True,
            "sound": "Glass",
            "webhook_url": "",
        }
        result = send_notification("Title", "Body", notify_type="session_complete")
        assert result is True
        mock_send.assert_called_once()

    @patch("cc_stats.notifier._send_osascript")
    @patch("cc_stats.notifier.load_config")
    def test_disabled_returns_false(
        self, mock_config: MagicMock, mock_send: MagicMock
    ) -> None:
        mock_config.return_value = {"enabled": False}
        result = send_notification("Title", "Body", notify_type="session_complete")
        assert result is False
        mock_send.assert_not_called()

    @patch("cc_stats.notifier._send_osascript")
    @patch("cc_stats.notifier.load_config")
    @patch("cc_stats.notifier.is_terminal_focused", return_value=True)
    def test_suppressed_when_terminal_focused(
        self, mock_focus: MagicMock, mock_config: MagicMock, mock_send: MagicMock
    ) -> None:
        mock_config.return_value = {
            "enabled": True,
            "session_complete": True,
            "smart_suppress": True,
            "sound": "Glass",
            "webhook_url": "",
        }
        result = send_notification("Title", "Body", notify_type="session_complete")
        assert result is False
        mock_send.assert_not_called()

    @patch("cc_stats.notifier._send_osascript", return_value=True)
    @patch("cc_stats.notifier.load_config")
    @patch("cc_stats.notifier.is_terminal_focused", return_value=False)
    def test_cost_alert_sent_when_not_focused(
        self, mock_focus: MagicMock, mock_config: MagicMock, mock_send: MagicMock
    ) -> None:
        mock_config.return_value = {
            "enabled": True,
            "cost_alert": True,
            "smart_suppress": True,
            "sound": "Glass",
            "webhook_url": "",
        }
        result = send_notification("Alert", "Over budget", notify_type="cost_alert")
        assert result is True
        mock_send.assert_called_once()

    @patch("cc_stats.notifier._send_osascript", return_value=True)
    @patch("cc_stats.notifier.load_config")
    def test_force_bypasses_suppression(
        self, mock_config: MagicMock, mock_send: MagicMock
    ) -> None:
        mock_config.return_value = {
            "enabled": True,
            "session_complete": True,
            "smart_suppress": True,
            "sound": "Glass",
            "webhook_url": "",
        }
        result = send_notification("T", "B", notify_type="session_complete", force=True)
        assert result is True
        mock_send.assert_called_once()


class TestLoadConfig(unittest.TestCase):
    """配置加载"""

    @patch("cc_stats.notifier._CONFIG_FILE")
    def test_returns_defaults_when_no_file(self, mock_path: MagicMock) -> None:
        mock_path.exists.return_value = False
        config = load_config()
        assert config["enabled"] is True
        assert config["sound"] == "Glass"


if __name__ == "__main__":
    unittest.main()
