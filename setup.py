from setuptools import setup, find_packages

setup(
    name="cc-statistics",
    version="0.12.19",
    description="Claude Code 会话统计工具 — 分析 AI Coding 工程指标",
    python_requires=">=3.10",
    packages=find_packages(include=["cc_stats*", "cc_stats_app*", "cc_stats_web*"]),
    package_data={
        "cc_stats_app": ["swift/**/*.swift", "swift/Info.plist", "swift/CCStats.app/**/*"],
        "cc_stats_web": ["web/**/*"],
    },
    entry_points={
        "console_scripts": [
            "cc-stats = cc_stats.cli:main",
            "cc-stats-app = cc_stats_app.__main__:main",
            "cc-stats-web = cc_stats_web.__main__:main",
            "cc-stats-hooks = cc_stats.hooks:main",
        ],
    },
    license="MIT",
    author="androidZzT",
    keywords=["claude-code", "statistics", "ai-coding", "cli"],
)
