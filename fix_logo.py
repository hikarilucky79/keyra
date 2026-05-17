import zipfile
import os
from PIL import Image, ImageDraw

print("=== Iniciando Correção de Transparência do Logotipo ===")

# 1. Extrair os arquivos originais do favicon.zip para uma pasta temporária
print("1. Extraindo original de favicon.zip...")
with zipfile.ZipFile('favicon.zip', 'r') as zip_ref:
    zip_ref.extractall('temp_original')

# 2. Localizar o favicon.png original dentro dos arquivos extraídos
original_path = None
for root, dirs, files in os.walk('temp_original'):
    for f in files:
        if f == 'favicon.png' or f.endswith('.png'):
            original_path = os.path.join(root, f)
            break

if not original_path or not os.path.exists(original_path):
    print("Erro: Não foi possível encontrar o favicon.png original dentro do zip!")
    exit(1)

print(f"   -> Imagem original encontrada: {original_path}")
img = Image.open(original_path).convert("RGBA")

# 3. Detectar a caixa delimitadora do quadrado arredondado (removendo o fundo preto sólido)
width, height = img.size
pixels = img.load()

left = width
right = 0
top = height
bottom = 0

print("2. Calculando bordas do ícone (removendo fundo preto)...")
for y in range(height):
    for x in range(width):
        r, g, b, a = pixels[x, y]
        # Se o pixel não for preto sólido (RGB > 10)
        if r > 10 or g > 10 or b > 10:
            if x < left: left = x
            if x > right: right = x
            if y < top: top = y
            if y > bottom: bottom = y

print(f"   -> Caixa delimitadora detectada: esquerda={left}, direita={right}, topo={top}, base={bottom}")

# 4. Cortar a imagem rente às bordas do ícone arredondado
cropped = img.crop((left, top, right + 1, bottom + 1))
c_w, c_h = cropped.size

# 5. Aplicar uma máscara de canto arredondado super suave e anti-aliased (macOS style)
print("3. Aplicando máscara de cantos arredondados com transparência real...")
mask = Image.new('L', (c_w, c_h), 0)
draw = ImageDraw.Draw(mask)
radius = int(c_w * 0.18)  # 18% é o padrão oficial de border-radius do macOS Big Sur/Sonoma
draw.rounded_rectangle([0, 0, c_w, c_h], radius, fill=255)

cropped.putalpha(mask)

# 6. Salvar nos diretórios corretos com redimensionamento inteligente de alta qualidade (Lanczos)
paths = [
    'app_logo.png',
    'public/favicon.png',
    'public/apple-touch-icon.png',
    'public/android-chrome-192x192.png',
    'public/android-chrome-512x512.png',
    'public/favicon-32x32.png',
    'public/favicon-16x16.png',
    'keyra-flutter/assets/icons/app_icon.png'
]

print("4. Salvando e redimensionando os assets...")
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
    print(f"   -> Salvo: {p}")

# Limpar arquivos temporários
import shutil
shutil.rmtree('temp_original', ignore_errors=True)

print("\n=== CONCLUÍDO COM SUCESSO! Todos os logotipos estão com transparência real! ===")
