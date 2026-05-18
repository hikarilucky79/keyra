#!/bin/bash
set -e

# Cores para o terminal
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # Sem cor

echo -e "${BLUE}=== [Automação] Iniciando Publicação Automática no GitHub ===${NC}\n"

# 1. Adicionar todos os arquivos modificados e novos
echo -e "-> Staging de arquivos no Git..."
git add .

# 2. Fazer o commit
echo -e "-> Criando commit..."
git commit -m "feat: complete multiplatform packaging, desktop launcher integration, and automated AUR pipeline" || echo -e "${YELLOW}Sem novas alterações para commitar.${NC}"

# 3. Remover a tag antiga localmente e remotamente (para evitar conflitos de tag duplicada)
echo -e "-> Removendo tag 'v0.1.0' antiga (local e remota)..."
git tag -d v0.1.0 2>/dev/null || true
git push origin :refs/tags/v0.1.0 2>/dev/null || true

# 4. Criar a nova tag de versão v0.1.0
echo -e "-> Criando nova tag 'v0.1.0'..."
git tag -a v0.1.0 -m "Release v0.1.0"

# 5. Fazer o push das alterações e da tag para o GitHub
echo -e "-> Enviando commits e tags para o repositório GitHub..."
git push origin main --tags

echo -e "\n${GREEN}✓ Tudo pronto! As alterações foram enviadas e a tag v0.1.0 foi recriada.${NC}"
echo -e "${BLUE}A pipeline do GitHub Actions foi iniciada com sucesso na nuvem!${NC}\n"
