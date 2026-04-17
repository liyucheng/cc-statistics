#!/usr/bin/env python3
"""构建平台专属 wheel 和 fallback any wheel。

用法：
    # 编译当前架构 + 构建平台专属 wheel + fallback any wheel
    python scripts/build_wheels.py

    # 仅构建平台专属 wheel（假设 CCStats.app 已存在）
    python scripts/build_wheels.py --skip-compile

    # 指定架构（CI 用）
    python scripts/build_wheels.py --arch arm64
    python scripts/build_wheels.py --arch x86_64

    # 仅构建 fallback any wheel（不含 binary）
    python scripts/build_wheels.py --any-only

输出目录：dist/
"""

import argparse
import glob
import os
import platform
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SWIFT_DIR = os.path.join(ROOT, "cc_stats_app", "swift")
APP_BUNDLE = os.path.join(SWIFT_DIR, "CCStats.app")
DIST_DIR = os.path.join(ROOT, "dist")


def get_version() -> str:
    init_file = os.path.join(ROOT, "cc_stats", "__init__.py")
    with open(init_file) as f:
        for line in f:
            m = re.search(r'__version__\s*=\s*"([^"]+)"', line)
            if m:
                return m.group(1)
    raise RuntimeError("Cannot find version in cc_stats/__init__.py")


def compile_app(arch: str):
    """编译 CCStats.app for given architecture."""
    print(f"Compiling CCStats.app for {arch}...")

    swift_files = glob.glob(os.path.join(SWIFT_DIR, "**", "*.swift"), recursive=True)
    target = f"{arch}-apple-macosx12.0"
    tmp_bin = os.path.join(SWIFT_DIR, "CCStats.tmp")

    result = subprocess.run(
        [
            "swiftc",
            *swift_files,
            "-o", tmp_bin,
            "-target", target,
            "-framework", "Cocoa",
            "-framework", "SwiftUI",
            "-framework", "Carbon",
            "-framework", "UserNotifications",
            "-framework", "WebKit",
            "-lsqlite3",
            "-O",
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Swift compilation failed:\n{result.stderr}", file=sys.stderr)
        sys.exit(1)

    # Create .app bundle
    if os.path.exists(APP_BUNDLE):
        shutil.rmtree(APP_BUNDLE)

    macos_dir = os.path.join(APP_BUNDLE, "Contents", "MacOS")
    resources_dir = os.path.join(APP_BUNDLE, "Contents", "Resources")
    os.makedirs(macos_dir, exist_ok=True)
    os.makedirs(resources_dir, exist_ok=True)

    dest_bin = os.path.join(macos_dir, "CCStats")
    shutil.move(tmp_bin, dest_bin)
    os.chmod(dest_bin, 0o755)

    # Copy clawd resources
    src_clawd = os.path.join(SWIFT_DIR, "Resources", "clawd")
    if os.path.isdir(src_clawd):
        shutil.copytree(src_clawd, os.path.join(resources_dir, "clawd"))

    # Generate Info.plist
    version = get_version()
    plist_template = os.path.join(SWIFT_DIR, "Info.plist")
    with open(plist_template) as f:
        plist_content = f.read()
    plist_content = plist_content.replace("__VERSION__", version)
    with open(os.path.join(APP_BUNDLE, "Contents", "Info.plist"), "w") as f:
        f.write(plist_content)

    print(f"CCStats.app built for {arch}.")


def build_wheel() -> str:
    """Build a wheel using `python -m build` and return the .whl filename."""
    subprocess.run(
        [sys.executable, "-m", "build", "--wheel", "--outdir", DIST_DIR],
        cwd=ROOT,
        check=True,
    )
    wheels = glob.glob(os.path.join(DIST_DIR, "cc_statistics-*.whl"))
    if not wheels:
        raise RuntimeError("No wheel found in dist/")
    # Return the most recently created wheel
    return max(wheels, key=os.path.getmtime)


def rename_wheel_platform(whl_path: str, arch: str) -> str:
    """Rename a wheel from py3-none-any to py3-none-macosx_12_0_{arch}."""
    dirname = os.path.dirname(whl_path)
    basename = os.path.basename(whl_path)
    new_basename = basename.replace(
        "-py3-none-any.whl",
        f"-py3-none-macosx_12_0_{arch}.whl",
    )
    if new_basename == basename:
        print(f"Warning: wheel name did not contain '-py3-none-any.whl': {basename}")
        return whl_path
    new_path = os.path.join(dirname, new_basename)
    os.rename(whl_path, new_path)
    print(f"Renamed: {basename} -> {new_basename}")
    return new_path


def remove_app_bundle():
    """Remove CCStats.app bundle if it exists."""
    if os.path.exists(APP_BUNDLE):
        shutil.rmtree(APP_BUNDLE)


def main():
    parser = argparse.ArgumentParser(description="Build cc-statistics wheels")
    parser.add_argument(
        "--arch",
        choices=["arm64", "x86_64"],
        default=platform.machine(),
        help="Target architecture (default: current machine)",
    )
    parser.add_argument(
        "--skip-compile",
        action="store_true",
        help="Skip compilation (assume CCStats.app already exists)",
    )
    parser.add_argument(
        "--any-only",
        action="store_true",
        help="Only build the fallback any wheel (no binary)",
    )
    parser.add_argument(
        "--platform-only",
        action="store_true",
        help="Only build the platform-specific wheel (no any wheel)",
    )
    args = parser.parse_args()

    os.makedirs(DIST_DIR, exist_ok=True)

    if args.any_only:
        # Build fallback any wheel without binary
        print("Building fallback any wheel (no binary)...")
        remove_app_bundle()
        whl = build_wheel()
        print(f"Fallback wheel: {whl}")
        return

    # Step 1: Compile if needed
    if not args.skip_compile:
        compile_app(args.arch)
    elif not os.path.exists(os.path.join(APP_BUNDLE, "Contents", "MacOS", "CCStats")):
        print("Error: CCStats.app not found. Run without --skip-compile first.",
              file=sys.stderr)
        sys.exit(1)

    # Step 2: Build platform-specific wheel (with binary)
    print(f"Building platform wheel for {args.arch}...")
    whl = build_wheel()
    platform_whl = rename_wheel_platform(whl, args.arch)
    print(f"Platform wheel: {platform_whl}")

    if args.platform_only:
        return

    # Step 3: Build fallback any wheel (without binary)
    print("Building fallback any wheel (no binary)...")
    remove_app_bundle()
    any_whl = build_wheel()
    print(f"Fallback wheel: {any_whl}")

    print(f"\nAll wheels in {DIST_DIR}/:")
    for f in sorted(os.listdir(DIST_DIR)):
        if f.endswith(".whl"):
            print(f"  {f}")


if __name__ == "__main__":
    main()
