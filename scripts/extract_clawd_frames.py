#!/usr/bin/env python3
"""Extract key frames from Clawd GIF animations for status bar sprites."""

import shutil
from pathlib import Path
from PIL import Image

SRC_DIR = Path.home() / "Claude" / "clawd-on-desk" / "assets" / "gif"
DST_DIR = Path(__file__).resolve().parent.parent / "cc_stats_app" / "swift" / "Resources" / "clawd"

# GIF file -> list of (frame_index, output_name)
FRAME_MAP = {
    "clawd-idle.gif": [(0, "clawd-idle-f0"), (12, "clawd-idle-f1")],
    "clawd-sleeping.gif": [(0, "clawd-sleeping-f0"), (16, "clawd-sleeping-f1"), (32, "clawd-sleeping-f2")],
    "clawd-typing.gif": [(0, "clawd-typing-f0"), (8, "clawd-typing-f1"), (24, "clawd-typing-f2")],
    "clawd-thinking.gif": [(0, "clawd-thinking-f0"), (16, "clawd-thinking-f1")],
    "clawd-error.gif": [(0, "clawd-error-f0")],
}

TARGET_2X_HEIGHT = 36


def extract_and_save(gif_path: Path, frame_idx: int, name: str) -> None:
    img = Image.open(gif_path)
    img.seek(frame_idx)
    frame = img.copy().convert("RGBA")

    bbox = frame.getbbox()
    if bbox:
        frame = frame.crop(bbox)

    w, h = frame.size
    new_h_2x = TARGET_2X_HEIGHT
    new_w_2x = round(w * new_h_2x / h)
    img_2x = frame.resize((new_w_2x, new_h_2x), Image.NEAREST)

    new_h_1x = new_h_2x // 2
    new_w_1x = new_w_2x // 2
    img_1x = frame.resize((new_w_1x, new_h_1x), Image.NEAREST)

    img_2x.save(DST_DIR / f"{name}@2x.png")
    img_1x.save(DST_DIR / f"{name}.png")
    print(f"  {name}: {w}x{h} -> @2x {new_w_2x}x{new_h_2x}, @1x {new_w_1x}x{new_h_1x}")


def main() -> None:
    # Clean destination
    if DST_DIR.exists():
        shutil.rmtree(DST_DIR)
    DST_DIR.mkdir(parents=True, exist_ok=True)

    for gif_name, frames in FRAME_MAP.items():
        gif_path = SRC_DIR / gif_name
        if not gif_path.exists():
            print(f"WARNING: {gif_path} not found, skipping")
            continue
        print(f"Processing {gif_name}:")
        for idx, name in frames:
            extract_and_save(gif_path, idx, name)

    png_count = len(list(DST_DIR.glob("*.png")))
    print(f"\nDone: {png_count} PNG files in {DST_DIR}")


if __name__ == "__main__":
    main()
