<div align="center">

# Keyra

<img src="./app_logo.png" alt="Logo do Keyra" width="132" />

<br />

![Rust](https://img.shields.io/badge/Rust-Edition_2021-0D0D0E?style=flat-square&logo=rust&logoColor=DEA584)
![Flutter](https://img.shields.io/badge/Flutter-Desktop-0D0D0E?style=flat-square&logo=flutter&logoColor=02569B)
![Linux](https://img.shields.io/badge/Linux-IPC_UDS-0D0D0E?style=flat-square&logo=linux&logoColor=FCC624)
![License](https://img.shields.io/badge/Licen%C3%A7a-MIT-C86D51?style=flat-square)

<br />

[Arquitetura](./ARCHITECTURE_PLAN.md) · [Licença MIT](./LICENSE) · [Portfólio](https://dev-hikari.vercel.app)

</div>

---

## O que é

**Keyra** é uma engine de áudio de digitação desktop de baixa latência para Linux, construída com arquitetura cliente-servidor desacoplada: um daemon de sistema em **Rust** captura eventos globais de teclado e processa o áudio de forma lock-free, enquanto a interface nativa em **Flutter Desktop** controla perfis, volume e soundpacks em tempo real via Unix Domain Sockets (`#[cfg(unix)]`).

---

## Principais Funcionalidades

- **Captura global e reprodução lock-free no Linux:** leitura direta de dispositivos via `evdev` e mixer de baixa latência (`cpal`, `rodio`, `symphonia`, `rubato`, `ringbuf`) para soundpacks mecânicos (Cherry MX, Topre, EG) em `ogg`, `wav`, `flac` e `mp3`.
- **Perfis automáticos por janela ativa:** alternância automática de soundpack conforme o aplicativo em foco via `active-win-pos-rs`.
- **Interface nativa Flutter Desktop:** editor de soundpacks, importação drag-and-drop de pacotes `.zip` (`desktop_drop`), extração de paleta dinâmica (`palette_generator`) e controle em segundo plano na bandeja (`tray_manager`).
- **Empacotamento Linux multi-distro:** receitas e scripts prontos para `.deb`, AppImage, Arch/AUR (`PKGBUILD`), Flatpak e serviço `systemd`.

---

## Arquitetura e Tecnologias

```text
keyra-flutter (Cliente UI - Flutter Desktop / Dart)
      │
      ▼  Unix Domain Socket · protocolo JSON com prefixo de tamanho (#[cfg(unix)])
keyra-daemon (Servidor de sistema - Rust)
      ├── Captura global de entrada (evdev) e janela ativa (active-win-pos-rs)
      └── Pipeline de áudio lock-free (cpal · rodio · symphonia · rubato · ringbuf)
```

> **Compatibilidade:** o servidor IPC via Unix Domain Sockets opera sob `#[cfg(unix)]` (Linux). Em builds não-Unix (`#[cfg(not(unix))]`, como Windows), o módulo IPC do daemon executa hoje em modo stub em background.

### Destaques Técnicos

- **Daemon em Rust (`keyra-daemon` · Edition 2021 · LTO release):** controle concorrente com `tokio`, `parking_lot`, `dashmap` e `arc-swap`, importação de `.zip` (`packs.rs` / `importer.rs`), atualização (`updater.rs`), logs estruturados (`tracing`), tratamento de `SIGTERM`/`SIGINT` (`signal-hook`) e arquivo PID em `/run/user/$UID/keyra.pid`.
- **Cliente Desktop em Flutter (`keyra-flutter`):** gerenciamento de estado via `provider`, integração nativa (`tray_manager`, `window_manager`, `screen_retriever`) e cliente IPC dedicado em `lib/ipc/`.
- **Empacotamento (`packaging/`):** scripts reproduzíveis em `build_deb.sh`, `build_appimage.sh`, `build_arch.sh`, `build_flatpak.sh`, manifesto `io.github.hikarilucky79.keyra.yml` e unit `keyra.service`.

### Estrutura do Repositório

```text
keyra/
├── keyra-daemon/          # Daemon em Rust (áudio, evdev, IPC UDS, packs, estado e testes)
├── keyra-flutter/         # Cliente desktop em Flutter/Dart (lib/ipc, providers, screens, widgets)
├── packaging/             # Receitas e scripts (.deb, AppImage, AUR, Flatpak, systemd)
├── .github/workflows/     # Automação de release (release.yml)
├── ARCHITECTURE_PLAN.md   # Análise arquitetural e diagrama cliente-servidor
└── Cargo.toml             # Workspace Rust (profile.release com LTO e opt-level = 3)
```

---

## Boas Práticas de Engenharia

- **Testes automatizados (29 testes em Rust + testes Flutter):**
  - [`keyra-daemon/tests/audio_integrity.rs`](./keyra-daemon/tests/audio_integrity.rs) (**11 testes**): valida mapeamento estrutural `evdev`/Mechvibes, permutações de carregamento de packs, normalização matemática de áudio, variações rápidas de volume, entropia de IDs IPC e resiliência a `config.json` malformado ou diretórios vazios.
  - [`keyra-daemon/tests/integration.rs`](./keyra-daemon/tests/integration.rs) (**18 testes**): verifica serialização de comandos e eventos IPC, fluxo ping-pong, decodificação de todos os samples empacotados e mapeamento completo de keycodes.
  - [`keyra-flutter/test/widget_test.dart`](./keyra-flutter/test/widget_test.dart): verificação da interface Flutter.
- **Arquitetura desacoplada e Workspace Cargo:** separação explícita entre daemon de sistema (`audio/`, `input/`, `ipc/`, `state/`) e interface desktop (`lib/ipc/`, `providers/`, `screens/`), com build `release` otimizado em `Cargo.toml` (`lto`, `opt-level = 3`).
- **Automação de empacotamento e versionamento semântico:** workflow [`.github/workflows/release.yml`](./.github/workflows/release.yml), scripts de build em `packaging/` e histórico versionado com commits semânticos (`feat:`, `docs:`, `style:`, `flatpak:`).

---

## Como Rodar Localmente (Linux)

### 1. Compilar e executar os testes do daemon (`keyra-daemon`)

```bash
cargo test
cargo build --release
./target/release/keyra-daemon
```

### 2. Testar e executar a interface desktop (`keyra-flutter`)

```bash
cd keyra-flutter
flutter pub get
flutter test
flutter run -d linux
```

---

## Autor & Licença

Desenvolvido por **Kauã Oliveira** (`@hikarilucky79`) · [Portfólio](https://dev-hikari.vercel.app) · [GitHub](https://github.com/hikarilucky79)

Distribuído sob a licença **MIT** — consulte [LICENSE](./LICENSE).
