# -*- coding: utf-8 -*-
import textwrap

from PIL import Image, ImageDraw, ImageFont

W, H = 900, 1500
BG = (238, 238, 238)
WHITE = (255, 255, 255)
DARK = (30, 30, 30)
GRAY = (120, 120, 120)
BLUE = (0, 122, 255)
LIGHT_BLUE_BAR = (230, 240, 255)

# Разные цвета под разные пункты — легче найти нужный в легенде
C_GREEN = (30, 150, 90)      # 1 подключение
C_PURPLE = (150, 80, 200)    # 2 название/дата подписки
C_ORANGE = (230, 140, 20)    # 3 обновить список
C_RED = (220, 60, 60)        # 4 пинг (недоступность = тревога)
C_TEAL = (20, 150, 150)      # 5 трафик
C_INDIGO = (70, 70, 200)     # 6 профили

img = Image.new('RGB', (W, H), BG)
d = ImageDraw.Draw(img)


def font(size, bold=False):
    names = ['arialbd.ttf', 'segoeuib.ttf'] if bold else ['arial.ttf', 'segoeui.ttf']
    for n in names:
        try:
            return ImageFont.truetype(n, size)
        except Exception:
            continue
    return ImageFont.load_default()


f_h = font(24, True)
f_b = font(20)
f_s = font(17)
f_num = font(22, True)

# ── Верхняя панель: настройки (шестерёнка) и добавить профиль (+) ────────
gear_x, gear_y = 48, 48
d.ellipse([gear_x - 18, gear_y - 18, gear_x + 18, gear_y + 18], outline=DARK, width=3)
d.ellipse([gear_x - 5, gear_y - 5, gear_x + 5, gear_y + 5], outline=DARK, width=2)
for ang in range(0, 360, 45):
    import math
    rad = math.radians(ang)
    x1, y1 = gear_x + 18 * math.cos(rad), gear_y + 18 * math.sin(rad)
    x2, y2 = gear_x + 25 * math.cos(rad), gear_y + 25 * math.sin(rad)
    d.line([x1, y1, x2, y2], fill=DARK, width=3)

plus_x, plus_y = W - 48, 48
d.text((plus_x - 15, plus_y - 22), '+', font=font(44, True), fill=DARK)

cx, cy, r = W // 2, 260, 130
d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(210, 210, 210), width=6)
d.ellipse([cx - r + 20, cy - r + 20, cx + r - 20, cy + r - 20], fill=WHITE, outline=(220, 220, 220), width=2)
d.line([cx, cy - 30, cx, cy + 5], fill=DARK, width=6)
d.arc([cx - 25, cy - 25, cx + 25, cy + 30], start=-60, end=240, fill=DARK, width=6)
d.text((W - 220, cy + r + 20), 'Скрыть все', font=f_s, fill=GRAY)

card_top = 470
d.rounded_rectangle([20, card_top, W - 20, H - 20], radius=24, fill=WHITE)

row_y = card_top + 30
d.text((50, row_y), 'v', font=f_h, fill=DARK)
d.text((90, row_y), 'Моя подписка: 27 д.', font=f_h, fill=DARK)
d.text((90, row_y + 34), 'Действует до: 24.08.2026', font=f_s, fill=GRAY)

icon_y = row_y + 6
d.ellipse([W - 220, icon_y, W - 220 + 34, icon_y + 34], outline=BLUE, width=3)
d.arc([W - 220 + 5, icon_y + 5, W - 220 + 29, icon_y + 29], start=30, end=300, fill=BLUE, width=3)
d.ellipse([W - 160, icon_y, W - 160 + 34, icon_y + 34], outline=(60, 60, 60), width=3)
d.line([W - 160 + 17, icon_y + 8, W - 160 + 17, icon_y + 17], fill=(60, 60, 60), width=3)
d.text((W - 100, icon_y - 2), '...', font=f_h, fill=GRAY)

traf_y = row_y + 80
d.rounded_rectangle([50, traf_y, W - 50, traf_y + 44], radius=22, outline=(210, 210, 210), width=2, fill=(250, 250, 250))
d.ellipse([65, traf_y + 12, 85, traf_y + 32], outline=GRAY, width=2)
d.text((72, traf_y + 13), 'i', font=f_s, fill=GRAY)
d.text((W // 2 - 60, traf_y + 10), '385,0MB/∞', font=f_b, fill=DARK)

status_y = traf_y + 60
d.rounded_rectangle([50, status_y, W - 50, status_y + 40], radius=8, fill=LIGHT_BLUE_BAR)
d.text((W // 2 - 150, status_y + 8), 'ПОДКЛЮЧЕНИЕ ЗАЩИЩЕНО', font=f_s, fill=BLUE)

servers = [
    ('Auto', 'Auto ДЛЯ ДОМАШНЕГО ИНТЕРНЕТА', 'VLESS / TCP / REALITY / JSON', False),
    ('Auto', 'Auto ДЛЯ МОБИЛЬНОГО ИНТЕРНЕТА', 'VLESS / TCP / REALITY / JSON', False),
    ('FI', 'Finland', 'VLESS / TCP / REALITY / JSON', False),
    ('SE', 'Sweden', 'VLESS / TCP / REALITY / JSON', False),
    ('RU', 'Moscow', 'VLESS / TCP / REALITY / JSON', True),
]
list_y = status_y + 70
row_h = 90
for i, (emoji, name, sub, selected) in enumerate(servers):
    y = list_y + i * row_h
    if i > 0:
        d.line([50, y, W - 50, y], fill=(230, 230, 230), width=1)
    if selected:
        d.rectangle([20, y, 26, y + row_h], fill=BLUE)
    d.rounded_rectangle([55, y + 18, 100, y + 63], radius=10, fill=(235, 235, 235))
    d.text((64, y + 25), emoji, font=f_s, fill=DARK)
    d.text((115, y + 18), name, font=f_b, fill=DARK)
    d.text((115, y + 48), sub, font=f_s, fill=GRAY)
    d.text((W - 60, y + 30), '>', font=f_h, fill=GRAY)

# ── Выноски (номер + свой цвет на каждый пункт) ──────────────────────────
# Панель (настройки/добавить профиль) визуально на скрине есть, но без
# выносок — это стандартные иконки приложения, не специфичные для VPN.
callouts = [
    (cx, cy, '1', C_GREEN),
    (35, row_y - 22, '2', C_PURPLE),
    (W - 143, icon_y + 17, '3', C_ORANGE),
    (W - 203, icon_y + 17, '4', C_RED),
    (W // 2 - 82, traf_y + 22, '5', C_TEAL),
    (77, list_y + 40, '6', C_INDIGO),
]
for x, y, num, color in callouts:
    d.ellipse([x - 18, y - 18, x + 18, y + 18], fill=color)
    bbox = d.textbbox((0, 0), num, font=f_num)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    d.text((x - tw / 2, y - th / 2 - 4), num, font=f_num, fill=WHITE)

# ── Легенда ───────────────────────────────────────────────────────────────
legend = [
    ('1', C_GREEN, 'Подключить / отключить VPN'),
    ('2', C_PURPLE, 'Название подписки и дата, до которой она действует'),
    ('3', C_ORANGE, 'Обновить список серверов'),
    ('4', C_RED, 'Пинг — скорость и доступность сервера («Н/Д» = сервер недоступен)'),
    ('5', C_TEAL, 'Использовано трафика / доступно (∞ = безлимит)'),
    ('6', C_INDIGO, 'Профили: Auto подбирает сервер автоматически, остальные — ручной выбор локации'),
]

WRAP_WIDTH = 58
line_h = 26
rows = []
for num, color, text in legend:
    wrapped = textwrap.wrap(text, WRAP_WIDTH) or ['']
    rows.append((num, color, wrapped))

legend_img_h = 50 + sum(len(w) for _, _, w in rows) * line_h + len(rows) * 14
legend_canvas = Image.new('RGB', (W, legend_img_h), WHITE)
ld = ImageDraw.Draw(legend_canvas)
ld.text((30, 10), 'Обозначения', font=f_h, fill=DARK)

y = 55
for num, color, wrapped in rows:
    ld.ellipse([30, y, 60, y + 30], fill=color)
    bbox = ld.textbbox((0, 0), num, font=f_b)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    ld.text((45 - tw / 2, y + 15 - th / 2 - 2), num, font=f_b, fill=WHITE)
    for j, line in enumerate(wrapped):
        ld.text((75, y + 3 + j * line_h), line, font=f_s, fill=DARK)
    y += len(wrapped) * line_h + 14

final = Image.new('RGB', (W, H + legend_img_h + 20), BG)
final.paste(img, (0, 0))
final.paste(legend_canvas, (0, H + 20))

import sys
out_path = sys.argv[1] if len(sys.argv) > 1 else 'happ_guide_screenshot.png'
final.save(out_path)
print('Saved:', out_path, final.size)
