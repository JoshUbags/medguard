"""Download the Inter static TTFs the app uses and save them with the file
names the google_fonts package looks for in bundled assets."""

import re
import time
import urllib.request
from pathlib import Path


def fetch(url: str, headers: dict, attempts: int = 6) -> bytes:
    last_error: Exception | None = None
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(url, headers=headers)
            return urllib.request.urlopen(req, timeout=60).read()
        except Exception as e:  # noqa: BLE001 - retry any transient failure
            last_error = e
            time.sleep(2 * (attempt + 1))
    raise last_error

CSS_URL = (
    "https://fonts.googleapis.com/css2?family=Inter:ital,wght@"
    "0,400;0,500;0,600;0,700;0,800;1,500;1,600&display=swap"
)
# A legacy UA makes the API return plain TTF urls without unicode-range splits.
HEADERS = {"User-Agent": "curl/7.64"}

NAMES = {
    ("normal", "400"): "Inter-Regular.ttf",
    ("normal", "500"): "Inter-Medium.ttf",
    ("normal", "600"): "Inter-SemiBold.ttf",
    ("normal", "700"): "Inter-Bold.ttf",
    ("normal", "800"): "Inter-ExtraBold.ttf",
    ("italic", "500"): "Inter-MediumItalic.ttf",
    ("italic", "600"): "Inter-SemiBoldItalic.ttf",
}

out_dir = Path(__file__).resolve().parent.parent / "google_fonts"
out_dir.mkdir(parents=True, exist_ok=True)

css = fetch(CSS_URL, HEADERS).decode("utf-8")

faces = re.findall(
    r"@font-face\s*\{(.*?)\}", css, flags=re.DOTALL
)
saved = []
for face in faces:
    style = re.search(r"font-style:\s*(\w+)", face).group(1)
    weight = re.search(r"font-weight:\s*(\d+)", face).group(1)
    url = re.search(r"url\((https://[^)]+\.ttf)\)", face)
    if url is None:
        continue
    name = NAMES.get((style, weight))
    if name is None:
        continue
    data = fetch(url.group(1), HEADERS)
    (out_dir / name).write_bytes(data)
    saved.append(f"{name}: {len(data)} bytes")

print("\n".join(saved))
print(f"saved {len(saved)} files to {out_dir}")
