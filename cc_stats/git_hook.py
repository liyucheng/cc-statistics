"""Git Hook 集成：在提交时自动记录 AI 使用统计到 log 文件

使用方法：
  1. 安装 Git Hook:
     cc-stats --install-git-hook --log-file .ai-usage.log
  
  2. 或手动生成 hook 脚本:
     cc-stats --generate-git-hook > .git/hooks/pre-commit
  
  3. 提交时会自动记录:
     - 指令数
     - 工具调用次数
     - 活跃时长
     - 代码新增/删除行数
     - Token 消耗
     - 预估费用
     - 提交人信息
"""

from __future__ import annotations

import json
import os
import subprocess
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


@dataclass
class GitCommitInfo:
    """Git 提交信息"""
    hash: str
    author: str
    author_email: str
    message: str
    timestamp: str


@dataclass
class AIUsageLog:
    """AI 使用统计日志"""
    timestamp: str
    commit_info: GitCommitInfo | None
    project_path: str
    session_count: int
    user_message_count: int  # 指令数
    tool_call_total: int  # 工具调用次数
    active_duration_seconds: float  # 活跃时长（秒）
    total_added: int  # 代码新增行数
    total_removed: int  # 代码删除行数
    token_usage_total: int  # Token 总消耗
    estimated_cost_usd: float  # 预估费用
    model_distribution: dict[str, dict[str, int]] = field(default_factory=dict)  # 按模型的 token 分布


def get_current_commit_info(repo_path: str | None = None) -> GitCommitInfo | None:
    """获取当前提交信息（在 pre-commit hook 中调用）"""
    if repo_path is None:
        repo_path = os.getcwd()
    
    try:
        # 获取当前用户配置
        result = subprocess.run(
            ["git", "config", "user.name"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5,
        )
        author = result.stdout.strip() if result.returncode == 0 else "Unknown"
        
        result = subprocess.run(
            ["git", "config", "user.email"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5,
        )
        author_email = result.stdout.strip() if result.returncode == 0 else ""
        
        # 获取当前提交消息（pre-commit 阶段可能还没有）
        # 在 pre-commit 中无法获取 commit hash，用 HEAD 代替
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5,
        )
        commit_hash = result.stdout.strip()[:8] if result.returncode == 0 else "pending"
        
        # 获取提交消息（如果是 amend 或有暂存）
        result = subprocess.run(
            ["git", "log", "-1", "--format=%s"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5,
        )
        message = result.stdout.strip() if result.returncode == 0 else ""
        
        timestamp = datetime.now(timezone.utc).isoformat()
        
        return GitCommitInfo(
            hash=commit_hash,
            author=author,
            author_email=author_email,
            message=message,
            timestamp=timestamp,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return None


def get_current_commit_info_post_commit(repo_path: str | None = None) -> GitCommitInfo | None:
    """获取当前提交信息（在 post-commit hook 中调用，可以获取完整的 commit hash）"""
    if repo_path is None:
        repo_path = os.getcwd()
    
    try:
        # 获取刚提交的 commit hash
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode != 0:
            return None
        commit_hash = result.stdout.strip()
        
        # 获取完整的 commit 信息
        result = subprocess.run(
            ["git", "log", "-1", "--format=%an|%ae|%s|%ci"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode != 0:
            return None
        
        parts = result.stdout.strip().split("|", 3)
        if len(parts) < 4:
            return None
        
        author, author_email, message, committer_date = parts
        
        timestamp = datetime.now(timezone.utc).isoformat()
        
        return GitCommitInfo(
            hash=commit_hash[:8],
            author=author,
            author_email=author_email,
            message=message,
            timestamp=timestamp,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return None


def generate_ai_usage_log(
    log_file_path: str,
    repo_path: str | None = None,
    hook_type: str = "post-commit",  # "pre-commit" 或 "post-commit"
) -> bool:
    """生成 AI 使用统计日志并写入文件
    
    Args:
        log_file_path: 日志文件路径
        repo_path: Git 仓库路径
        hook_type: Hook 类型，pre-commit 或 post-commit
    
    Returns:
        是否成功
    """
    from .analyzer import analyze_session, merge_stats
    from .parser import (
        find_codex_sessions,
        find_codex_sessions_by_keyword,
        find_gemini_sessions,
        find_gemini_sessions_by_keyword,
        find_sessions,
        find_sessions_by_keyword,
        parse_session_file,
    )
    from .pricing import estimate_cost_from_token_by_model
    
    # 1. 获取提交信息
    if hook_type == "post-commit":
        commit_info = get_current_commit_info_post_commit(repo_path)
    else:
        commit_info = get_current_commit_info(repo_path)
    
    if commit_info is None:
        return False
    
    # 2. 收集当前项目的会话
    project_dir = Path(repo_path) if repo_path else Path.cwd()
    
    # 查找匹配当前项目的会话
    claude_files = find_sessions_by_keyword(project_dir.name)
    codex_files = find_codex_sessions_by_keyword(project_dir.name)
    gemini_files = find_gemini_sessions_by_keyword(project_dir.name)
    
    # 按 cwd 精确匹配
    all_files: list[Path] = []
    
    def match_by_cwd(files: list[Path]) -> list[Path]:
        matched = []
        for f in files:
            try:
                session = parse_session_file(f)
                if session.project_path and Path(session.project_path).resolve() == project_dir.resolve():
                    matched.append(f)
            except Exception:
                continue
        return matched
    
    all_files.extend(match_by_cwd(claude_files))
    all_files.extend(match_by_cwd(codex_files))
    all_files.extend(match_by_cwd(gemini_files))
    
    if not all_files:
        # 没有找到会话，记录空日志
        log = AIUsageLog(
            timestamp=datetime.now(timezone.utc).isoformat(),
            commit_info=commit_info,
            project_path=str(project_dir),
            session_count=0,
            user_message_count=0,
            tool_call_total=0,
            active_duration_seconds=0.0,
            total_added=0,
            total_removed=0,
            token_usage_total=0,
            estimated_cost_usd=0.0,
        )
    else:
        # 3. 分析会话
        all_stats = []
        for f in all_files:
            try:
                session = parse_session_file(f)
                stats = analyze_session(session)
                all_stats.append(stats)
            except Exception:
                continue
        
        if not all_stats:
            return False
        
        # 4. 合并统计
        merged = merge_stats(all_stats) if len(all_stats) > 1 else all_stats[0]
        
        # 5. 计算模型分布
        model_distribution = {}
        for model, usage in merged.token_by_model.items():
            model_distribution[model] = {
                "input_tokens": usage.input_tokens,
                "output_tokens": usage.output_tokens,
                "cache_read_tokens": usage.cache_read_input_tokens,
                "total": usage.total,
            }
        
        # 6. 估算费用
        cost = estimate_cost_from_token_by_model(merged.token_by_model)
        
        # 7. 创建日志
        log = AIUsageLog(
            timestamp=datetime.now(timezone.utc).isoformat(),
            commit_info=commit_info,
            project_path=str(project_dir),
            session_count=len(all_stats),
            user_message_count=merged.user_message_count,
            tool_call_total=merged.tool_call_total,
            active_duration_seconds=merged.active_duration.total_seconds(),
            total_added=merged.total_added + merged.git_total_added,
            total_removed=merged.total_removed + merged.git_total_removed,
            token_usage_total=merged.token_usage.total,
            estimated_cost_usd=cost,
            model_distribution=model_distribution,
        )
    
    # 8. 写入日志文件
    log_path = Path(log_file_path)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    
    # 追加写入 JSON Lines 格式
    log_dict = {
        "timestamp": log.timestamp,
        "commit": {
            "hash": log.commit_info.hash if log.commit_info else "",
            "author": log.commit_info.author if log.commit_info else "",
            "author_email": log.commit_info.author_email if log.commit_info else "",
            "message": log.commit_info.message if log.commit_info else "",
            "timestamp": log.commit_info.timestamp if log.commit_info else "",
        } if log.commit_info else None,
        "project": log.project_path,
        "stats": {
            "session_count": log.session_count,
            "user_message_count": log.user_message_count,
            "tool_call_total": log.tool_call_total,
            "active_duration_seconds": log.active_duration_seconds,
            "active_duration": format_duration(log.active_duration_seconds),
            "total_added": log.total_added,
            "total_removed": log.total_removed,
            "token_usage_total": log.token_usage_total,
            "estimated_cost_usd": log.estimated_cost_usd,
            "model_distribution": log.model_distribution,
        },
    }
    
    with open(log_path, "a", encoding="utf-8") as f:
        f.write(json.dumps(log_dict, ensure_ascii=False) + "\n")
    
    return True


def format_duration(seconds: float) -> str:
    """格式化时长"""
    total = int(seconds)
    if total < 0:
        return "0s"
    h, rem = divmod(total, 3600)
    m, s = divmod(rem, 60)
    parts = []
    if h:
        parts.append(f"{h}h")
    if m:
        parts.append(f"{m}m")
    if s or not parts:
        parts.append(f"{s}s")
    return " ".join(parts)


def generate_hook_script(log_file_path: str = ".ai-usage.log", hook_type: str = "post-commit") -> str:
    """生成 Git Hook 脚本
    
    Args:
        log_file_path: 日志文件路径
        hook_type: hook 类型，pre-commit 或 post-commit
    
    Returns:
        Hook 脚本内容
    """
    hook_type_str = "pre-commit" if hook_type == "pre-commit" else "post-commit"
    
    script = f"""#!/bin/bash
# cc-statistics Git Hook - 自动记录 AI 使用统计
# Generated by cc-stats --generate-git-hook
# Log file: {log_file_path}

# 获取 cc-stats 命令路径
CC_STATS_CMD=""

# 优先查找 cc-stats 命令
if command -v cc-stats &> /dev/null; then
    CC_STATS_CMD="cc-stats"
else
    # fallback 到 python -m cc_stats.git_hook
    if command -v python3 &> /dev/null; then
        CC_STATS_CMD="python3 -m cc_stats.git_hook"
    else
        CC_STATS_CMD="python -m cc_stats.git_hook"
    fi
fi

# 生成日志
REPO_PATH="$(git rev-parse --show-toplevel)"
LOG_FILE="{log_file_path}"

# 将日志文件路径转换为相对于仓库根目录的路径
if [[ "$LOG_FILE" != /* ]]; then
    LOG_FILE="$REPO_PATH/$LOG_FILE"
fi

# 调用 cc-stats 生成日志
$CC_STATS_CMD --write-log "$LOG_FILE" --repo "$REPO_PATH" --hook-type "{hook_type_str}"

# 返回原始退出码
exit $?
"""
    return script


def install_git_hook(
    log_file_path: str = ".ai-usage.log",
    hook_type: str = "post-commit",
    repo_path: str | None = None,
) -> bool:
    """安装 Git Hook
    
    Args:
        log_file_path: 日志文件路径
        hook_type: hook 类型，pre-commit 或 post-commit
        repo_path: Git 仓库路径
    
    Returns:
        是否成功
    """
    repo = Path(repo_path) if repo_path else Path.cwd()
    git_dir = repo / ".git"
    
    # 检查是否是 worktree（.git 是文件而非目录）
    if git_dir.is_file():
        # 读取 worktree 的 gitdir 指向
        try:
            with open(git_dir, "r", encoding="utf-8") as f:
                content = f.read().strip()
            if content.startswith("gitdir: "):
                gitdir_path = content[8:].strip()
                # 如果是相对路径，相对于 worktree 目录解析
                if not Path(gitdir_path).is_absolute():
                    gitdir_path = (repo / gitdir_path).resolve()
                # hooks 目录在 gitdir 的 hooks 子目录
                hooks_dir = Path(gitdir_path) / "hooks"
            else:
                raise ValueError(f"Invalid .git file format: {content}")
        except Exception as e:
            print(f"Warning: Failed to read worktree .git file: {e}")
            return False
    else:
        # 普通仓库
        hooks_dir = git_dir / "hooks"
    
    if not hooks_dir.exists():
        print(f"Warning: Hooks directory not found: {hooks_dir}")
        print("This may be a worktree without hooks support.")
        return False
    
    hook_file = hooks_dir / hook_type
    script = generate_hook_script(log_file_path, hook_type)
    
    with open(hook_file, "w", encoding="utf-8") as f:
        f.write(script)
    
    # 设置可执行权限
    hook_file.chmod(0o755)
    
    return True


def read_ai_usage_log(log_file_path: str) -> list[dict[str, Any]]:
    """读取 AI 使用日志
    
    Args:
        log_file_path: 日志文件路径
    
    Returns:
        日志条目列表
    """
    log_path = Path(log_file_path)
    if not log_path.exists():
        return []
    
    logs = []
    with open(log_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                logs.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    
    return logs


def format_ai_usage_log_summary(log_file_path: str) -> str:
    """格式化 AI 使用日志摘要
    
    Args:
        log_file_path: 日志文件路径
    
    Returns:
        格式化的摘要文本
    """
    logs = read_ai_usage_log(log_file_path)
    
    if not logs:
        return f"日志文件为空: {log_file_path}"
    
    lines = [
        f"AI 使用统计摘要",
        f"日志文件: {log_file_path}",
        f"记录数: {len(logs)}",
        f"",
        f"{'提交 Hash':<12} {'提交人':<20} {'指令数':>8} {'工具调用':>8} {'时长':>10} {'代码':>12} {'Token':>12} {'费用':>8}",
        f"{'-'*12} {'-'*20} {'-'*8} {'-'*8} {'-'*10} {'-'*12} {'-'*12} {'-'*8}",
    ]
    
    for log in logs[-20:]:  # 只显示最近 20 条
        commit = log.get("commit", {}) or {}
        stats = log.get("stats", {}) or {}
        
        commit_hash = commit.get("hash", "")[:8] if commit else ""
        author = commit.get("author", "")[:18] if commit else ""
        
        user_message_count = stats.get("user_message_count", 0)
        tool_call_total = stats.get("tool_call_total", 0)
        active_duration = stats.get("active_duration", "0s")
        total_added = stats.get("total_added", 0)
        total_removed = stats.get("total_removed", 0)
        token_usage_total = stats.get("token_usage_total", 0)
        estimated_cost_usd = stats.get("estimated_cost_usd", 0.0)
        
        # 格式化 Token
        if token_usage_total >= 1_000_000:
            token_str = f"{token_usage_total / 1e6:.1f}M"
        elif token_usage_total >= 1_000:
            token_str = f"{token_usage_total / 1e3:.1f}K"
        else:
            token_str = str(token_usage_total)
        
        # 格式化代码变更
        code_str = f"+{total_added}/-{total_removed}"
        
        # 格式化费用
        if estimated_cost_usd >= 1:
            cost_str = f"${estimated_cost_usd:.2f}"
        else:
            cost_str = f"${estimated_cost_usd:.3f}"
        
        lines.append(
            f"{commit_hash:<12} {author:<20} {user_message_count:>8} {tool_call_total:>8} {active_duration:>10} {code_str:>12} {token_str:>12} {cost_str:>8}"
        )
    
    if len(logs) > 20:
        lines.append(f"... (显示最近 20 条，共 {len(logs)} 条)")
    
    lines.append("")
    
    # 汇总统计
    total_instructions = sum(log.get("stats", {}).get("user_message_count", 0) for log in logs)
    total_tools = sum(log.get("stats", {}).get("tool_call_total", 0) for log in logs)
    total_tokens = sum(log.get("stats", {}).get("token_usage_total", 0) for log in logs)
    total_cost = sum(log.get("stats", {}).get("estimated_cost_usd", 0.0) for log in logs)
    total_added = sum(log.get("stats", {}).get("total_added", 0) for log in logs)
    total_removed = sum(log.get("stats", {}).get("total_removed", 0) for log in logs)
    
    # 格式化汇总 Token
    if total_tokens >= 1_000_000:
        total_token_str = f"{total_tokens / 1e6:.1f}M"
    elif total_tokens >= 1_000:
        total_token_str = f"{total_tokens / 1e3:.1f}K"
    else:
        total_token_str = str(total_tokens)
    
    lines.extend([
        f"汇总统计:",
        f"  总指令数: {total_instructions}",
        f"  总工具调用: {total_tools}",
        f"  总 Token 消耗: {total_token_str}",
        f"  总费用: ${total_cost:.2f}",
        f"  总代码新增: +{total_added}",
        f"  总代码删除: -{total_removed}",
    ])
    
    return "\n".join(lines)
