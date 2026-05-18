# 🏹 Guia de Publicação no AUR (Arch User Repository)

Este guia explica como configurar a publicação automatizada do Keyra no AUR utilizando a chave SSH fornecida.

---

## 🔑 Suas Chaves SSH Cadastradas

Para realizar o deploy automático no AUR via GitHub Actions, você utilizará o seguinte par de chaves:

* **Chave Pública (AUR):**
  ```text
  ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINw0/LZk+0Rdl4qcXe3Zl4GI2c701e0HIKT1pJZC+mbO
  ```
* **Chave Privada (GitHub Secrets):**
  A chave privada correspondente a esta chave pública deve ser adicionada como um segredo no seu repositório do GitHub.

---

## 🛠️ Passo a Passo para Configuração

### Passo 1: Adicionar a Chave Pública no AUR
1. Acesse o site do **[AUR (Arch User Repository)](https://aur.archlinux.org/)** e faça login na sua conta.
2. Vá em **My Account** (Minha Conta).
3. No campo **SSH Public Key** (Chave Pública SSH), cole a sua chave pública:
   ```text
   ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINw0/LZk+0Rdl4qcXe3Zl4GI2c701e0HIKT1pJZC+mbO
   ```
4. Clique em **Update** (Atualizar) no final da página para salvar.

---

### Passo 2: Adicionar a Chave Privada no GitHub
1. Acesse o seu repositório do Keyra no GitHub: `https://github.com/hikarilucky79/keyra`
2. Vá na aba **Settings** (Configurações) no topo.
3. No menu lateral esquerdo, clique em **Secrets and variables** -> **Actions**.
4. Clique no botão verde **New repository secret** (Novo segredo do repositório).
5. Preencha os campos com as seguintes informações:
   * **Name:** `AUR_SSH_PRIVATE_KEY`
   * **Secret:** Cole o conteúdo completo da sua chave privada (incluindo as linhas `-----BEGIN OPENSSH PRIVATE KEY-----` e `-----END OPENSSH PRIVATE KEY-----`).
6. Clique em **Add secret** para salvar.

---

## 🚀 Como Publicar uma Nova Versão

Após realizar as configurações acima, o fluxo de publicação se torna 100% automático!

Sempre que você criar e enviar uma nova Tag de versão no Git, a pipeline do GitHub Actions fará todo o trabalho:

1. **Criar a Tag localmente:**
   ```bash
   git tag -a v0.1.0 -m "Release v0.1.0"
   ```
2. **Enviar a Tag para o GitHub:**
   ```bash
   git push origin v0.1.0
   ```

A pipeline do GitHub detectará a nova tag, compilará os binários para Windows e Linux, gerará as notas de lançamento no GitHub Releases e, em seguida, fará o commit e push automáticos do `PKGBUILD.production`, `.SRCINFO` e atalhos diretamente para a conta do AUR!
