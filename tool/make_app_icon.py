"""Draws the Returner app icon and writes it for every platform.

A white return arrow — an arc that comes back round and ends in an arrowhead —
on the design system's night background (#0c0c0d). Drawn with strokes and
round caps, like the system's interface icons.

    python tool/make_app_icon.py

Needs Pillow. Outputs:
    windows/runner/resources/app_icon.ico
    macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_<size>.png
    installer/app_icon.png   (512px preview)
"""
import math
import os

from PIL import Image, ImageDraw

BACKGROUND = (12, 12, 13, 255)   # page, night theme
MARK = (235, 235, 232, 255)      # ink, night theme
SCALE = 4                        # supersampling


def draw(size: int, margin: float, corner: float) -> Image.Image:
    """Renders one icon. `margin` and `corner` are fractions of the size."""
    s = size * SCALE
    image = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(image)

    # Rounded tile.
    m = margin * s
    d.rounded_rectangle((m, m, s - m, s - m), radius=corner * s, fill=BACKGROUND)

    tile = s - 2 * m
    # Nudged right: the arrowhead hangs out to the left of the arc.
    cx, cy = s / 2 + tile * 0.05, s / 2 + tile * 0.02
    radius = tile * 0.25
    stroke = max(SCALE, tile * 0.085)

    # The arc: from the lower right, up over the top, round to the left —
    # three quarters of a circle that "comes back".
    start, end = 180, 60  # PIL angles: clockwise, 0° at 3 o'clock
    box = (cx - radius, cy - radius, cx + radius, cy + radius)
    d.arc(box, start=start, end=end, fill=MARK, width=round(stroke))

    def point(angle_deg: float, r: float = radius):
        a = math.radians(angle_deg)
        return cx + r * math.cos(a), cy + r * math.sin(a)

    def dot(p):
        h = stroke / 2
        d.ellipse((p[0] - h, p[1] - h, p[0] + h, p[1] + h), fill=MARK)

    # Round caps: PIL draws arcs with butt ends, centred on the stroke.
    mid = radius - stroke / 2
    tail = point(end, mid)
    tip = point(start, mid)
    dot(tail)

    # Arrowhead at the left end, pointing down — the direction the arc is
    # travelling there. An open chevron, same stroke as the arc.
    arm = tile * 0.15
    head_tip = (tip[0], tip[1] + stroke * 0.55)
    for dx in (-1, 1):
        wing = (head_tip[0] + dx * arm * 0.78, head_tip[1] - arm * 0.78)
        d.line((wing, head_tip), fill=MARK, width=round(stroke))
        dot(wing)
    dot(head_tip)

    return image.resize((size, size), Image.LANCZOS)


def main() -> None:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    # Windows: the tile fills the canvas; small sizes get less rounding.
    ico_sizes = [16, 24, 32, 48, 64, 128, 256]
    frames = [draw(n, margin=0.0, corner=0.22) for n in ico_sizes]
    ico = os.path.join(root, "windows", "runner", "resources", "app_icon.ico")
    frames[-1].save(ico, format="ICO", sizes=[(n, n) for n in ico_sizes],
                    append_images=frames[:-1])

    # macOS: the icon grid leaves a transparent margin around the tile.
    mac = os.path.join(root, "macos", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    for n in [16, 32, 64, 128, 256, 512, 1024]:
        draw(n, margin=0.098, corner=0.18).save(os.path.join(mac, f"app_icon_{n}.png"))

    draw(512, margin=0.0, corner=0.22).save(os.path.join(root, "installer", "app_icon.png"))
    print("icons written")


if __name__ == "__main__":
    main()
