"""hooks 模块的单元测试 — 覆盖 hook 命令查找、安装/卸载、匹配逻辑"""

from __future__ import annotations

import json
import unittest
from pathlib import Path
from unittest.mock import patch

from cc_stats.hooks import (
    get_hook_command,
    install_hooks,
    uninstall_hooks,
    _hook_matches,
    _hook_exists,
)


class TestGetHookCommand(unittest.TestCase):
    """get_hook_command() — 优先使用 entry-point binary"""

    @patch("cc_stats.hooks.shutil.which", return_value="/usr/local/bin/cc-stats-hooks")
    def test_returns_entry_point_when_found(self, mock_which):
        result = get_hook_command()
        assert result == "/usr/local/bin/cc-stats-hooks"
        mock_which.assert_called_once_with("cc-stats-hooks")

    @patch("cc_stats.hooks.shutil.which", return_value=None)
    def test_fallback_to_python_m_when_not_found(self, mock_which):
        result = get_hook_command()
        assert "python" in result
        assert "-m cc_stats.hooks" in result

    @patch("cc_stats.hooks.shutil.which", return_value="/home/user/.local/bin/cc-stats-hooks")
    def test_returns_absolute_path(self, mock_which):
        result = get_hook_command()
        assert result.startswith("/")


class TestHookMatches(unittest.TestCase):
    """_hook_matches() — 兼容新旧两种 hook 命令格式"""

    def test_matches_old_format(self):
        hook = {"type": "command", "command": "/usr/bin/python3 -m cc_stats.hooks"}
        assert _hook_matches(hook, "anything") is True

    def test_matches_new_format(self):
        hook = {"type": "command", "command": "/usr/local/bin/cc-stats-hooks"}
        assert _hook_matches(hook, "anything") is True

    def test_no_match_unrelated(self):
        hook = {"type": "command", "command": "echo hello"}
        assert _hook_matches(hook, "anything") is False

    def test_non_dict_returns_false(self):
        assert _hook_matches("not a dict", "anything") is False

    def test_missing_command_key(self):
        hook = {"type": "command"}
        assert _hook_matches(hook, "anything") is False


class TestHookExists(unittest.TestCase):
    """_hook_exists() — 检测 hook 是否已安装"""

    def test_exists_old_format(self):
        hooks = [{"type": "command", "command": "python3 -m cc_stats.hooks"}]
        assert _hook_exists(hooks, "anything") is True

    def test_exists_new_format(self):
        hooks = [{"type": "command", "command": "/usr/local/bin/cc-stats-hooks"}]
        assert _hook_exists(hooks, "anything") is True

    def test_not_exists(self):
        hooks = [{"type": "command", "command": "echo hello"}]
        assert _hook_exists(hooks, "anything") is False

    def test_empty_list(self):
        assert _hook_exists([], "anything") is False


class TestInstallHooks(unittest.TestCase):
    """install_hooks() — 注册 Stop、PreToolUse、Notification 三个 event"""

    @patch("cc_stats.hooks.get_hook_command", return_value="/usr/local/bin/cc-stats-hooks")
    def test_installs_all_three_events(self, mock_cmd, tmp_path=None):
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            settings_path = Path(tmpdir) / ".claude" / "settings.json"
            with patch("cc_stats.hooks.Path.home", return_value=Path(tmpdir)):
                install_hooks(scope="user")

            assert settings_path.exists()
            with open(settings_path, encoding="utf-8") as f:
                settings = json.load(f)

            hooks = settings["hooks"]
            assert "Stop" in hooks
            assert "PreToolUse" in hooks
            assert "Notification" in hooks

            for event_type in ("Stop", "PreToolUse", "Notification"):
                entries = hooks[event_type]
                assert len(entries) == 1
                assert entries[0]["command"] == "/usr/local/bin/cc-stats-hooks"
                assert entries[0]["type"] == "command"

    @patch("cc_stats.hooks.get_hook_command", return_value="/usr/local/bin/cc-stats-hooks")
    def test_does_not_duplicate_on_reinstall(self, mock_cmd):
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("cc_stats.hooks.Path.home", return_value=Path(tmpdir)):
                install_hooks(scope="user")
                install_hooks(scope="user")

            settings_path = Path(tmpdir) / ".claude" / "settings.json"
            with open(settings_path, encoding="utf-8") as f:
                settings = json.load(f)

            for event_type in ("Stop", "PreToolUse", "Notification"):
                assert len(settings["hooks"][event_type]) == 1

    @patch("cc_stats.hooks.get_hook_command", return_value="/usr/local/bin/cc-stats-hooks")
    def test_preserves_existing_hooks(self, mock_cmd):
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            settings_path = Path(tmpdir) / ".claude" / "settings.json"
            settings_path.parent.mkdir(parents=True, exist_ok=True)
            existing = {
                "hooks": {
                    "Stop": [{"type": "command", "command": "echo done"}],
                },
                "other_key": "preserved",
            }
            with open(settings_path, "w", encoding="utf-8") as f:
                json.dump(existing, f)

            with patch("cc_stats.hooks.Path.home", return_value=Path(tmpdir)):
                install_hooks(scope="user")

            with open(settings_path, encoding="utf-8") as f:
                settings = json.load(f)

            assert settings["other_key"] == "preserved"
            # existing Stop hook preserved + new one added
            assert len(settings["hooks"]["Stop"]) == 2


class TestUninstallHooks(unittest.TestCase):
    """uninstall_hooks() — 清理 Stop、PreToolUse、Notification 三个 event"""

    @patch("cc_stats.hooks.get_hook_command", return_value="/usr/local/bin/cc-stats-hooks")
    def test_removes_all_three_events(self, mock_cmd):
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            settings_path = Path(tmpdir) / ".claude" / "settings.json"
            settings_path.parent.mkdir(parents=True, exist_ok=True)
            settings = {
                "hooks": {
                    "Stop": [{"type": "command", "command": "/usr/local/bin/cc-stats-hooks"}],
                    "PreToolUse": [{"type": "command", "command": "/usr/local/bin/cc-stats-hooks"}],
                    "Notification": [{"type": "command", "command": "/usr/local/bin/cc-stats-hooks"}],
                }
            }
            with open(settings_path, "w", encoding="utf-8") as f:
                json.dump(settings, f)

            with patch("cc_stats.hooks.Path.home", return_value=Path(tmpdir)):
                uninstall_hooks(scope="user")

            with open(settings_path, encoding="utf-8") as f:
                result = json.load(f)

            # hooks key should be removed entirely when empty
            assert "hooks" not in result

    @patch("cc_stats.hooks.get_hook_command", return_value="/usr/local/bin/cc-stats-hooks")
    def test_removes_old_format_hooks(self, mock_cmd):
        """向后兼容：卸载旧格式 (python -m cc_stats.hooks) 的 hook"""
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            settings_path = Path(tmpdir) / ".claude" / "settings.json"
            settings_path.parent.mkdir(parents=True, exist_ok=True)
            settings = {
                "hooks": {
                    "Stop": [{"type": "command", "command": "/usr/bin/python3 -m cc_stats.hooks"}],
                    "PreToolUse": [{"type": "command", "command": "/usr/bin/python3 -m cc_stats.hooks"}],
                }
            }
            with open(settings_path, "w", encoding="utf-8") as f:
                json.dump(settings, f)

            with patch("cc_stats.hooks.Path.home", return_value=Path(tmpdir)):
                uninstall_hooks(scope="user")

            with open(settings_path, encoding="utf-8") as f:
                result = json.load(f)

            assert "hooks" not in result

    @patch("cc_stats.hooks.get_hook_command", return_value="/usr/local/bin/cc-stats-hooks")
    def test_preserves_other_hooks(self, mock_cmd):
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            settings_path = Path(tmpdir) / ".claude" / "settings.json"
            settings_path.parent.mkdir(parents=True, exist_ok=True)
            settings = {
                "hooks": {
                    "Stop": [
                        {"type": "command", "command": "/usr/local/bin/cc-stats-hooks"},
                        {"type": "command", "command": "echo other"},
                    ],
                }
            }
            with open(settings_path, "w", encoding="utf-8") as f:
                json.dump(settings, f)

            with patch("cc_stats.hooks.Path.home", return_value=Path(tmpdir)):
                uninstall_hooks(scope="user")

            with open(settings_path, encoding="utf-8") as f:
                result = json.load(f)

            assert len(result["hooks"]["Stop"]) == 1
            assert result["hooks"]["Stop"][0]["command"] == "echo other"

    @patch("cc_stats.hooks.get_hook_command", return_value="/usr/local/bin/cc-stats-hooks")
    def test_no_settings_file_returns_true(self, mock_cmd):
        import tempfile
        with tempfile.TemporaryDirectory() as tmpdir:
            with patch("cc_stats.hooks.Path.home", return_value=Path(tmpdir)):
                result = uninstall_hooks(scope="user")
            assert result is True


if __name__ == "__main__":
    unittest.main()
