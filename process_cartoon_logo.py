import os
from PIL import Image, ImageDraw

# Caminho da imagem gerada pelo Gemini
generated_image_path = "/home/hikari/.gemini/antigravity/brain/16832806-9b7b-4146-b276-0147e5861399/keyra_cartoon_logo_1779039666466.png"
workspace_dir = "/home/hikari/Projetos/keyra"

print("=== Processando Novo Logotipo Cartoon do Keyra ===")
print(f"Carregando imagem: {generated_image_path}")

if not os.path.exists(generated_image_path):
    print(f"Erro: Imagem não encontrada em {generated_image_path}!")
    exit(1)

img = Image.open(generated_image_path).convert("RGBA")
width, height = img.size
pixels = img.load()

# Detectar as bordas dos elementos cartoon (excluindo fundo preto absoluto das bordas extremas)
left = width
right = 0
top = height
bottom = 0

print("1. Calculando limites do ícone...")
for y in range(height):
    for x in range(width):
        r, g, b, a = pixels[x, y]
        # Detectar pixels que não são o preto profundo do fundo (RGB > 12)
        if r > 12 or g > 12 or b > 12:
            if x < left: left = x
            if x > right: right = x
            if y < top: top = y
            if y > bottom: bottom = y

# Adicionar uma margem de segurança de 15 pixels para não cortar as pontas dos sparkles/ondas
padding = 15
left = max(0, left - padding)
right = min(width - 1, right + padding)
top = max(0, top - padding)
bottom = min(height - 1, bottom + padding)

c_w = right - left + 1
c_h = bottom - top + 1
print(f"Bordas detectadas com padding: esquerda={left}, direita={right}, topo={top}, base={bottom} (Tamanho: {c_w}x{c_h})")

# Para garantir um quadrado perfeito e centralizado
max_dim = max(c_w, c_h)
center_x = (left + right) // 2
center_y = (top + bottom) // 2

left = max(0, center_x - max_dim // 2)
right = min(width - 1, center_x + max_dim // 2)
top = max(0, center_y - max_dim // 2)
bottom = min(height - 1, center_y + max_dim // 2)

cropped = img.crop((left, top, right + 1, bottom + 1))
c_w, c_h = cropped.size
print(f"Cortado para quadrado perfeito: {c_w}x{c_h}")

# Aplicar máscara de cantos arredondados macOS squircle style (18%)
print("2. Aplicando máscara de transparência (macOS Squircle style)...")
mask = Image.new('L', (c_w, c_h), 0)
draw = ImageDraw.Draw(mask)
radius = int(c_w * 0.18)  # 18% para o padrão oficial squircle
draw.rounded_rectangle([0, 0, c_w, c_h], radius, fill=255)

cropped.putalpha(mask)

# Destinos dos assets
paths = [
    os.path.join(workspace_dir, 'app_logo.png'),
    os.path.join(workspace_dir, 'public/favicon.png'),
    os.path.join(workspace_dir, 'public/apple-touch-icon.png'),
    os.path.join(workspace_dir, 'public/android-chrome-192x192.png'),
    os.path.join(workspace_dir, 'public/android-chrome-512x512.png'),
    os.path.join(workspace_dir, 'public/favicon-32x32.png'),
    os.path.join(workspace_dir, 'public/favicon-16x16.png'),
    os.path.join(workspace_dir, 'keyra-flutter/assets/icons/app_icon.png')
]

print("3. Salvando e redimensionando os assets...")
for p in paths:
    dir_name = os.path.dirname(p)
    if dir_name and not os.path.exists(dir_name):
        os.makedirs(dir_name, exist_ok=True)
        
    if '16x16' in p:
        resized = cropped.resize((16, 16), Image.Resampling.LANCZOS)
        resized.save(p, 'PNG')
    elif '32x32' in p:
        resized = cropped.resize((32, 32), Image.Resampling.LANCZOS)
        resized.save(p, 'PNG')
    elif '192x192' in p:
        resized = cropped.resize((192, 192), Image.Resampling.LANCZOS)
        resized.save(p, 'PNG')
    else:
        resized = cropped.resize((512, 512), Image.Resampling.LANCZOS)
        resized.save(p, 'PNG')
    print(f"   -> Salvo com sucesso: {p}")

print("\n=== CONCLUÍDO COM SUCESSO! Logotipo cartoon aplicado em todo o projeto! ===")
