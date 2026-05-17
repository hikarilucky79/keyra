//! Keyra Daemon - Main Entry Point
//!
//! Starts the IPC server, audio engine, and input listener.
//! Handles graceful shutdown on SIGTERM/SIGINT.

use anyhow::{Context, Result};
use std::fs;
use std::path::PathBuf;
use std::process;
use std::sync::Arc;
use tracing::{info, warn, Level};

use keyra_daemon::audio::{self, AudioEngine};
use keyra_daemon::input::InputMonitor;
use keyra_daemon::ipc::{self, server::IpcServer};
use keyra_daemon::migration;
use keyra_daemon::state::{AudioSignal, StateManager};
use keyra_daemon::updater::UpdateManager;
use keyra_daemon::window_monitor::WindowMonitor;

/// Write PID file to /run/user/$UID/keyra.pid (Unix) or temp dir (Windows)
#[cfg(unix)]
fn write_pid_file() -> Result<PathBuf> {
    let uid = nix::unistd::geteuid().as_raw();
    let pid_dir = PathBuf::from("/run").join(format!("user/{}", uid));

    if let Err(e) = fs::create_dir_all(&pid_dir) {
        warn!(
            "Failed to create PID directory {}: {}",
            pid_dir.display(),
            e
        );
        let fallback = PathBuf::from("/tmp/keyra.pid");
        fs::write(&fallback, process::id().to_string())
            .with_context(|| format!("Failed to write PID file at {}", fallback.display()))?;
        return Ok(fallback);
    }

    let pid_path = pid_dir.join("keyra.pid");
    fs::write(&pid_path, process::id().to_string())
        .with_context(|| format!("Failed to write PID file at {}", pid_path.display()))?;
    Ok(pid_path)
}

#[cfg(not(unix))]
fn write_pid_file() -> Result<PathBuf> {
    let temp_dir = std::env::temp_dir();
    let pid_path = temp_dir.join("keyra.pid");
    fs::write(&pid_path, process::id().to_string())
        .with_context(|| format!("Failed to write PID file at {}", pid_path.display()))?;
    Ok(pid_path)
}

/// Remove PID file on shutdown.
fn remove_pid_file(path: &PathBuf) {
    if let Err(e) = fs::remove_file(path) {
        warn!("Failed to remove PID file: {}", e);
    }
}

/// Resolve the sound pack directory. Checks user config first, then bundled fallback.
fn resolve_pack_dir(pack_name: &str, config_packs_dir: &PathBuf) -> PathBuf {
    // 1. User config dir: ~/.config/keyra/packs/<pack_name>
    let user_dir = config_packs_dir.join(pack_name);
    if user_dir.exists() && user_dir.is_dir() {
        info!("Using user sound pack: {}", user_dir.display());
        return user_dir;
    }

    // 2. Bundled fallback: relative to the binary
    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|d| d.to_path_buf()))
        .unwrap_or_else(|| PathBuf::from("."));

    let bundled_dir = exe_dir.join("packs").join(pack_name);
    if bundled_dir.exists() && bundled_dir.is_dir() {
        info!("Using bundled sound pack: {}", bundled_dir.display());
        return bundled_dir;
    }

    // 3. Development fallback: project root packs/ dir
    let dev_dir = PathBuf::from("packs").join(pack_name);
    if dev_dir.exists() && dev_dir.is_dir() {
        info!("Using development sound pack: {}", dev_dir.display());
        return dev_dir;
    }

    warn!("Sound pack '{}' not found, audio may not work", pack_name);
    user_dir
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_max_level(Level::INFO)
        .with_target(true)
        .with_thread_ids(true)
        .init();

    info!("Keyra daemon starting...");

    let pid_path = write_pid_file().context("Failed to write PID file")?;
    info!("PID file written to {}", pid_path.display());

    // Set up shutdown broadcast channel
    let (shutdown_tx, shutdown_rx) = tokio::sync::broadcast::channel::<()>(1);

    // Spawn signal handler
    #[cfg(unix)]
    {
        let mut sigterm =
            tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())?;
        let mut sigint = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::interrupt())?;

        let shutdown_tx2 = shutdown_tx.clone();
        tokio::spawn(async move {
            tokio::select! {
                _ = sigterm.recv() => {
                    info!("Received SIGTERM");
                }
                _ = sigint.recv() => {
                    info!("Received SIGINT");
                }
            }
            let _ = shutdown_tx2.send(());
        });
    }

    #[cfg(not(unix))]
    {
        let shutdown_tx2 = shutdown_tx.clone();
        tokio::spawn(async move {
            if let Err(e) = tokio::signal::ctrl_c().await {
                warn!("Failed to listen for ctrl_c: {}", e);
            } else {
                info!("Received ctrl_c signal");
            }
            let _ = shutdown_tx2.send(());
        });
    }

    // Create state manager with IPC broadcast channel
    migration::migrate_klickity_if_needed();
    migration::provision_default_packs();

    let (ipc_tx, _ipc_rx) = tokio::sync::broadcast::channel::<ipc::Message>(1024);
    let state_manager = StateManager::new(ipc_tx.clone());

    // ── Audio Engine ──────────────────────────────────────────────
    let app_state = state_manager.get_state();
    let mut audio_engine = AudioEngine::new(state_manager.clone());
    audio_engine.set_config(app_state.volume, app_state.config.latency_target_ms);

    // Resolve and load the default sound pack
    let pack_dir = resolve_pack_dir(&app_state.pack, &app_state.config.sound_packs_dir);
    match audio_engine.load_pack(&pack_dir) {
        Ok(count) => info!(
            "Sound pack loaded: {} samples from '{}'",
            count, app_state.pack
        ),
        Err(e) => warn!("Failed to load sound pack '{}': {}", app_state.pack, e),
    }

    // Start the cpal audio stream
    match audio_engine.start() {
        Ok(()) => info!("Audio engine running"),
        Err(e) => warn!(
            "Audio engine failed to start: {} (continuing without audio)",
            e
        ),
    }

    // ── Input Monitor ─────────────────────────────────────────────
    let mut input_monitor = InputMonitor::new(state_manager.clone());
    input_monitor.start();

    // ── Window Monitor ────────────────────────────────────────────
    let window_monitor = WindowMonitor::new(state_manager.clone());
    window_monitor.start(shutdown_tx.subscribe());

    // ── Updater ──────────────────────────────────────────────────
    let update_manager = Arc::new(UpdateManager::new(
        ipc_tx.clone(),
        env!("CARGO_PKG_VERSION").to_string(),
    ));

    // Spawn a thread to listen for audio signal changes (volume, pack reload, stop)
    // Note: AudioEngine contains cpal::Stream which is !Send, so it stays on the main thread.
    // We process signals through the engine's existing lock-free/Mutex-based shared state.
    let audio_signal_rx = state_manager.audio_signal_receiver().clone();
    let state_for_audio = state_manager.clone();
    let volume_atomic = audio_engine.volume_handle();
    let shared_handle = audio_engine.shared_handle();
    let mut shutdown_audio_rx = shutdown_tx.subscribe();
    let (stream_err_tx, mut stream_err_rx) = tokio::sync::mpsc::channel::<()>(1);

    std::thread::spawn(move || {
        loop {
            // Check shutdown
            match shutdown_audio_rx.try_recv() {
                Ok(_) | Err(tokio::sync::broadcast::error::TryRecvError::Closed) => {
                    // Clear voices on shutdown
                    if let Ok(mut shared) = shared_handle.lock() {
                        shared.active_voices.clear();
                    }
                    info!("Audio signal listener shutting down");
                    break;
                }
                _ => {}
            }

            match audio_signal_rx.recv_timeout(std::time::Duration::from_millis(100)) {
                Ok(signal) => match signal {
                    AudioSignal::VolumeChanged(vol) => {
                        let v = vol.clamp(0.0, 1.0);
                        volume_atomic
                            .store((v * 10000.0) as u32, std::sync::atomic::Ordering::Relaxed);
                        info!("Audio volume updated to {:.2}", v);
                    }
                    AudioSignal::ReloadPack { name, path: _ } => {
                        let state = state_for_audio.get_state();
                        let pack_dir = resolve_pack_dir(&name, &state.config.sound_packs_dir);

                        info!("Reloading pack '{}' from {:?}", name, pack_dir);

                        if let Ok(mut shared) = shared_handle.lock() {
                            let mut samples = std::collections::HashMap::new();
                            match audio::load_pack_to_map(&pack_dir, &mut samples) {
                                Ok(count) => {
                                    shared.samples = samples;
                                    shared.active_voices.clear();
                                    info!("Reloaded pack '{}': {} samples", name, count);
                                }
                                Err(e) => warn!("Failed to reload pack '{}': {}", name, e),
                            }
                        }
                    }
                    AudioSignal::Stop => {
                        if let Ok(mut shared) = shared_handle.lock() {
                            shared.active_voices.clear();
                        }
                    }
                    AudioSignal::StreamError(err) => {
                        warn!("Stream error received: {}. Requesting restart.", err);
                        let _ = stream_err_tx.blocking_send(());
                    }
                    AudioSignal::AudioPeak(peak) => {
                        let _ =
                            ipc_tx.send(ipc::Message::new_event(ipc::Event::AudioPeak { peak }));
                    }
                    AudioSignal::PlayFile(path) => {
                        if let Ok(sample) = audio::AudioEngine::decode_file(&path) {
                            if let Ok(mut shared) = shared_handle.lock() {
                                shared.active_voices.push(audio::ActiveVoice {
                                    sample_data: sample.data,
                                    sample_rate: sample.sample_rate,
                                    sample_channels: sample.channels,
                                    position: 0.0,
                                    velocity: volume_atomic
                                        .load(std::sync::atomic::Ordering::Relaxed)
                                        as f32
                                        / 10000.0,
                                    pitch: 1.0,
                                });
                            }
                        }
                    }
                },
                Err(crossbeam::channel::RecvTimeoutError::Timeout) => {}
                Err(crossbeam::channel::RecvTimeoutError::Disconnected) => break,
            }
        }
    });

    // ── IPC Server ────────────────────────────────────────────────
    #[cfg(unix)]
    let (socket_path, fallback_socket_path) = {
        let uid = nix::unistd::geteuid().as_raw();
        let socket_path = PathBuf::from("/run")
            .join(format!("user/{}", uid))
            .join("keyra.sock");
        let fallback_socket_path = PathBuf::from("/tmp/keyra.sock");
        (socket_path, fallback_socket_path)
    };

    #[cfg(not(unix))]
    let (socket_path, fallback_socket_path) = {
        let temp_dir = std::env::temp_dir();
        let socket_path = temp_dir.join("keyra.sock");
        let fallback_socket_path = temp_dir.join("keyra_fallback.sock");
        (socket_path, fallback_socket_path)
    };

    let ipc_server = IpcServer::new(
        socket_path,
        fallback_socket_path,
        state_manager.clone(),
        update_manager.clone(),
        shutdown_rx,
    );

    info!("Starting IPC server...");
    let _server_events = ipc_server.run()?;

    // ── Wait for shutdown or restart ──────────────────────────────
    let mut shutdown_complete = shutdown_tx.subscribe();

    loop {
        tokio::select! {
            _ = shutdown_complete.recv() => {
                break;
            }
            Some(_) = stream_err_rx.recv() => {
                info!("Attempting to restart audio engine...");
                if let Err(e) = audio_engine.start() {
                    warn!("Failed to restart audio engine: {}", e);
                }
            }
        }
    }

    info!("Shutting down daemon...");
    input_monitor.stop();
    audio_engine.stop();
    remove_pid_file(&pid_path);
    info!("Keyra daemon stopped gracefully");

    Ok(())
}
