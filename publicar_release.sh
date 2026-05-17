#!/usr/bin/env bash

# ==========================================================
#       KEYRA MASTER PIPELINE (LOCAL BUILD & GITHUB RELEASE)
# ==========================================================
# Desenvolvido por Antigravity para Hikari

set -e

# Cores para o terminal
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
NC='\033[0m' # Sem cor

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

clear
echo -e "${MAGENTA}==========================================================${NC}"
echo -e "${MAGENTA}         KEYRA - CENTRAL DE CONTROLE DE RELEASE          ${NC}"
echo -e "${MAGENTA}==========================================================${NC}\n"

echo -e "Escolha o fluxo de trabalho desejado:\n"
echo -e "  ${BLUE}[1]${NC} 🛠️  Compilar e Empacotar Localmente (Debian & AppImage)"
echo -e "  ${BLUE}[2]${NC} 🌐 Publicar no GitHub (CI/CD na Nuvem - Recomendado)"
echo -e "  ${BLUE}[3]${NC} 🚀 Completo: Compilar Localmente + Publicar no GitHub"
echo -e "  ${BLUE}[4]${NC} ❌ Sair\n"

read -p "Selecione uma opção (1-4): " OPTION

if [ "$OPTION" == "4" ] || [ -z "$OPTION" ]; then
    echo -e "${YELLOW}Operação cancelada.${NC}"
    exit 0
fi

# Solicitar a versão da Tag se for interagir com o Git (Opções 2 e 3)
if [ "$OPTION" == "2" ] || [ "$OPTION" == "3" ]; then
    echo ""
    read -p "Digite a tag de versão desejada (ex: v0.1.0) ou Enter para o padrão [v0.1.0]: " TAG_VERSION
    TAG_VERSION=${TAG_VERSION:-v0.1.0}
    echo -e "Versão configurada: ${GREEN}${TAG_VERSION}${NC}\n"
fi

# ==========================================
# FUNÇÃO: Executa compilação e empacotamento local
# ==========================================
executar_build_local() {
    echo -e "\n${BLUE}=== [1/2] Iniciando Compilação Local ===${NC}"
    
    # Verifica se estamos em um ambiente Windows (MSYS/Git Bash/Cygwin)
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
        echo -e "${YELLOW}Detectado ambiente Windows (Git Bash). Compilando .exe nativo...${NC}"
        
        echo -e "\n${BLUE}-> Compilando keyra-daemon em Rust...${NC}"
        cd "$WORKSPACE_DIR/keyra-daemon"
        cargo build --release
        
        echo -e "\n${BLUE}-> Compilando keyra-flutter...${NC}"
        cd "$WORKSPACE_DIR/keyra-flutter"
        flutter build windows --release
        
        echo -e "\n${BLUE}-> Montando pacote portátil Windows...${NC}"
        mkdir -p "$WORKSPACE_DIR/packaging/win_release"
        cp -r "$WORKSPACE_DIR/keyra-flutter/build/windows/x64/runner/release/"* "$WORKSPACE_DIR/packaging/win_release/"
        cp "$WORKSPACE_DIR/keyra-daemon/target/release/keyra-daemon.exe" "$WORKSPACE_DIR/packaging/win_release/"
        
        cd "$WORKSPACE_DIR/packaging"
        # Tenta zipar usando PowerShell (padrão Windows) ou utilitário zip
        powershell.exe -Command "Compress-Archive -Path 'win_release/*' -DestinationPath 'Keyra-Windows-Portable.zip' -Force" &> /dev/null || zip -r Keyra-Windows-Portable.zip win_release &> /dev/null || true
        rm -rf win_release
        
        echo -e "\n${GREEN}==================================================${NC}"
        echo -e "${GREEN}✓ Versão Windows (.exe) compilada em packaging/Keyra-Windows-Portable.zip!${NC}"
        echo -e "${GREEN}==================================================${NC}"
    else
        echo -e "${YELLOW}Detectado ambiente Linux. Compilando pacotes Linux...${NC}"
        chmod +x "$WORKSPACE_DIR/packaging/build_all.sh"
        chmod +x "$WORKSPACE_DIR/packaging/build_deb.sh"
        chmod +x "$WORKSPACE_DIR/packaging/build_appimage.sh"
        
        # Exporta a versão temporária para os builds locais
        export GITHUB_REF_NAME="${TAG_VERSION:-v0.1.0}"
        
        # Executa o script mestre de empacotamento Linux
        "$WORKSPACE_DIR/packaging/build_all.sh"
    fi
}

# ==========================================
# FUNÇÃO: Copia preview e faz commit de preparação
# ==========================================
preparar_repositorio_git() {
    echo -e "\n${BLUE}=== [Preparações] Copiando preview e preparando Git ===${NC}"
    
    # Copia a imagem de preview gerada pela IA, caso exista no diretório do Gemini
    PREVIEW_SRC="/home/hikari/.gemini/antigravity/brain/00493a9a-899f-44c3-8769-81a98b6205eb/keyra_preview_1778981058525.png"
    PREVIEW_DEST="$WORKSPACE_DIR/public/keyra_preview.png"
    if [ -f "$PREVIEW_SRC" ]; then
        echo -e "Copiando imagem de preview para public/keyra_preview.png..."
        mkdir -p "$WORKSPACE_DIR/public"
        if cp "$PREVIEW_SRC" "$PREVIEW_DEST" 2>/dev/null; then
            echo -e "${GREEN}✓ Imagem de preview copiada com sucesso!${NC}"
        else
            echo -e "${YELLOW}Aviso: Não foi possível copiar a imagem de preview localmente devido a restrições de permissão do sistema na pasta do Gemini. Pulando cópia automática...${NC}"
        fi
    fi

    # Adiciona README.md, preview, logotipos, ícones e scripts alterados ao Git
    git add -A 2>/dev/null || true
    
    if ! git diff --cached --quiet; then
        echo -e "${YELLOW}Encontradas alterações de documentação/scripts. Criando commit de preparação...${NC}"
        git commit -m "docs: adiciona README.md com instruções e imagem de preview"
        echo -e "${GREEN}✓ Alterações commitadas no Git!${NC}"
    else
        echo -e "${GREEN}✓ Nenhuma alteração pendente para commitar.${NC}"
    fi
}

# ==========================================
# FUNÇÃO: Cria repo no GitHub e faz push do código e tags
# ==========================================
publicar_github() {
    echo -e "\n${BLUE}=== [GitHub] Autenticando e Configurando Repositório ===${NC}"
    
    # Verificar se o gh está instalado
    if ! command -v gh &> /dev/null; then
        echo -e "${RED}Erro: GitHub CLI ('gh') não está instalado. Por favor, instale-o.${NC}"
        exit 1
    fi

    # Verificar login do gh
    if ! gh auth status &> /dev/null; then
        echo -e "${YELLOW}Você não está autenticado no GitHub CLI.${NC}"
        echo -e "Iniciando o login interativo. Por favor, siga as instruções na tela...${NC}"
        gh auth login -h github.com -p https --web
    else
        echo -e "${GREEN}✓ Você já está autenticado no GitHub!${NC}"
    fi

    # Criar o repositório público se necessário
    if git remote | grep -q "origin"; then
        echo -e "${YELLOW}O remote 'origin' já existe. Atualizando código no GitHub...${NC}"
        git push -u origin main 2>/dev/null || git push -u origin master 2>/dev/null || true
    else
        if gh repo create keyra --public --source=. --remote=origin --push; then
            echo -e "${GREEN}✓ Repositório público criado e código enviado com sucesso!${NC}"
        else
            echo -e "${RED}Erro ao criar repositório. Verifique se o nome 'keyra' já não está em uso.${NC}"
            exit 1
        fi
    fi

    # Configurando o "About" e os "Tópicos" do repositório
    echo -e "\n${BLUE}Configurando a seção About e Tópicos no GitHub...${NC}"
    if gh repo edit \
        -d "Keyra - Premium low-latency typing sound engine & real-time mechanical keyboard visualizer (Rust + Flutter)" \
        --add-topic "rust,flutter,keyboard,sound-pack,sound-generator,low-latency,desktop,linux,windows,keycap,glassmorphism" \
        --enable-issues --enable-wiki --enable-projects=false &> /dev/null; then
        echo -e "${GREEN}✓ Seção About, Wiki, Issues e Tópicos configurados no GitHub!${NC}"
    else
        echo -e "${YELLOW}Aviso: Não foi possível editar as configurações do repositório via API (pode estar sendo provisionado).${NC}"
    fi

    # Criar e empurrar a tag de Release para disparar o CI/CD
    echo -e "\n${BLUE}Configurando tag de versão ${TAG_VERSION}...${NC}"
    if git tag -l | grep -q "${TAG_VERSION}"; then
        echo -e "${YELLOW}A tag ${TAG_VERSION} já existe. Recriando-a local e remotamente para aplicar as novas correções...${NC}"
        git tag -d "${TAG_VERSION}" 2>/dev/null || true
        git push origin --delete "${TAG_VERSION}" 2>/dev/null || true
        git tag "${TAG_VERSION}"
        echo -e "${GREEN}✓ Tag ${TAG_VERSION} recriada com sucesso!${NC}"
    else
        git tag "${TAG_VERSION}"
        echo -e "${GREEN}✓ Tag ${TAG_VERSION} criada localmente!${NC}"
    fi

    echo -e "\n${BLUE}Enviando tag para o GitHub (Disparando pipeline de Release)...${NC}"
    if git push origin "${TAG_VERSION}"; then
        echo -e "\n${GREEN}==================================================${NC}"
        echo -e "${GREEN}✓ SUCESSO! O pipeline de CI/CD foi disparado!${NC}"
        echo -e "${GREEN}==================================================${NC}"
        echo -e "Acompanhe o progresso na aba 'Actions' do repositório no GitHub."
        echo -e "Os pacotes oficiais (.deb, .AppImage e .zip para Windows) serão gerados e postados automaticamente."
    else
        echo -e "${RED}Falha ao enviar a tag. Verifique sua conexão com a internet.${NC}"
        exit 1
    fi
}

# ==========================================
# EXECUÇÃO DA OPÇÃO SELECIONADA
# ==========================================
case "$OPTION" in
    1)
        executar_build_local
        ;;
    2)
        preparar_repositorio_git
        publicar_github
        ;;
    3)
        executar_build_local
        preparar_repositorio_git
        publicar_github
        ;;
    *)
        echo -e "${RED}Opção inválida.${NC}"
        exit 1
        ;;
esac
