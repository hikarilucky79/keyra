#!/bin/bash
# Forçar parada em qualquer erro não-esperado
set -e

echo "=========================================================="
echo "🚀 INICIANDO PIPELINE DE ATUALIZAÇÃO DA RELEASE V0.1.0 🚀"
echo "=========================================================="

# 1. Adicionar e enviar todas as alterações de imagens (cartoon logo) para o GitHub
echo "-> 1. Salvando e comitando a nova logo cartoon na branch main..."
git add -A
git commit -m "style: update to new cartoon logo and assets"
git push origin main

# 2. Deletar a release v0.1.0 antiga no GitHub usando a CLI gh
echo "-> 2. Removendo a release v0.1.0 antiga do GitHub usando 'gh CLI'..."
if gh release view v0.1.0 &>/dev/null; then
    gh release delete v0.1.0 --yes
    echo "   [OK] Release antiga v0.1.0 deletada com sucesso no GitHub!"
else
    echo "   [INFO] Nenhuma release v0.1.0 anterior encontrada na nuvem. Continuando..."
fi

# 3. Deletar a tag v0.1.0 anterior localmente e na nuvem
echo "-> 3. Limpando a tag v0.1.0 antiga..."
git tag -d v0.1.0 &>/dev/null || true
git push origin --delete v0.1.0 &>/dev/null || true
echo "   [OK] Tags v0.1.0 antigas removidas!"

# 4. Criar a nova tag v0.1.0 apontando para a logo cartoon e enviar para disparar o CI/CD
echo "-> 4. Criando e enviando nova tag v0.1.0 para disparar a compilação..."
git tag v0.1.0
git push origin v0.1.0

echo ""
echo "=========================================================="
echo "🎉 SUCESSO ABSOLUTO! A NOVA COMPILAÇÃO ESTÁ NO AR! 🎉"
echo "=========================================================="
echo "O GitHub Actions foi disparado na nuvem e está compilando:"
echo " 1. O instalador portátil do Windows (.zip)"
echo " 2. O executável portátil do Linux (.AppImage)"
echo " 3. O instalador do Linux (.deb)"
echo ""
echo "Todos os instaladores virão atualizados com a logo cartoon! 🎨"
echo "Acompanhe o build em: https://github.com/hikarilucky79/keyra/actions"
echo "=========================================================="
