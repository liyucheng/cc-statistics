# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

cc-statistics — CLI 工具，用于统计 Claude Code 会话的 AI Coding 工程指标。

数据源：`~/.claude/projects/` 下的 JSONL 会话文件。

## Setup

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
```

## Usage

```bash
cc-stats --list              # 列出所有项目
cc-stats                     # 分析当前目录项目
cc-stats <project-keyword>   # 按关键词匹配项目
cc-stats <path/to/file.jsonl> # 分析指定 JSONL
cc-stats --all               # 分析所有项目
cc-stats --last N            # 只看最近 N 个会话
```

## Architecture

- `cc_stats/parser.py` — 解析 JSONL 为 Session/Message 数据结构
- `cc_stats/analyzer.py` — 从 Session 计算 5 项工程指标（指令数、工具调用、时长、代码行数、token）
- `cc_stats/formatter.py` — 将统计结果格式化为终端表格输出
- `cc_stats/cli.py` — argparse CLI 入口，负责文件发现和参数处理

## Key conventions

- 纯 Python stdlib，无第三方依赖
- 用户消息判定：`type == "user"` 且 `is_tool_result == False` 且 `is_meta == False`
- 活跃时间：消息间隔 ≤ 5 分钟视为活跃
- 代码行数来自 Edit/Write 工具调用的 input 参数
