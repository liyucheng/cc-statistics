from cc_stats.pricing import is_claude_model, match_model_pricing


def test_match_gpt_53_codex_exact():
    p = match_model_pricing("gpt-5.3-codex")
    assert p["input"] == 1.75
    assert p["output"] == 14.0
    assert p["cache_read"] == 0.175


def test_match_gpt5_codex_fallback():
    p = match_model_pricing("gpt-5.2-codex")
    assert p["input"] == 1.75
    assert p["output"] == 14.0


def test_match_claude_opus_46():
    p = match_model_pricing("claude-opus-4-6-20260101")
    assert p["input"] == 5.0
    assert p["output"] == 25.0


def test_match_claude_sonnet_4():
    p = match_model_pricing("claude-sonnet-4-20250514")
    assert p["input"] == 3.0
    assert p["output"] == 15.0


def test_match_gemini_25_flash():
    p = match_model_pricing("gemini-2.5-flash")
    assert p["input"] == 0.3
    assert p["output"] == 2.5
    assert p["cache_read"] == 0.03


def test_is_claude_model():
    assert is_claude_model("claude-sonnet-4-6")
    assert is_claude_model("sonnet")
    assert not is_claude_model("gpt-5.3-codex")
