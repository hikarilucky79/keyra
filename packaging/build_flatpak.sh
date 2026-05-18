#!/bin/bash
# Helper script to build and run Keyra Flatpak locally
# Desenvolvido por Antigravity para Hikari

set -e

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGING_DIR="$WORKSPACE_DIR/packaging"

# Colors for terminal output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== [Flatpak] Iniciando Empacotamento Local ===${NC}"

# 1. Check for flatpak-builder
if ! command -v flatpak-builder &> /dev/null; then
    echo -e "${RED}Erro: 'flatpak-builder' não está instalado.${NC}"
    echo -e "Instale-o usando o gerenciador de pacotes do seu sistema."
    echo -e "Exemplo (Debian/Ubuntu): ${YELLOW}sudo apt install flatpak-builder flatpak${NC}"
    exit 1
fi

# 2. Build Flutter release bundle if it doesn't exist
FLUTTER_BUNDLE="$WORKSPACE_DIR/keyra-flutter/build/linux/x64/release/bundle"
if [ ! -d "$FLUTTER_BUNDLE" ]; then
    echo -e "\n${BLUE}-> Compilando keyra-flutter em release mode...${NC}"
    cd "$WORKSPACE_DIR/keyra-flutter"
    flutter build linux --release
else
    echo -e "\n${GREEN}✓ Flutter Linux bundle encontrado, pulando compilação frontend.${NC}"
fi

# 3. Compile and Install local Flatpak
echo -e "\n${BLUE}-> Compilando e instalando Flatpak localmente (modo --user)...${NC}"
cd "$WORKSPACE_DIR"

# Ensure the official GNOME SDK runtime 46 is present
if ! flatpak list | grep -q "org.gnome.Platform//46"; then
    echo -e "${YELLOW}Aviso: Runtime org.gnome.Platform//46 não encontrado. Baixando da Flathub...${NC}"
    flatpak install -y flathub org.gnome.Platform//46 org.gnome.Sdk//46 org.freedesktop.Sdk.Extension.rust-stable//23.08 || true
fi

# Compile the manifest and install locally
flatpak-builder --force-clean --user --install "$PACKAGING_DIR/flatpak_build" "$PACKAGING_DIR/io.github.hikarilucky79.keyra.yml"

echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN}✓ Flatpak compilado e instalado com sucesso!${NC}"
echo -e "${GREEN}==================================================${NC}"
echo -e "Para executar o aplicativo no sandbox Flatpak, use:"
echo -e "  ${BLUE}flatpak run io.github.hikarilucky79.keyra${NC}\n"
