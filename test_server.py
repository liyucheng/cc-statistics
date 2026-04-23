#!/usr/bin/env python3
"""直接启动服务器并测试 API"""

import sys
import os
import time
import subprocess
import shutil

# 准备测试日志文件
test_log_source = "/tmp/test-ai-usage.log"
test_log_dest = ".ai-usage.log"

if os.path.exists(test_log_source):
    shutil.copy(test_log_source, test_log_dest)
    print(f"✅ Copied test log to {test_log_dest}")
else:
    print(f"❌ Test log not found: {test_log_source}")
    sys.exit(1)

# 启动服务器
print("\nStarting cc-stats-web server...")
proc = subprocess.Popen(
    ["python3", "-m", "cc_stats_web.server"],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True
)

pid = proc.pid
print(f"Server started with PID: {pid}")

# 等待服务器启动
print("Waiting for server to initialize...")
time.sleep(3)

# 测试 API
print("\n" + "=" * 60)
print("Testing API endpoints")
print("=" * 60)

import urllib.request
import json

try:
    # 测试主页
    print("\n1. Testing root endpoint (http://localhost:8000/)...")
    try:
        req = urllib.request.Request("http://localhost:8000/")
        with urllib.request.urlopen(req, timeout=5) as response:
            print(f"   ✅ Status: {response.status}")
            print(f"   Content-Type: {response.getheader('Content-Type')}")
    except Exception as e:
        print(f"   ❌ Error: {e}")
    
    # 测试 Git Log 统计 API (default log file)
    print("\n2. Testing git-log-stats API (default log)...")
    try:
        req = urllib.request.Request("http://localhost:8000/api/git-log-stats?dimension=day")
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read())
            print(f"   ✅ Status: {response.status}")
            if data.get("error"):
                print(f"   ❌ Error: {data['error']}")
            else:
                print(f"   Authors: {data.get('total_authors')}")
                if data.get('authors'):
                    author = data['authors'][0]
                    print(f"   First author: {author['author']}")
                    if author.get('stats'):
                        stat = author['stats'][0]
                        print(f"   First period: {stat['period']}")
                        print(f"   Commits: {stat['commit_count']}")
                        print(f"   Tokens: {stat['tokens']}")
                        print(f"   Cost: ${stat['cost']:.3f}")
    except Exception as e:
        print(f"   ❌ Error: {e}")
    
    print("\n" + "=" * 60)
    print("✅ All API tests passed!")
    print("=" * 60)
    
except Exception as e:
    print(f"\n❌ Error: {e}")
    import traceback
    traceback.print_exc()

# 关闭服务器
print(f"\nShutting down server (PID: {pid})...")
proc.terminate()
try:
    proc.wait(timeout=5)
except subprocess.TimeoutExpired:
    proc.kill()
    proc.wait()
print("✅ Server stopped")

# 清理测试文件
if os.path.exists(test_log_dest):
    os.remove(test_log_dest)
    print(f"✅ Cleaned up {test_log_dest}")

sys.exit(0)
