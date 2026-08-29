#!/usr/bin/env python3
# regenerates ../previews/balatro.png - a frame of the balatro animation rendered two
# ways: exact truecolor (left) and the linux VT's 16-color approximation of
# the same dithered cells (right), which is what the greeter actually shows.
# stdlib only. shader math mirrors src/animations/Balatro.zig from the patch,
# which itself mirrors https://www.shadertoy.com/view/XXtBRr by localthunk.
import math
import struct
import zlib

SPIN_ROTATION = -2.0
SPIN_SPEED = 7.0
CONTRAST = 3.5
LIGHTING = 0.4
SPIN_AMOUNT = 0.25
PIXEL_FILTER = 745.0
SPIN_EASE = 1.0
CM = 0.25 * CONTRAST + 0.5 * SPIN_AMOUNT + 1.2
PALETTE_LEN = 48

# defaults from the patch (balatro_col1/2/3)
COL1 = (222, 68, 59)     # 0x00DE443B
COL2 = (0, 85, 180)      # 0x000055B4
COL3 = (0, 0, 0)         # 0x20000000 (termbox true black)
WHITE = (255, 255, 255)

VGA = [
    (0, 0, 0), (0, 0, 170), (0, 170, 0), (0, 170, 170),
    (170, 0, 0), (170, 0, 170), (170, 85, 0), (170, 170, 170),
    (85, 85, 85), (85, 85, 255), (85, 255, 85), (85, 255, 255),
    (255, 85, 85), (255, 85, 255), (255, 255, 85), (255, 255, 255),
]


def paint_res_at(x, y, w_cells, h_cells, t):
    wpx, hpx = float(w_cells), float(h_cells * 2)
    slen = math.hypot(wpx, hpx)
    ps = slen / PIXEL_FILTER
    px, py = x + 0.5, 2.0 * y + 1.0
    ux = (math.floor(px / ps) * ps - 0.5 * wpx) / slen
    uy = (math.floor(py / ps) * ps - 0.5 * hpx) / slen
    ul = math.hypot(ux, uy)
    rot = SPIN_ROTATION * SPIN_EASE * 0.2 + 302.2
    ang = math.atan2(uy, ux) + rot - SPIN_EASE * 20.0 * (SPIN_AMOUNT * ul + (1.0 - SPIN_AMOUNT))
    ux, uy = ul * math.cos(ang) * 30.0, ul * math.sin(ang) * 30.0
    sp = t * SPIN_SPEED
    u2x = u2y = ux + uy
    for _ in range(5):
        m = math.sin(max(ux, uy))
        u2x += m + ux
        u2y += m + uy
        ux += 0.5 * math.cos(5.1123314 + 0.353 * u2y + sp * 0.131121)
        uy += 0.5 * math.sin(u2x - 0.113 * sp)
        s = math.cos(ux + uy) - math.sin(ux * 0.711 - uy)
        ux -= s
        uy -= s
    return min(2.0, max(0.0, math.hypot(ux, uy) * 0.035 * CM))


def shader_color(pr):
    c1p = max(0.0, 1.0 - CM * abs(1.0 - pr))
    c2p = max(0.0, 1.0 - CM * abs(pr))
    c3p = 1.0 - min(1.0, c1p + c2p)
    light = (LIGHTING - 0.2) * max(c1p * 5.0 - 4.0, 0.0) + LIGHTING * max(c2p * 5.0 - 4.0, 0.0)
    base = 0.3 / CONTRAST
    cols = (COL1, COL2, COL3)
    return tuple(
        min(1.0, max(0.0, base * COL1[c] / 255 + (1.0 - base)
                    * sum(col[c] / 255 * p for col, p in zip(cols, (c1p, c2p, c3p))) + light))
        for c in range(3)
    )


def vt_fg(c):
    r, g, b = c
    mx = max(r, g, b)
    hue = (4 if r > mx / 2 else 0) | (2 if g > mx / 2 else 0) | (1 if b > mx / 2 else 0)
    if hue == 7 and mx <= 0x55:
        return VGA[8]
    return VGA[hue + (8 if mx > 0xAA else 0)]


def vt_bg(c):
    r, g, b = c
    return VGA[(4 if r & 0x80 else 0) | (2 if g & 0x80 else 0) | (1 if b & 0x80 else 0)]


def build_palette():
    pal = []
    for i in range(PALETTE_LEN):
        tgt = shader_color((i + 0.5) * 2.0 / PALETTE_LEN)
        best = None
        for fg in (COL1, COL2, COL3, WHITE):
            for bg in (COL1, COL2, COL3):
                for cov in (0.25, 0.5, 0.75, 1.0):
                    mixed = tuple((fg[c] / 255) * cov + (bg[c] / 255) * (1 - cov) for c in range(3))
                    d = sum(w * (mixed[c] - tgt[c]) ** 2 for c, w in enumerate((0.3, 0.59, 0.11)))
                    if best is None or d < best[0]:
                        best = (d, fg, bg, cov)
        pal.append(best[1:])
    return pal


def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 6)))
        f.write(chunk(b"IEND", b""))


def main():
    W, H, CW, CH, T = 120, 40, 6, 12, 5.0
    pal = build_palette()
    cells = [[pal[min(PALETTE_LEN - 1, int(paint_res_at(x, y, W, H, T) * PALETTE_LEN / 2.0))]
              for x in range(W)] for y in range(H)]

    rows = []
    for y in range(H):
        for _ in range(CH):
            line = []
            for x in range(W):  # truecolor: optical blend of fg over bg
                fg, bg, cov = cells[y][x]
                line.extend(tuple(int(fg[c] * cov + bg[c] * (1 - cov)) for c in range(3)) * CW)
            line.extend((60, 60, 60) * 8)
            for x in range(W):  # VT: kernel-quantized fg/bg, same blend
                fg, bg, cov = cells[y][x]
                qfg, qbg = vt_fg(fg), vt_bg(bg)
                line.extend(tuple(int(qfg[c] * cov + qbg[c] * (1 - cov)) for c in range(3)) * CW)
            rows.append(line)

    out = __file__.rsplit("/", 2)[0] + "/previews/balatro.png"
    write_png(out, W * CW * 2 + 8, H * CH, rows)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
