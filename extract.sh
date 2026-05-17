#!/bin/bash
# Copiar a logo transparente arredondada (removendo a parte preta) para todos os assets
SRC="/home/hikari/.gemini/antigravity/brain/e8432724-8e74-4038-b46d-45da7509cc60/transparent_favicon_1778992545826.png"

echo "-> Copiando logo transparente para app_logo.png..."
cp "$SRC" "/home/hikari/Projetos/keyra/app_logo.png"

echo "-> Copiando para public/favicon.png e formatos secundários..."
cp "$SRC" "/home/hikari/Projetos/keyra/public/favicon.png"
cp "$SRC" "/home/hikari/Projetos/keyra/public/apple-touch-icon.png"
cp "$SRC" "/home/hikari/Projetos/keyra/public/android-chrome-192x192.png"
cp "$SRC" "/home/hikari/Projetos/keyra/public/android-chrome-512x512.png"
cp "$SRC" "/home/hikari/Projetos/keyra/public/favicon-32x32.png"
cp "$SRC" "/home/hikari/Projetos/keyra/public/favicon-16x16.png"

echo "-> Copiando para assets do Flutter..."
cp "$SRC" "/home/hikari/Projetos/keyra/keyra-flutter/assets/icons/app_icon.png"

echo "-> Atualizando index do Git..."
git update-index --really-refresh || true

echo "=== Concluído com Sucesso! ==="
