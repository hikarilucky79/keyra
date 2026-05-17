import os
from PIL import Image

workspace_dir = "/home/hikari/Projetos/keyra"
new_logo_path = os.path.join(workspace_dir, "app_logo.png")

print("=== Iniciando Atualização de Ícones ICO e Tray ===")

if not os.path.exists(new_logo_path):
    print(f"Erro: O logotipo processado {new_logo_path} não existe!")
    exit(1)

# Carregar o novo logotipo processado (512x512)
logo_img = Image.open(new_logo_path).convert("RGBA")

# 1. Atualizar o tray_icon.png preservando as dimensões exatas do original
tray_path = os.path.join(workspace_dir, "keyra-flutter/assets/icons/tray_icon.png")
if os.path.exists(tray_path):
    original_tray = Image.open(tray_path)
    tray_size = original_tray.size
    print(f"Detectada dimensão original do tray_icon: {tray_size[0]}x{tray_size[1]}")
    # Redimensionar com alta qualidade Lanczos
    new_tray = logo_img.resize(tray_size, Image.Resampling.LANCZOS)
    new_tray.save(tray_path, "PNG")
    print(f"   -> tray_icon.png atualizado com sucesso!")
else:
    # Se não existir por algum motivo, salvar como 32x32 (padrão)
    new_tray = logo_img.resize((32, 32), Image.Resampling.LANCZOS)
    new_tray.save(tray_path, "PNG")
    print(f"   -> tray_icon.png criado (32x32)!")

# 2. Gerar os arquivos .ico (contendo múltiplos tamanhos para compatibilidade máxima)
ico_sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]

ico_paths = [
    os.path.join(workspace_dir, "public/favicon.ico"),
    os.path.join(workspace_dir, "keyra-flutter/assets/icons/favicon.ico"),
    os.path.join(workspace_dir, "keyra-flutter/windows/runner/resources/app_icon.ico")
]

for p in ico_paths:
    dir_name = os.path.dirname(p)
    if dir_name and not os.path.exists(dir_name):
        os.makedirs(dir_name, exist_ok=True)
        
    print(f"Convertendo e salvando .ico em: {p}")
    logo_img.save(p, format="ICO", sizes=ico_sizes)
    print(f"   -> {os.path.basename(p)} atualizado com sucesso!")

print("\n=== SUCESSO! Todos os arquivos .ico e o ícone de bandeja foram atualizados! ===")
