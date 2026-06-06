#!/usr/bin/env bash
# 生成带白色圆角底的商店图标（全平台 launcher 使用）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/assets/app_icon.png"
OUT="${ROOT}/assets/app_icon_store.png"
SIZE=1024
PAD=140
RADIUS=220

python3 <<PY
from pathlib import Path
try:
    from PIL import Image, ImageDraw
except ImportError:
    raise SystemExit("请先安装 Pillow: pip3 install Pillow")

src = Path("${SRC}")
out = Path("${OUT}")
size = ${SIZE}
pad = ${PAD}
radius = ${RADIUS}

fg = Image.open(src).convert("RGBA")
side = min(fg.size)
fg = fg.crop(((fg.width - side) // 2, (fg.height - side) // 2,
              (fg.width + side) // 2, (fg.height + side) // 2))
inner = size - pad * 2
fg = fg.resize((inner, inner), Image.Resampling.LANCZOS)

canvas = Image.new("RGBA", (size, size), (255, 255, 255, 255))
mask = Image.new("L", (size, size), 0)
draw = ImageDraw.Draw(mask)
draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
canvas.putalpha(mask)
canvas.paste(fg, (pad, pad), fg)
canvas.save(out, format="PNG")
print(f"Wrote {out}")
PY
