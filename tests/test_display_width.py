"""Tests for CJK display width helpers."""

from cc_stats.cli import _display_width, _pad_right


class TestDisplayWidth:
    def test_ascii_only(self):
        assert _display_width("hello") == 5

    def test_empty_string(self):
        assert _display_width("") == 0

    def test_chinese_chars(self):
        # Each CJK character is 2 columns wide
        assert _display_width("项目") == 4
        assert _display_width("合计") == 4

    def test_mixed_ascii_and_cjk(self):
        assert _display_width("abc中文") == 7  # 3 + 2*2

    def test_fullwidth_chars(self):
        # Fullwidth Latin letters
        assert _display_width("Ａ") == 2

    def test_japanese(self):
        assert _display_width("テスト") == 6  # 3 katakana * 2


class TestPadRight:
    def test_ascii_padding(self):
        result = _pad_right("abc", 6)
        assert result == "abc   "
        assert _display_width(result) == 6

    def test_cjk_padding(self):
        result = _pad_right("项目", 8)
        assert result == "项目    "
        assert _display_width(result) == 8

    def test_no_padding_needed(self):
        result = _pad_right("abcd", 4)
        assert result == "abcd"

    def test_mixed_padding(self):
        result = _pad_right("ab中", 8)
        # "ab中" is 4 wide, needs 4 spaces
        assert result == "ab中    "
        assert _display_width(result) == 8
