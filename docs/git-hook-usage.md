# Git Hook 集成使用指南

cc-statistics 支持通过 Git Hook 自动记录每次提交时的 AI 使用统计。

## 功能特性

每次 Git 提交时，自动记录以下信息到日志文件：

- **指令数**：用户发送的消息数量
- **工具调用次数**：AI 调用的工具总数
- **活跃时长**：用户活跃时间（消息间隔 ≤ 5 分钟）
- **代码行数**：新增/删除的代码行数
- **Token 消耗**：总 Token 使用量
- **预估费用**：按模型定价估算的费用
- **提交人信息**：Git 用户名、邮箱、提交消息
- **模型分布**：按模型分组的 Token 使用量

## 安装方法

### 方法 1：自动安装（推荐）

```bash
# 在你的项目目录下运行
cc-stats --install-git-hook

# 指定自定义日志文件路径
cc-stats --install-git-hook --log-file .logs/ai-usage.log

# 使用 pre-commit hook（在提交前记录）
cc-stats --install-git-hook --hook-type pre-commit

# 默认使用 post-commit hook（在提交后记录）
cc-stats --install-git-hook --hook-type post-commit
```

安装完成后，每次 `git commit` 都会自动记录统计信息。

### 方法 2：手动生成 Hook 脚本

```bash
# 生成 hook 脚本
cc-stats --generate-git-hook > .git/hooks/post-commit

# 赋予执行权限
chmod +x .git/hooks/post-commit
```

### 方法 3：自定义 Hook 脚本

如果你需要在 hook 中添加其他逻辑，可以生成脚本后手动编辑：

```bash
# 生成基础脚本
cc-stats --generate-git-hook --log-file .ai-usage.log > .git/hooks/post-commit

# 编辑脚本添加自定义逻辑
vim .git/hooks/post-commit

# 设置执行权限
chmod +x .git/hooks/post-commit
```

## 使用示例

### 安装 Hook

```bash
# 在项目目录下
$ git init
$ cc-stats --install-git-hook
✅ Git Hook 已安装到 .git/hooks/post-commit
   日志文件: .ai-usage.log
   Hook 类型: post-commit

   每次提交时会自动记录 AI 使用统计到日志文件
```

### 正常开发流程

```bash
# 使用 Claude Code 开发
$ claude "帮我实现一个 RESTful API"

# 提交代码（hook 自动记录统计信息）
$ git add .
$ git commit -m "Add RESTful API endpoints"
```

### 查看日志文件

```bash
# 查看原始日志（JSON Lines 格式）
cat .ai-usage.log

# 使用 cc-stats 格式化显示
$ cc-stats --read-log .ai-usage.log

AI 使用统计摘要
日志文件: .ai-usage.log
记录数: 15

提交 Hash      提交人               指令数   工具调用    时长        代码          Token        费用
------------ -------------------- -------- -------- ---------- ------------ ------------ --------
a1b2c3d4      John Doe              5        12      1h 23m     +234/-56      1.5M         $2.45
e5f6g7h8      John Doe              3        8       45m       +123/-34      890K         $1.34
i9j0k1l2      Jane Smith            8        15      2h 10m     +567/-89      2.1M         $3.56
... (显示最近 20 条，共 15 条)

汇总统计:
  总指令数: 125
  总工具调用: 312
  总 Token 消耗: 15.2M
  总费用: $23.45
  总代码新增: +3456
  总代码删除: -789
```

## 日志文件格式

日志采用 JSON Lines 格式，每行一条记录：

```json
{
  "timestamp": "2026-04-18T10:30:45.123456+00:00",
  "commit": {
    "hash": "a1b2c3d4e5f6",
    "author": "John Doe",
    "author_email": "john@example.com",
    "message": "Add RESTful API endpoints",
    "timestamp": "2026-04-18T10:30:45.123456+00:00"
  },
  "project": "/Users/john/projects/my-app",
  "stats": {
    "session_count": 3,
    "user_message_count": 5,
    "tool_call_total": 12,
    "active_duration_seconds": 4985.0,
    "active_duration": "1h 23m 5s",
    "total_added": 234,
    "total_removed": 56,
    "token_usage_total": 1500000,
    "estimated_cost_usd": 2.45,
    "model_distribution": {
      "claude-sonnet-4": {
        "input_tokens": 800000,
        "output_tokens": 600000,
        "cache_read_tokens": 50000,
        "total": 1450000
      },
      "claude-haiku-4.5": {
        "input_tokens": 30000,
        "output_tokens": 20000,
        "cache_read_tokens": 0,
        "total": 50000
      }
    }
  }
}
```

## Hook 类型说明

### pre-commit vs post-commit

| 类型 | 时机 | Commit Hash | 说明 |
|------|------|-------------|------|
| pre-commit | 提交前执行 | pending | 无法获取完整的 commit hash |
| post-commit | 提交后执行 | 实际 hash | 可以获取完整的 commit hash |

**推荐使用 `post-commit`**，因为可以获取完整的 commit 信息。

### pre-commit 的适用场景

- 需要在提交前检查 AI 使用量
- 想在提交失败时不记录日志

### post-commit 的适用场景

- 需要完整的 commit 信息
- 提交后的统计和报告（推荐）

## 高级用法

### 手动写入日志

```bash
# 手动触发日志写入（不通过 hook）
$ cc-stats --write-log .ai-usage.log --repo /path/to/repo --hook-type post-commit
✅ AI 使用统计已写入: .ai-usage.log
```

### 集成到 CI/CD

```yaml
# .github/workflows/ai-usage-report.yml
name: AI Usage Report

on:
  push:
    branches: [main]

jobs:
  report:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install cc-stats
        run: pip install cc-statistics
      
      - name: Generate AI usage log
        run: cc-stats --write-log .ai-usage.log --repo $PWD --hook-type post-commit
      
      - name: Report to Slack
        run: |
          # 使用 cc-stats 的 webhook 功能发送报告
          cc-stats --notify ${{ secrets.SLACK_WEBHOOK }}
```

### 自定义日志处理

```python
# 解析日志文件进行自定义分析
import json

def analyze_ai_usage(log_file: str):
    logs = []
    with open(log_file) as f:
        for line in f:
            logs.append(json.loads(line))
    
    # 按提交人分组
    by_author = {}
    for log in logs:
        author = log["commit"]["author"]
        cost = log["stats"]["estimated_cost_usd"]
        by_author[author] = by_author.get(author, 0) + cost
    
    # 输出统计
    print("AI 费用按提交人分布:")
    for author, cost in sorted(by_author.items(), key=lambda x: -x[1]):
        print(f"  {author}: ${cost:.2f}")

# 使用
analyze_ai_usage(".ai-usage.log")
```

## 故障排查

### Hook 没有执行

```bash
# 检查 hook 文件是否存在
ls -la .git/hooks/post-commit

# 检查 hook 是否有执行权限
chmod +x .git/hooks/post-commit

# 手动测试 hook
.git/hooks/post-commit
```

### 日志文件未生成

```bash
# 检查是否有写权限
touch .ai-usage.log

# 手动触发日志写入
cc-stats --write-log .ai-usage.log --repo $PWD --hook-type post-commit

# 检查输出
cat .ai-usage.log
```

### 找不到会话文件

```bash
# 检查 cc-stats 是否能找到会话
cc-stats --list

# 手动分析当前项目
cc-stats
```

## 卸载 Hook

```bash
# 删除 hook 文件
rm .git/hooks/post-commit

# 或者在 .gitignore 中忽略日志文件
echo ".ai-usage.log" >> .gitignore
```

## 注意事项

1. **日志文件大小**：日志会持续增长，建议定期清理或归档
2. **性能影响**：Hook 会在每次提交时执行，但开销很小（< 1 秒）
3. **隐私保护**：日志文件包含代码路径和提交人信息，不要提交到公开仓库
4. **多平台统计**：自动合并 Claude Code / Codex / Gemini CLI 的会话
5. **时间匹配**：按项目路径精确匹配会话，避免跨项目污染

## 常见问题

### Q: 可以同时使用 pre-commit 和 post-commit 吗？

A: 可以，但建议只使用 post-commit，因为它可以获取完整的 commit 信息。

### Q: 日志文件应该提交到 Git 吗？

A: 不建议。建议添加到 .gitignore：

```bash
echo ".ai-usage.log" >> .gitignore
```

### Q: 可以记录到数据库吗？

A: 可以，解析日志文件后写入到你喜欢的数据库。

### Q: 如何按时间段筛选日志？

A: 可以使用 jq 等工具筛选：

```bash
# 只看最近 7 天的日志
cat .ai-usage.log | jq 'select(.commit.timestamp | fromdateiso8601 > now - 7*24*60*60)'
```

## 总结

Git Hook 集成让你在每次提交时自动记录 AI 使用统计，无需手动操作。日志采用 JSON Lines 格式，易于解析和集成到其他系统。

**核心命令：**

```bash
# 安装
cc-stats --install-git-hook

# 查看日志
cc-stats --read-log .ai-usage.log

# 生成 hook 脚本
cc-stats --generate-git-hook > .git/hooks/post-commit
```

**日志内容：**

- 指令数
- 工具调用次数
- 活跃时长
- 代码行数
- Token 消耗
- 预估费用
- 提交人信息
- 模型分布
