"""格式化统计结果输出"""

from __future__ import annotations

from datetime import timedelta

from .analyzer import TOOL_DESCRIPTIONS, SessionStats


def _fmt_duration(td: timedelta) -> str:
    """将 timedelta 格式化为可读字符串"""
    total_seconds = int(td.total_seconds())
    if total_seconds < 0:
        return "0s"
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    parts = []
    if hours:
        parts.append(f"{hours}h")
    if minutes:
        parts.append(f"{minutes}m")
    if seconds or not parts:
        parts.append(f"{seconds}s")
    return " ".join(parts)


def _fmt_tokens(n: int) -> str:
    """格式化 token 数量"""
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(n)


def _bar(value: int, max_value: int, width: int = 20) -> str:
    """生成简单的文本柱状图"""
    if max_value == 0:
        return ""
    filled = int(value / max_value * width)
    return "█" * filled + "░" * (width - filled)


def format_stats(stats: SessionStats, session_count: int = 1) -> str:
    """将统计结果格式化为终端输出"""
    lines: list[str] = []
    sep = "─" * 60

    lines.append("")
    lines.append("╔══════════════════════════════════════════════════════════╗")
    lines.append("║           Claude Code 会话统计报告                      ║")
    lines.append("╚══════════════════════════════════════════════════════════╝")
    lines.append("")

    if stats.project_path and stats.project_path != "all":
        lines.append(f"  项目: {stats.project_path}")
    if session_count > 1:
        lines.append(f"  会话数: {session_count}")
    if stats.start_time:
        start_local = stats.start_time.astimezone()
        end_local = stats.end_time.astimezone() if stats.end_time else None
        lines.append(f"  时间范围: {start_local.strftime('%Y-%m-%d %H:%M')} ~ {end_local.strftime('%Y-%m-%d %H:%M') if end_local else '?'}")
    lines.append("")

    # ---- 1. 用户指令数 ----
    lines.append(f"  ① 用户指令数")
    lines.append(sep)
    lines.append(f"  对话轮次: {stats.user_message_count}")
    lines.append("")

    # ---- 2. 工具调用 ----
    lines.append(f"  ② AI 工具调用")
    lines.append(sep)
    lines.append(f"  总调用次数: {stats.tool_call_total}")
    lines.append("")
    if stats.tool_call_counts:
        sorted_tools = sorted(
            stats.tool_call_counts.items(), key=lambda x: x[1], reverse=True
        )
        max_count = sorted_tools[0][1] if sorted_tools else 1
        max_name_len = max(len(name) for name, _ in sorted_tools)

        for name, count in sorted_tools:
            desc = TOOL_DESCRIPTIONS.get(name, "")
            bar = _bar(count, max_count, 15)
            desc_part = f"  {desc}" if desc else ""
            lines.append(
                f"  {name:<{max_name_len}}  {bar} {count:>5}{desc_part}"
            )
    lines.append("")

    # ---- 3. 开发时长 ----
    lines.append(f"  ③ 开发时长")
    lines.append(sep)
    lines.append(f"  总时长:       {_fmt_duration(stats.total_duration)}")
    lines.append(f"  活跃时长:     {_fmt_duration(stats.active_duration)}")
    lines.append(f"    AI 处理:    {_fmt_duration(stats.ai_duration)}")
    lines.append(f"    用户活跃:   {_fmt_duration(stats.user_duration)}")
    if stats.total_duration.total_seconds() > 0:
        ratio = stats.active_duration.total_seconds() / stats.total_duration.total_seconds() * 100
        lines.append(f"  活跃率:       {ratio:.0f}%")
    if stats.active_duration.total_seconds() > 0:
        ai_ratio = stats.ai_duration.total_seconds() / stats.active_duration.total_seconds() * 100
        lines.append(f"  AI 占比:      {ai_ratio:.0f}%")
    if stats.turn_count:
        avg_ai = stats.ai_duration / stats.turn_count
        lines.append(f"  平均轮次耗时: {_fmt_duration(avg_ai)}/轮 ({stats.turn_count} 轮)")
    lines.append("")

    # ---- 4. 代码行数 ----
    lines.append(f"  ④ 代码变更")
    lines.append(sep)

    if stats.git_available:
        # --- Git 总变更 (已提交) ---
        git_net = stats.git_total_added - stats.git_total_removed
        git_net_str = f"+{git_net}" if git_net >= 0 else str(git_net)
        lines.append(f"  [Git 已提交]  {stats.git_commit_count} 个 commit")
        lines.append(f"  总新增: +{stats.git_total_added}  总删除: -{stats.git_total_removed}  净增: {git_net_str}")
        lines.append("")

        if stats.git_lines_by_lang:
            sorted_langs = sorted(
                stats.git_lines_by_lang.items(),
                key=lambda x: x[1]["added"] + x[1]["removed"],
                reverse=True,
            )
            max_lang_len = max(len(lang) for lang, _ in sorted_langs)
            for lang, counts in sorted_langs:
                added = counts["added"]
                removed = counts["removed"]
                net_l = added - removed
                net_l_str = f"+{net_l}" if net_l >= 0 else str(net_l)
                lines.append(
                    f"  {lang:<{max_lang_len}}  +{added:<6} -{removed:<6} net {net_l_str}"
                )
        lines.append("")

    # --- AI 工具变更 ---
    ai_net = stats.total_added - stats.total_removed
    ai_net_str = f"+{ai_net}" if ai_net >= 0 else str(ai_net)
    lines.append(f"  [AI 工具变更]  来自 Edit/Write 调用")
    lines.append(f"  总新增: +{stats.total_added}  总删除: -{stats.total_removed}  净增: {ai_net_str}")
    lines.append("")

    if stats.lines_by_lang:
        sorted_langs = sorted(
            stats.lines_by_lang.items(),
            key=lambda x: x[1]["added"] + x[1]["removed"],
            reverse=True,
        )
        max_lang_len = max(len(lang) for lang, _ in sorted_langs)
        for lang, counts in sorted_langs:
            added = counts["added"]
            removed = counts["removed"]
            net_l = added - removed
            net_l_str = f"+{net_l}" if net_l >= 0 else str(net_l)
            lines.append(
                f"  {lang:<{max_lang_len}}  +{added:<6} -{removed:<6} net {net_l_str}"
            )
    lines.append("")

    # ---- 5. Token 消耗 ----
    lines.append(f"  ⑤ Token 消耗")
    lines.append(sep)
    tu = stats.token_usage
    lines.append(f"  Input tokens:          {_fmt_tokens(tu.input_tokens):>10}")
    lines.append(f"  Output tokens:         {_fmt_tokens(tu.output_tokens):>10}")
    lines.append(f"  Cache read tokens:     {_fmt_tokens(tu.cache_read_input_tokens):>10}")
    lines.append(f"  Cache creation tokens: {_fmt_tokens(tu.cache_creation_input_tokens):>10}")
    lines.append(f"  {'':─<40}")
    lines.append(f"  合计:                  {_fmt_tokens(tu.total):>10}")
    lines.append("")

    if stats.token_by_model:
        lines.append("  按模型拆分:")
        for model, usage in sorted(stats.token_by_model.items()):
            if usage.total == 0:
                continue
            lines.append(
                f"    {model}: input={_fmt_tokens(usage.input_tokens)} "
                f"output={_fmt_tokens(usage.output_tokens)} "
                f"cache_read={_fmt_tokens(usage.cache_read_input_tokens)} "
                f"total={_fmt_tokens(usage.total)}"
            )
    lines.append("")

    return "\n".join(lines)
