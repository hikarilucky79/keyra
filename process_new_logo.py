import os
from PIL import Image, ImageDraw

# Caminho da imagem gerada pelo Gemini
generated_image_path = "/home/hikari/.gemini/antigravity/brain/16832806-9b7b-4146-b276-0147e5861399/keyra_logo_concept_1779039096160.png"
workspace_dir = "/home/hikari/Projetos/keyra"

print("=== Processando Novo Logotipo do Keyra ===")
print(f"Carregando imagem: {generated_image_path}")

if not os.path.exists(generated_image_path):
    print(f"Erro: Imagem não encontrada em {generated_image_path}!")
    exit(1)

img = Image.open(generated_image_path).convert("RGBA")
width, height = img.size
pixels = img.load()

# Detectar as bordas do squircle (excluindo fundo preto sólido de fora)
left = width
right = 0
top = height
bottom = 0

print("1. Calculando bordas do ícone...")
for y in range(height):
    for x in range(width):
        r, g, b, a = pixels[x, y]
        # Se o pixel não for preto sólido (RGB > 12)
        if r > 12 or g > 12 or b > 12:
            if x < left: left = x
            if x > right: right = x
            if y < top: top = y
            if y > bottom: bottom = y

# Adicionar uma margem de segurança pequena ou ajustar limites para obter um quadrado perfeito
c_w = right - left + 1
c_h = bottom - top + 1
print(f"Bordas detectadas: esquerda={left}, direita={right}, topo={top}, base={bottom} (Tamanho: {c_w}x{c_h})")

# Para garantir que o ícone fique quadrado, pegamos a maior dimensão e centralizamos
max_dim = max(c_w, c_h)
center_x = (left + right) // 2
center_y = (top + bottom) // 2

# Recalcular as coordenadas para quadrado perfeito
left = max(0, center_x - max_dim // 2)
right = min(width - 1, center_x + max_dim // 2)
top = max(0, center_y - max_dim // 2)
bottom = min(height - 1, center_y + max_dim // 2)

cropped = img.crop((left, top, right + 1, bottom + 1))
c_w, c_h = cropped.size
print(f"Cortado para quadrado perfeito: {c_w}x{c_h}")

# Criar a máscara de cantos arredondados super suave (macOS style: 18% do tamanho)
print("2. Aplicando máscara de transparência (macOS Squircle style)...")
mask = Image.new('L', (c_w, c_h), 0)
draw = ImageDraw.Draw(mask)
radius = int(c_w * 0.18)  # 18% do tamanho é o padrão macOS
draw.rounded_rectangle([0, 0, c_w, c_h], radius, fill=255)

cropped.putalpha(mask)

# Caminhos de destino
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

print("3. Salvando e redimensionando nos diretórios do projeto...")
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

print("\n=== CONCLUÍDO! Todos os logotipos foram atualizados com o novo design! ===")
