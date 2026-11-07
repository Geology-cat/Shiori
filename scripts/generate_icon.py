import os
from PIL import Image, ImageDraw, ImageFilter

def generate_markdown_icon(path):
    size = 1024
    # 背景の作成（透明）
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    
    # --- 1. 背景のグラデーション (Sea-foam green to Teal) ---
    color_top = (163, 228, 215, 255)    # Sea-foam green
    color_bottom = (19, 141, 117, 255)   # Teal
    
    gradient = Image.new('RGBA', (size, size))
    draw_grad = ImageDraw.Draw(gradient)
    for y in range(size):
        r = int(color_top[0] + (color_bottom[0] - color_top[0]) * (y / size))
        g = int(color_top[1] + (color_bottom[1] - color_top[1]) * (y / size))
        b = int(color_top[2] + (color_bottom[2] - color_top[2]) * (y / size))
        draw_grad.line([(0, y), (size, y)], fill=(r, g, b, 255))
    
    # Squircle マスク
    radius = int(size * 0.22)
    padding = int(size * 0.08)
    rect_box = [padding, padding, size - padding, size - padding]
    
    mask = Image.new('L', (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(rect_box, radius=radius, fill=255)
    
    # 背景にマスクを適用して合成
    base = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    base.paste(gradient, (0, 0), mask)
    
    # --- 2. 紙の描画 (Paper layer) ---
    paper_padding = int(size * 0.22)
    paper_rect = [paper_padding, paper_padding, size - paper_padding, size - paper_padding]
    paper_mask = Image.new('L', (size, size), 0)
    paper_draw_mask = ImageDraw.Draw(paper_mask)
    paper_draw_mask.rounded_rectangle(paper_rect, radius=int(size*0.02), fill=255)
    
    paper_color = (250, 250, 250, 255)
    paper_layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    paper_draw = ImageDraw.Draw(paper_layer)
    paper_draw.rounded_rectangle(paper_rect, radius=int(size*0.02), fill=paper_color)
    
    # 紙のドロップシャドウ
    shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_rect = [paper_rect[0]+10, paper_rect[1]+10, paper_rect[2]+10, paper_rect[3]+10]
    shadow_draw.rounded_rectangle(shadow_rect, radius=int(size*0.02), fill=(0, 0, 0, 60))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=15))
    
    img.alpha_composite(base)
    img.alpha_composite(shadow)
    img.alpha_composite(paper_layer)
    
    # --- 3. Markdown記号 (Abstract Markdown Lines) ---
    draw = ImageDraw.Draw(img)
    line_color = (80, 80, 80, 255)
    accent_color = (19, 141, 117, 255)
    
    start_x = paper_padding + int(size * 0.08)
    curr_y = paper_padding + int(size * 0.1)
    line_width = int(size * 0.015)
    
    # Heading (# Heading)
    draw.rectangle([start_x, curr_y, start_x + int(size * 0.05), curr_y + line_width], fill=accent_color)
    draw.rectangle([start_x + int(size * 0.07), curr_y, start_x + int(size * 0.4), curr_y + line_width], fill=line_color)
    
    curr_y += int(size * 0.08)
    # Text lines
    for i in range(3):
        w = int(size * 0.45) if i < 2 else int(size * 0.3)
        draw.rectangle([start_x, curr_y, start_x + w, curr_y + int(size * 0.01)], fill=(150, 150, 150, 255))
        curr_y += int(size * 0.04)
        
    curr_y += int(size * 0.04)
    # List item
    draw.ellipse([start_x, curr_y, start_x + int(size * 0.015), curr_y + int(size * 0.015)], fill=accent_color)
    draw.rectangle([start_x + int(size * 0.03), curr_y + 0.005, start_x + int(size * 0.35), curr_y + int(size * 0.01)], fill=(150, 150, 150, 255))

    # --- 4. 万年筆/鉛筆のオーバーレイ (Pen/Pencil) ---
    # シンプルな万年筆のシルエットを斜めに配置
    pen_layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    pen_draw = ImageDraw.Draw(pen_layer)
    
    # 万年筆のボディ（長方形 + 先端）
    pen_start = (int(size * 0.7), int(size * 0.3))
    pen_end = (int(size * 0.4), int(size * 0.7))
    
    # ボディ
    pen_width = int(size * 0.04)
    pen_draw.line([pen_start, pen_end], fill=(50, 50, 50, 255), width=pen_width)
    
    # ペン先 (三角形)
    tip_end = (int(size * 0.38), int(size * 0.72))
    pen_draw.polygon([
        (int(size * 0.42), int(size * 0.68)),
        (int(size * 0.38), int(size * 0.72)),
        (int(size * 0.42), int(size * 0.72))
    ], fill=(200, 200, 200, 255))
    
    # ペンのシャドウ
    pen_shadow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    ps_draw = ImageDraw.Draw(pen_shadow)
    ps_draw.line([(pen_start[0]+5, pen_start[1]+5), (pen_end[0]+5, pen_end[1]+5)], fill=(0, 0, 0, 40), width=pen_width)
    pen_shadow = pen_shadow.filter(ImageFilter.GaussianBlur(radius=5))
    
    img.alpha_composite(pen_shadow)
    img.alpha_composite(pen_layer)
    
    # 保存
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)

target_path = "/Users/yamashitaujou/Desktop/アプリ作成/mdエディタ/icon_work/icon_1024.png"
generate_markdown_icon(target_path)
print(target_path)
