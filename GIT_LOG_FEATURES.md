# CC Statistics - Git Log 功能文档

## 概述

CC Statistics 现已支持 Git 日志集成，可以自动跟踪和统计与 Git 提交关联的 AI 使用情况。

## 核心功能

### 1. Git Hook 自动化记录

- **安装 Git Hook**：
  ```bash
  cc-stats --install-git-hook
  ```
  会在当前 Git 仓库的 `.git/hooks/` 目录下安装 `post-commit` hook

- **工作原理**：
  - 每次 `git commit` 后自动触发
  - 读取 Claude Code 的会话统计数据
  - 将 AI 使用情况记录到 `.ai-usage.log` 文件

- **日志格式**：
  ```json
  {
    "timestamp": "2024-04-18T10:30:00Z",
    "repo_path": "/path/to/repo",
    "stats": {
      "user_instructions": 5,
      "tool_calls": 10,
      "active_duration": 1800,
      "code_additions": 100,
      "code_deletions": 20,
      "total_tokens": 50000,
      "estimated_cost": 0.15
    },
    "commit": {
      "hash": "abc123",
      "author": "User Name",
      "author_email": "user@example.com",
      "message": "Commit message"
    },
    "model_usage": {
      "claude-sonnet-4": {
        "input_tokens": 30000,
        "output_tokens": 20000
      }
    }
  }
  ```

### 2. CLI 命令

#### 查看 Git Hook 日志摘要
```bash
cc-stats --git-log-summary
```
输出：
```
📊 Git AI Usage Summary
========================
Repository: /path/to/repo
Total commits: 9
Total authors: 2

User One (5 commits):
  2024-04-13: 1 commit, 38K tokens, 21m, +47 lines, $0.110
  2024-04-15: 1 commit, 35K tokens, 18m, +58 lines, $0.105
  2024-04-16: 1 commit, 45K tokens, 25m, +70 lines, $0.135
  2024-04-18: 2 commits, 80K tokens, 50m, +120 lines, $0.240

User Two (4 commits):
  2024-04-14: 1 commit, 28K tokens, 14m, +45 lines, $0.084
  2024-04-16: 1 commit, 18K tokens, 12m, +22 lines, $0.054
  2024-04-17: 1 commit, 25K tokens, 10m, +35 lines, $0.075
  2024-04-18: 1 commit, 40K tokens, 15m, +65 lines, $0.120
```

#### 管理 Git Hook
```bash
# 安装
cc-stats --install-git-hook

# 卸载
cc-stats --uninstall-git-hook

# 检查状态
cc-stats --check-git-hook
```

### 3. Web Dashboard

#### 启动 Web 服务
```bash
cc-stats-web
```
服务启动在 http://localhost:8000

#### 可访问的页面

1. **Git Log 统计页面**：`http://localhost:8000/git-log.html`
   - 展示按作者分组的 AI 使用统计
   - 支持按日/周/月切换统计维度
   - 显示总体指标：Tokens、活跃时间、代码变更、成本
   - 每个作者的详细时间段数据

2. **API 端点**：
   - `GET /api/git-log-stats?dimension=day&log_file=path/to/log`
   - `GET /api/git-log-summary`
   - `GET /api/git-hook-status`

#### 界面功能

**总体指标卡片**：
- Total Tokens：总 Token 使用量
- Active Time：总活跃时长
- Net Code：净代码变更量
- Est. Cost：估算成本

**按作者统计卡片**：
- 每个作者的提交次数、Token 使用量、成本
- 按时间段（日/周/月）的详细数据表格
- 每个时间段显示：提交数、时长、Tokens、代码变更

**维度切换**：
- 日维度：每天的数据
- 周维度：每周的数据聚合
- 月维度：每月的数据聚合

## 技术实现

### 后端（FastAPI）

**主要 API 端点**：

1. **获取 Git Log 统计**
   ```python
   GET /api/git-log-stats
   参数：
   - dimension: "day" | "week" | "month"
   - log_file: 日志文件路径（可选，默认为 .ai-usage.log）
   ```

2. **获取摘要**
   ```python
   GET /api/git-log-summary
   ```

3. **检查 Git Hook 状态**
   ```python
   GET /api/git-hook-status
   ```

**核心函数**：

- `_get_git_log_stats(log_file_path, dimension)`：
  - 读取 JSONL 日志文件
  - 按指定的维度（日/周/月）聚合数据
  - 按作者分组
  - 计算每组的统计数据

- `aggregate_stats(logs, dimension)`：
  - 聚合多个提交的统计数据
  - 计算 tokens、时长、代码变更、成本

### 前端（原生 JavaScript）

**主要功能**：

- `loadData()`：从 API 加载数据
- `render()`：渲染统计数据到界面
- `setDimension(dim)`：切换统计维度
- `formatNumber(num)`：数字格式化
- `formatDuration(seconds)`：时长格式化

**文件结构**：
```
cc_stats_web/
├── __main__.py       # 入口点
├── server.py          # FastAPI 服务器
└── web/
    ├── index.html     # 主页
    └── git-log.html   # Git Log 统计页面
```

### Git Hook 实现

**文件**：`cc_stats/git_hook.py`

**主要函数**：

1. `install_git_hook(repo_path)`：
   - 生成 post-commit hook 脚本
   - 写入到 `.git/hooks/post-commit`
   - 设置可执行权限

2. `read_ai_usage_log(log_file_path)`：
   - 读取 JSONL 格式的日志
   - 返回日志条目列表

3. `format_ai_usage_log_summary(log_file_path)`：
   - 生成格式化的文本摘要

4. `get_current_session_stats()`：
   - 读取当前 Claude Code 会话的统计
   - 从 `~/.claude/projects/` 解析 JSONL

5. `extract_commit_info()`：
   - 获取当前提交的信息
   - 调用 `git log -1 --format=...`

## 使用场景

### 场景 1：个人开发者

1. 在项目目录运行：
   ```bash
   cc-stats --install-git-hook
   ```

2. 正常使用 Claude Code 开发并提交代码

3. 查看统计：
   ```bash
   cc-stats --git-log-summary
   ```

### 场景 2：团队协作

1. 每个团队成员安装 Git Hook

2. 共享 `.ai-usage.log` 文件或使用统一的数据收集方案

3. 启动 Web 服务器查看团队整体 AI 使用情况

### 场景 3：成本分析

1. 收集一段时间的 Git Log 数据

2. 使用 Web Dashboard 切换到"月"维度

3. 分析每个作者的 Token 使用量和成本
4. 识别高频使用 AI 的提交类型

## 数据统计指标

### 基础指标
- **提交次数**：每个时间段的 Git 提交数量
- **会话数**：Claude Code 会话次数
- **用户指令数**：用户发送的消息数量
- **工具调用次数**：工具调用的总次数

### 时间指标
- **活跃时长**：消息间隔 ≤ 5 分钟的累计时间
- **平均每提交时长**：总时长 / 提交数

### 代码指标
- **代码增加行数**：Edit/Write 工具添加的代码行数
- **代码删除行数**：Edit 工具删除的代码行数
- **净变更**：增加 - 删除

### 成本指标
- **总 Tokens**：输入 + 输出 Token 总和
- **估算成本**：根据模型定价计算的费用

## 配置选项

### CLI 参数

```bash
cc-stats [OPTIONS]

Options:
  --install-git-hook    安装 Git post-commit hook
  --uninstall-git-hook  卸载 Git hook
  --check-git-hook      检查 Git hook 安装状态
  --git-log-summary     显示 Git AI 使用日志摘要
  --list                列出所有项目
  --all                 分析所有项目
  --last N              只看最近 N 个会话
```

### Web 服务

```bash
cc-stats-web [OPTIONS]

Options:
  --host HOST    服务器地址（默认：127.0.0.1）
  --port PORT    服务器端口（默认：8000）
  --reload       启用自动重载（开发模式）
```

## 测试验证

已实现的测试覆盖：

1. ✅ Git Hook 安装和卸载
2. ✅ JSONL 日志读取
3. ✅ 按日/周/月聚合数据
4. ✅ API 端点响应
5. ✅ 前端维度切换
6. ✅ 统计数据计算准确性

测试运行：
```bash
python3 test_git_log_stats.py
```

## 已知限制

1. **日志文件位置**：当前版本需要 `.ai-usage.log` 在项目根目录
2. **并发提交**：快速连续提交可能导致日志记录不完整
3. **分支隔离**：所有分支的提交记录到同一日志文件
4. **模型定价**：使用固定定价表，可能需要更新

## 未来扩展

计划中的功能：

- [ ] 支持多仓库集中统计
- [ ] 导出 CSV/Excel 报表
- [ ] 成本趋势图表
- [ ] 按分支/标签过滤
- [ ] Web 界面支持实时数据刷新
- [ ] 成本预警和配额设置

## 贡献指南

修改代码后的验证步骤：

1. 运行语法检查：`python3 -m py_compile cc_stats/*.py`
2. 运行测试：`python3 test_git_log_stats.py`
3. 重新安装：`uv tool install . --force-reinstall`
4. 验证 CLI：`cc-stats --help`
5. 启动 Web 服务：`cc-stats-web`
6. 浏览器访问：http://localhost:8000/git-log.html

## 版本信息

- 当前版本：0.12.19
- Python 要求：>= 3.10
- 依赖：纯 Python stdlib，无第三方依赖（CLI 部分）
- Web 依赖：fastapi, uvicorn（仅 Web 功能）
