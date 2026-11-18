<div align="center">

# Keyra

**Engine de áudio de digitação desktop para Linux — daemon em Rust + interface nativa em Flutter Desktop via Unix Domain Sockets (IPC)**

[Arquitetura](./ARCHITECTURE_PLAN.md) · [Licença MIT](./LICENSE) · [Portfólio](https://dev-hikari.vercel.app)

</div>

---

## Sobre & Arquitetura

O **Keyra** é uma aplicação desktop de baixa latência para simulação de som de teclado mecânico construída com arquitetura cliente-servidor desacoplada:

```text
keyra-flutter (Cliente UI - Flutter Desktop / Dart)
      │
      ▼  Unix Domain Socket · protocolo JSON com prefixo de tamanho (#[cfg(unix)])
keyra-daemon (Servidor de sistema - Rust)
      ├── Captura global de entrada (evdev) e janela ativa (active-win-pos-rs)
      └── Pipeline de áudio lock-free (cpal · rodio · symphonia · rubato · ringbuf)
```

> **Compatibilidade:** o servidor IPC via Unix Domain Sockets opera sob `#[cfg(unix)]` (Linux). Em builds não-Unix (`#[cfg(not(unix))]`, como Windows), o módulo IPC do daemon executa hoje em modo stub em background.

---

## Destaques Técnicos

### Daemon em Rust (`keyra-daemon` · Edition 2021 · LTO release)
- **Captura e eventos:** leitura global de dispositivos no Linux via `evdev` e monitoramento de janela ativa com `active-win-pos-rs`.
- **Motor de áudio:** decodificação e reprodução com `cpal`, `rodio`, `symphonia` (`vorbis`, `wav`, `flac`, `mp3`), reamostragem com `rubato`, fila lock-free (`ringbuf` / `crossbeam`) e controle concorrente (`tokio`, `parking_lot`, `dashmap`, `arc-swap`).
- **Gerenciamento de soundpacks e ciclo de vida:** importação de pacotes `.zip` (`packs.rs` / `importer.rs`), atualização (`updater.rs`), logs com `tracing`, tratamento de `SIGTERM`/`SIGINT` (`signal-hook`) e arquivo PID em `/run/user/$UID/keyra.pid`.

### Interface Desktop em Flutter (`keyra-flutter`)
- Interface nativa multi-tela construída em **Dart / Flutter** com gerenciamento de estado via `provider`.
- Integração com sistema e janela usando `tray_manager`, `window_manager`, `screen_retriever`, drag-and-drop de pacotes (`desktop_drop`) e extração de paleta visual (`palette_generator`).
- Cliente IPC dedicado em `lib/ipc/` comunicando diretamente com o `keyra-daemon`.

### Empacotamento Linux (`packaging/`)
- Scripts e receitas para `.deb` (`build_deb.sh`), AppImage (`build_appimage.sh`), Arch/AUR (`PKGBUILD`, `build_arch.sh`), Flatpak (`io.github.hikarilucky79.keyra.yml`, `build_flatpak.sh`) e unit `systemd` (`keyra.service`).

---

## Estrutura do Repositório

```text
keyra/
├── keyra-daemon/          # Daemon em Rust (áudio, evdev, IPC UDS, packs, estado)
├── keyra-flutter/         # Cliente desktop em Flutter/Dart (lib/ipc, screens, widgets)
├── packaging/             # Scripts de build e empacotamento (.deb, AppImage, AUR, Flatpak, systemd)
├── ARCHITECTURE_PLAN.md   # Análise arquitetural e diagrama cliente-servidor
└── Cargo.toml             # Workspace Rust (profile.release com LTO e opt-level = 3)
```

---

## Como Compilar e Rodar (Linux)

### 1. Compilar e iniciar o daemon (`keyra-daemon`)

```bash
cargo build --release
./target/release/keyra-daemon
```

### 2. Executar a interface desktop (`keyra-flutter`)

```bash
cd keyra-flutter
flutter pub get
flutter run -d linux
```

---

## Autor & Licença

Desenvolvido por **Kauã Oliveira** (`@hikarilucky79`) · [Portfólio](https://dev-hikari.vercel.app) · [GitHub](https://github.com/hikarilucky79)

Distribuído sob a licença **MIT** — consulte [LICENSE](./LICENSE).
