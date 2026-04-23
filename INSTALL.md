# 打包和安装指南

## 概述

cc-statistics 使用标准 Python 打包工具，支持 pip 和 pipx 安装。

## 依赖要求

- Python 3.10 或更高版本
- setuptools 68.0 或更高版本
- pip / pipx（任选其一）

---

## 方法 1：使用 pip 安装（推荐用于全局安装）

### 安装

```bash
# 安装到系统 Python
pip install cc-statistics

# 或使用 pip3
pip3 install cc-statistics
```

### 验证安装

```bash
# 检查版本
cc-stats --version

# 列出可用项目
cc-stats --list

# 查看帮助
cc-stats --help
```

### 升级

```bash
pip install --upgrade cc-statistics
```

### 卸载

```bash
pip uninstall cc-statistics
```

---

## 方法 2：使用 pipx 安装（推荐用于隔离环境）

### 为什么使用 pipx？

pipx 会为每个包创建独立的虚拟环境，避免依赖冲突，更适合 CLI 工具。

### 安装

```bash
# 安装 pipx（如果还没有）
pip install pipx
# 或
brew install pipx  # macOS

# 使用 pipx 安装 cc-statistics
pipx install cc-statistics
```

### 验证安装

```bash
# 检查版本
cc-stats --version

# 列出安装的包
pipx list
```

### 升级

```bash
pipx upgrade cc-statistics
```

### 卸载

```bash
pipx uninstall cc-statistics
```

---

## 方法 3：从本地安装（开发模式）

### 克隆仓库

```bash
git clone https://github.com/androidZzT/cc-statistics.git
cd cc-statistics
```

### 开发模式安装（可编辑）

```bash
# 开发模式安装（代码修改后无需重新安装）
pip install -e .

# 或使用 pipx
pipx install --editable .
```

### 验证

```bash
cc-stats --version
```

### 卸载

```bash
# pip
pip uninstall cc-statistics

# pipx
pipx uninstall cc-statistics
```

---

## 方法 4：从源码构建并安装

### 构建分发包

```bash
# 安装构建工具
pip install build

# 构建 wheel 和 sdist
python -m build
```

构建完成后，在 `dist/` 目录下会生成：
- `cc-statistics-0.12.19-py3-none-any.whl`
- `cc-statistics-0.12.19.tar.gz`

### 从构建的包安装

```bash
# 安装 wheel（推荐）
pip install dist/cc-statistics-0.12.19-py3-none-any.whl

# 或安装源码包
pip install dist/cc-statistics-0.12.19.tar.gz
```

---

## 方法 5：从 PyPI 安装

cc-statistics 已发布到 PyPI：https://pypi.org/project/cc-statistics/

### 安装

```bash
pip install cc-statistics
```

### 查看版本

```bash
pip show cc-statistics
```

---

## 开发者：发布到 PyPI

### 1. 准备工作

```bash
# 安装发布工具
pip install build twine

# 检查版本号（在 pyproject.toml 中）
cat pyproject.toml | grep version
```

### 2. 构建

```bash
# 清理旧的构建文件
rm -rf dist/ build/

# 构建
python -m build
```

### 3. 测试发布（发布到 TestPyPI）

```bash
# 上传到 TestPyPI
twine upload --repository testpypi dist/*

# 从 TestPyPI 测试安装
pip install --index-url https://test.pypi.org/simple/ cc-statistics
```

### 4. 正式发布（发布到 PyPI）

```bash
# 上传到 PyPI
twine upload dist/*

# 或使用 API Token（避免每次输入密码）
# 1. 在 PyPI 创建 API Token
# 2. 将 Token 保存到 ~/.pypirc
# 3. 直接使用 twine upload
```

### 5. 验证发布

```bash
# 等待几分钟让 PyPI 索引
pip install --upgrade cc-statistics
pip show cc-statistics
```

---

## 安装后的文件位置

### pip 安装

```
/usr/local/lib/python3.10/site-packages/cc_stats/  # 包代码
/usr/local/bin/cc-stats                           # 命令行工具
```

### pipx 安装

```
~/.local/pipx/venvs/cc-statistics/               # 虚拟环境
~/.local/bin/cc-stats                             # 命令行工具
```

### 开发模式安装

```
/path/to/cc-statistics/cc_stats/                  # 源码目录（可编辑）
/usr/local/bin/cc-stats                           # 命令行工具
```

---

## 配置文件位置

### 配置目录

```
~/.cc-stats/          # 配置文件目录
  ├── notify_config.json      # 通知配置
  └── update_cache.json       # 版本检查缓存
```

### Claude Code Hooks

```
~/.claude/settings.json       # 全局 hooks
.claude/settings.local.json  # 项目级 hooks
```

### Git Hooks

```
.git/hooks/post-commit       # Git 提交 hook
.git/hooks/pre-commit        # Git 提交前 hook
```

---

## 常见问题

### Q: 安装后找不到 cc-stats 命令？

A: 检查 PATH 是否包含 Python 的 bin 目录：

```bash
# pip 安装的路径
echo $PATH | grep -o '/usr/local/bin'

# pipx 安装的
echo $PATH | grep -o '/.local/bin'

# 手动添加到 PATH
export PATH="$HOME/.local/bin:$PATH"
```

### Q: 权限错误？

A: 使用 `--user` 选项：

```bash
pip install --user cc-statistics
```

### Q: 依赖冲突？

A: 使用 pipx 安装（隔离环境）：

```bash
pipx install cc-statistics
```

### Q: 如何验证安装成功？

A:

```bash
# 检查命令
which cc-stats

# 检查版本
cc-stats --version

# 运行基本命令
cc-stats --list
```

### Q: 如何调试安装问题？

A:

```bash
# 详细输出
pip install -v cc-statistics

# 清理缓存
pip cache purge

# 重新安装
pip install --force-reinstall cc-statistics
```

---

## 更新日志

当前版本：**0.12.19**

### 最新更新

- ✅ 新增 Git Hook 集成（自动记录 AI 使用统计到日志文件）
- ✅ 支持多平台会话解析（Claude Code / Codex / Gemini CLI）
- ✅ 周报/月报生成
- ✅ Usage Quota 预测
- ✅ 零依赖（纯 Python 标准库）

---

## 推荐安装方式

| 场景 | 推荐方式 |
|------|---------|
| 日常使用 | `pipx install cc-statistics` |
| 开发者 | `pip install -e .` |
| 多版本管理 | `pipx install cc-statistics` |
| 容器环境 | `pip install cc-statistics` |

---

## 下一步

安装完成后，建议：

1. **安装 Claude Code Hooks**（可选）
   ```bash
   cc-stats --install-hooks
   ```

2. **安装 Git Hook**（可选）
   ```bash
   cc-stats --install-git-hook
   ```

3. **查看可用项目**
   ```bash
   cc-stats --list
   ```

4. **分析当前项目**
   ```bash
   cc-stats
   ```

---

## 获取帮助

- GitHub Issues: https://github.com/androidZzT/cc-statistics/issues
- 文档: https://github.com/androidZzT/cc-statistics#readme
- PyPI: https://pypi.org/project/cc-statistics/
