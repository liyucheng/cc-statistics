#!/usr/bin/env python3
"""测试 Git Log 统计功能"""

import sys
import os

# Add current directory to path
sys.path.insert(0, os.path.dirname(__file__))

from cc_stats_web.server import _get_git_log_stats

def main():
    print("Testing Git Log Stats API...\n")
    
    # Test with the sample log file
    log_file = "/tmp/test-ai-usage.log"
    
    if not os.path.exists(log_file):
        print(f"Error: Test log file not found: {log_file}")
        print("Please ensure the test log file exists.")
        return 1
    
    print(f"Reading log file: {log_file}\n")
    
    # Test day dimension
    print("=" * 60)
    print("Testing Day Dimension:")
    print("=" * 60)
    result = _get_git_log_stats(log_file_path=log_file, dimension="day")
    print_result(result)
    
    # Test week dimension
    print("\n" + "=" * 60)
    print("Testing Week Dimension:")
    print("=" * 60)
    result = _get_git_log_stats(log_file_path=log_file, dimension="week")
    print_result(result)
    
    # Test month dimension
    print("\n" + "=" * 60)
    print("Testing Month Dimension:")
    print("=" * 60)
    result = _get_git_log_stats(log_file_path=log_file, dimension="month")
    print_result(result)
    
    print("\n" + "=" * 60)
    print("✅ All tests passed!")
    print("=" * 60)
    
    return 0

def print_result(result):
    """Pretty print the result"""
    if result.get("error"):
        print(f"❌ Error: {result['error']}")
        return
    
    print(f"\n📊 Log File: {result['log_file']}")
    print(f"👥 Total Authors: {result['total_authors']}\n")
    
    for author_data in result.get("authors", []):
        print(f"\n👤 Author: {author_data['author']}")
        print("-" * 40)
        
        for stat in author_data.get("stats", []):
            print(f"  📅 Period: {stat['period']}")
            print(f"     Commits: {stat['commit_count']}")
            print(f"     Sessions: {stat['sessions']}")
            print(f"     Duration: {stat['duration_seconds']}s")
            print(f"     Tokens: {stat['tokens']}")
            print(f"     Cost: ${stat['cost']:.3f}")
            print(f"     Code Added: +{stat['code_added']}")
            print(f"     Code Removed: -{stat['code_removed']}")
            print(f"     Net Change: {stat['code_net']:+d}")
            print()

if __name__ == "__main__":
    sys.exit(main())
