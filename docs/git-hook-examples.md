# Git Hook 示例日志文件

## 快速开始

### 1. 安装 Git Hook

```bash
# 在你的项目目录下
cc-stats --install-git-hook

# 指定自定义日志文件
cc-stats --install-git-hook --log-file .logs/ai-usage.log
```

### 2. 正常开发和提交

```bash
# 使用 Claude Code 开发
claude "帮我实现一个 RESTful API"

# 提交代码（hook 自动记录统计信息）
git add .
git commit -m "Add RESTful API endpoints"
```

### 3. 查看统计日志

```bash
# 查看格式化的统计摘要
cc-stats --read-log .ai-usage.log

# 查看原始 JSON 数据
cat .ai-usage.log
```

## 日志示例

### 格式化输出

```
AI 使用统计摘要
日志文件: .ai-usage.log
记录数: 5

提交 Hash      提交人               指令数   工具调用    时长        代码          Token        费用
------------ -------------------- -------- -------- ---------- ------------ ------------ --------
a1b2c3d4      John Doe              5        12      1h 23m     +234/-56      1.5M         $2.45
e5f6g7h8      John Doe              3        8       45m       +123/-34      890K         $1.34
i9j0k1l2      Jane Smith            8        15      2h 10m     +567/-89      2.1M         $3.56
m3n4o5p6      Jane Smith            4        6       30m       +89/-12       450K         $0.67
q7r8s9t0      John Doe              6        10      1h 5m      +178/-45      1.2M         $1.89

汇总统计:
  总指令数: 26
  总工具调用: 51
  总 Token 消耗: 6.14M
  总费用: $9.91
  总代码新增: +1191
  总代码删除: -236
```

### JSON 格式（原始）

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

## 记录的统计信息

每次 Git 提交时记录：

| 字段 | 说明 | 示例 |
|------|------|------|
| `timestamp` | 日志时间 | "2026-04-18T10:30:45.123456+00:00" |
| `commit.hash` | Git 提交 hash | "a1b2c3d4e5f6" |
| `commit.author` | 提交人 | "John Doe" |
| `commit.author_email` | 提交人邮箱 | "john@example.com" |
| `commit.message` | 提交消息 | "Add RESTful API endpoints" |
| `project` | 项目路径 | "/Users/john/projects/my-app" |
| `stats.session_count` | AI 会话数 | 3 |
| `stats.user_message_count` | 指令数（用户消息） | 5 |
| `stats.tool_call_total` | 工具调用次数 | 12 |
| `stats.active_duration` | 活跃时长 | "1h 23m 5s" |
| `stats.total_added` | 代码新增行数 | 234 |
| `stats.total_removed` | 代码删除行数 | 56 |
| `stats.token_usage_total` | Token 总消耗 | 1500000 |
| `stats.estimated_cost_usd` | 预估费用（USD） | 2.45 |
| `stats.model_distribution` | 按模型分组统计 | {"claude-sonnet-4": {...}} |

## 命令参考

```bash
# 安装 Git Hook
cc-stats --install-git-hook

# 指定日志文件路径

cc-stats --install-git-hook --log-file .logs/ai-usage.log

# 使用 pre-commit hook（提交前记录）
cc-stats --install-git-hook --hook-type pre-commit

# 生成 hook 脚本（输出到 stdout）
cc-stats --generate-git-hook > .git/hooks/post-commit

# 手动写入日志（供测试）
cc-stats --write-log .ai-usage.log --repo /path/to/repo

# 读取并格式化显示日志
cc-stats --read-log .ai-usage.log
```

## 高级用法

### Python 解析日志

```python
import json

def analyze_by_author(log_file):
    """按提交人分组统计费用"""
    by_author = {}
    
    with open(log_file) as f:
        for line in f:
            log = json.loads(line)
            author = log["commit"]["author"]
            cost = log["stats"]["estimated_cost_usd"]
            by_author[author] = by_author.get(author, 0) + cost
    
    return by_author

# 使用
by_author = analyze_by_author(".ai-usage.log")
for author, cost in sorted(by_author.items(), key=lambda x: -x[1]):
    print(f"{author}: ${cost:.2f}")
```

### Shell 查询

```bash
# 查看某个提交人的所有提交
cat .ai-usage.log | jq 'select(.commit.author == "John Doe")'

# 查看费用超过 $1 的提交
cat .ai-usage.log | jq 'select(.stats.estimated_cost_usd > 1)'

# 统计总代码新增量
cat .ai-usage.log | jq '[.stats.total_added] | add'

# 按日期分组统计
cat .ai-usage.log | jq -r '.timestamp[:10]' | sort | uniq -c
```

## 集成到 CI/CD

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
      
      - name: Upload log as artifact
        uses: actions/upload-artifact@v3
        with:
          name: ai-usage-log
          path: .ai-usage.log
```

## 注意事项

1. **日志文件大小**：日志会持续增长，建议定期清理
2. **Git 忽略**：建议将日志文件添加到 `.gitignore`：
   ```bash
   echo ".ai-usage.log" >> .gitignore免   echo ".logs/" >> .gitignore
   ```
3. **隐私保护**：日志包含代码路径和提交人信息，不要提交到公开仓库
4. **性能影响**：Hook 执行开销很小（< 1 秒），对提交速度影响可忽略

## 故障排查

### Hook 没有执行

```bash
# 检查 hook 文件
ls -la .git/hooks/post-commit

# 设置执行权限
chmod +x .git/hooks/post-commit

# 手动测试
.git/hooks/post-commit
```

### 找不到会话文件

```bash
# 列出可用会话
cc-stats --list

# 检查当前项目统计
cc-stats
```

## 更多信息

详细文档请参阅：`docs/git-hook-usage.md`
