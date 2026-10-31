"""Generate native icon resources from AppStore/icon.png using Pillow."""

import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "AppStore/icon.png"

with Image.open(SOURCE) as icon:
    assert icon.format == "PNG" and icon.size == (1024, 1024)
    assert icon.getbands() == ("R", "G", "B"), "Icon must be opaque RGB"
    corners = [icon.getpixel((x, y)) for x in (0, 1023) for y in (0, 1023)]
    assert len(set(corners)) == 4, "Check icon corners for borders or masks"
    print(f"Source: {icon.format} {icon.size} {icon.mode}; corners: {corners}")

    ios = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    data = json.loads((ios / "Contents.json").read_text())
    for entry in data["images"]:
        size = round(float(entry["size"].split("x")[0]) * int(entry["scale"][0]))
        out = ios / entry["filename"]
        icon.resize((size, size), Image.Resampling.LANCZOS).save(out)
        assert Image.open(out).size == (size, size)

    android = ROOT / "android/app/src/main/res"
    for density, size in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
        out = android / f"mipmap-{density}/ic_launcher.png"
        icon.resize((size, size), Image.Resampling.LANCZOS).save(out)
        assert Image.open(out).size == (size, size)

    win = ROOT / "windows/runner/resources/app_icon.ico"
    icon.save(win, format="ICO", sizes=[(size, size) for size in (16, 24, 32, 48, 64, 128, 256)])
    with Image.open(win) as result:
        assert result.format == "ICO" and result.info["sizes"] >= {(16, 16), (256, 256)}
        print(f"Generated: {len(data['images'])} iOS, 5 Android, Windows ICO {sorted(result.info['sizes'])}")
