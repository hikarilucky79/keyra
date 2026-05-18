#!/bin/bash
# Script de empacotamento do Keyra para Arch Linux (PKGBUILD)
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

echo -e "${BLUE}=== [Arch Linux] Iniciando Empacotamento via PKGBUILD ===${NC}"

# 1. Check for makepkg
if ! command -v makepkg &> /dev/null; then
    echo -e "${RED}Erro: 'makepkg' não está instalado.${NC}"
    echo -e "Este script só pode ser executado em sistemas Arch Linux ou baseados nele (como Manjaro, EndeavourOS)."
    exit 1
fi

# 2. Clean previous build artifacts
echo -e "\n${BLUE}-> Limpando compilações anteriores...${NC}"
cd "$PACKAGING_DIR"
rm -f keyra-git-*.pkg.tar.zst
rm -rf src/ pkg/ cargo-home/

# 3. Build via makepkg
echo -e "\n${BLUE}-> Executando 'makepkg' para compilar e empacotar...${NC}"
makepkg -c -s --noconfirm

  # Show final package location
  echo -e "\n${GREEN}==================================================${NC}"
  echo -e "${GREEN}✓ Pacote Arch Linux compilado com sucesso!${NC}"
  echo -e "${GREEN}==================================================${NC}"
  echo -e "Arquivo gerado em packaging/:"
  ls -lh "$PACKAGING_DIR"/keyra-git-*.pkg.tar.zst
  echo -e "\nPronto para instalar:"
  echo -e "  ${BLUE}sudo pacman -U packaging/keyra-git-*.pkg.tar.zst${NC}\n"
