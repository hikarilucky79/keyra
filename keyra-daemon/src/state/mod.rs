//! Application state manager for the Keyra daemon.
//!
//! Holds all runtime configuration and state. Acts as the single source of truth
//! that the UI synchronizes with via IPC events.

use crate::ipc::{Event, Message};
use parking_lot::RwLock;
use serde::{Deserialize, Serialize};
use notify::{Watcher, RecursiveMode, Config as WatcherConfig, RecommendedWatcher};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Instant;
use tracing::*;

/// Runtime configuration that can be hot-reloaded.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub volume: f32,
    pub pack: String,
    pub enabled: bool,
    #[serde(skip)]
    pub sound_packs_dir: PathBuf,
    pub latency_target_ms: u64,
    #[serde(default)]
    pub app_profiles: std::collections::HashMap<String, String>,
    #[serde(default)]
    pub effects: crate::ipc::AudioEffects,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            volume: 0.7,
            pack: "cherrymx-black-pbt".to_string(),
            enabled: true,
            sound_packs_dir: dirs::config_dir()
                .unwrap_or_else(|| PathBuf::from("/tmp"))
                .join("keyra")
                .join("packs"),
            latency_target_ms: 10,
            app_profiles: std::collections::HashMap::new(),
            effects: crate::ipc::AudioEffects::default(),
        }
    }
}

/// Snapshot of the daemon state, pushed to UI on changes.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppState {
    pub volume: f32,
    pub pack: String,
    pub enabled: bool,
    pub playing: bool,
    pub clients_connected: usize,
    pub latency_ms: f64,
    pub uptime_ms: u64,
    pub config: Config,
    pub app_profiles: std::collections::HashMap<String, String>,
    pub available_packs: Vec<String>,
    pub effects: crate::ipc::AudioEffects,
}

impl Default for AppState {
    fn default() -> Self {
        let config = Config::default();
        let available_packs = Self::scan_packs(&config.sound_packs_dir);
        Self {
            volume: 0.7,
            pack: "cherrymx-black-pbt".to_string(),
            enabled: true,
            playing: false,
            clients_connected: 0,
            latency_ms: 0.0,
            uptime_ms: 0,
            config,
            app_profiles: std::collections::HashMap::new(),
            available_packs,
            effects: crate::ipc::AudioEffects::default(),
        }
    }
}

impl AppState {
    pub fn scan_packs(path: &PathBuf) -> Vec<String> {
        let mut packs = Vec::new();
        
        // Ensure directory exists
        if !path.exists() {
            let _ = std::fs::create_dir_all(path);
            return packs;
        }

        if let Ok(entries) = std::fs::read_dir(path) {
            for entry in entries.flatten() {
                if entry.path().is_dir() {
                    if let Some(name) = entry.file_name().to_str() {
                        packs.push(name.to_string());
                    }
                }
            }
        }
        packs.sort();
        packs
    }
}

/// Signal sent to the audio engine when a pack change or volume change occurs.
#[derive(Debug, Clone)]
pub enum AudioSignal {
    /// Reload the sound pack at the given path.
    ReloadPack {
        name: String,
        #[allow(dead_code)]
        path: PathBuf,
    },
    /// Update volume to the given value.
    VolumeChanged(f32),
    /// Stop all playback.
    Stop,
    /// Audio stream encountered a fatal error (e.g. device disconnected).
    StreamError(String),
    /// Real-time audio peak level for visualization.
    AudioPeak(f32),
    /// Play a specific file directly (for preview).
    PlayFile(PathBuf),
}

/// The state manager - wraps state with a lock and notifies IPC on changes.
pub struct StateManager {
    state: Arc<RwLock<AppState>>,
    start_time: Instant,
    ipc_tx: tokio::sync::broadcast::Sender<Message>,
    pub trigger_tx: crossbeam::channel::Sender<(String, f32)>,
    pub trigger_rx: crossbeam::channel::Receiver<(String, f32)>,
    /// Channel to signal the audio engine about config changes.
    pub audio_signal_tx: crossbeam::channel::Sender<AudioSignal>,
    pub audio_signal_rx: crossbeam::channel::Receiver<AudioSignal>,
}

impl StateManager {
    pub fn new(ipc_tx: tokio::sync::broadcast::Sender<Message>) -> Arc<Self> {
        let (trigger_tx, trigger_rx) = crossbeam::channel::bounded::<(String, f32)>(1024);
        let (audio_signal_tx, audio_signal_rx) = crossbeam::channel::bounded::<AudioSignal>(64);

        let state = AppState::default();
        let manager = Arc::new(Self {
            state: Arc::new(RwLock::new(state)),
            start_time: Instant::now(),
            ipc_tx,
            trigger_tx,
            trigger_rx,
            audio_signal_tx,
            audio_signal_rx,
        });

        // Phase 7: Auto-provisioning
        manager.ensure_default_packs();

        // Inicia o watcher em uma thread separada
        let m_clone = manager.clone();
        std::thread::spawn(move || {
            m_clone.start_watcher();
        });

        manager
    }

    /// Clone a reference-counted handle to this manager.
    pub fn clone_handle(self: &Arc<Self>) -> Arc<Self> {
        Arc::clone(self)
    }

    /// Get the IPC broadcast channel.
    pub fn ipc_tx(&self) -> &tokio::sync::broadcast::Sender<Message> {
        &self.ipc_tx
    }

    /// Get current state snapshot.
    pub fn get_state(&self) -> AppState {
        self.state.read().clone()
    }

    /// Get the audio trigger channel receiver.
    pub fn trigger_receiver(&self) -> &crossbeam::channel::Receiver<(String, f32)> {
        &self.trigger_rx
    }

    /// Get the audio signal receiver (for the audio engine to listen on).
    pub fn audio_signal_receiver(&self) -> &crossbeam::channel::Receiver<AudioSignal> {
        &self.audio_signal_rx
    }

    /// Set volume (0.0..=1.0). Notifies both IPC clients and audio engine.
    pub fn set_volume(&self, volume: f32) {
        let volume = volume.clamp(0.0, 1.0);
        self.state.write().volume = volume;
        self.broadcast_state();
        let _ = self
            .audio_signal_tx
            .try_send(AudioSignal::VolumeChanged(volume));
        info!("Volume set to {:.2}", volume);
    }

    /// Set active sound pack. Signals the audio engine to reload.
    pub fn set_pack(&self, name: String) {
        let pack_path = {
            let state = self.state.read();
            state.config.sound_packs_dir.join(&name)
        };
        self.state.write().pack = name.clone();
        self.broadcast_state();
        let _ = self.audio_signal_tx.try_send(AudioSignal::ReloadPack {
            name: name.clone(),
            path: pack_path,
        });
        info!("Sound pack switched to '{}'", name);
    }

    /// Set global enabled state.
    pub fn set_enabled(&self, enabled: bool) {
        self.state.write().enabled = enabled;
        self.broadcast_state();
        if !enabled {
            let _ = self.audio_signal_tx.try_send(AudioSignal::Stop);
        }
        info!("Daemon {}", if enabled { "enabled" } else { "disabled" });
    }

    /// Set or remove a sound pack profile for a specific application.
    pub fn set_app_profile(&self, app_name: String, pack_name: Option<String>) {
        {
            let mut state = self.state.write();
            if let Some(pack) = pack_name {
                state.config.app_profiles.insert(app_name.clone(), pack.clone());
                state.app_profiles.insert(app_name.clone(), pack);
            } else {
                state.config.app_profiles.remove(&app_name);
                state.app_profiles.remove(&app_name);
            }
        }
        self.broadcast_state();
    }

    /// Save a sound pack configuration to disk.
    pub fn save_pack_config(&self, name: String, config: serde_json::Value) -> Result<(), String> {
        let packs_dir = self.state.read().config.sound_packs_dir.clone();
        let pack_path = packs_dir.join(&name);
        
        if !pack_path.exists() {
            return Err(format!("Pack directory does not exist: {:?}", pack_path));
        }

        let config_path = pack_path.join("config.json");
        let content = serde_json::to_string_pretty(&config)
            .map_err(|e| format!("Failed to serialize config: {}", e))?;
        
        std::fs::write(&config_path, content)
            .map_err(|e| format!("Failed to write config file: {}", e))?;

        info!("Saved configuration for pack '{}'", name);
        
        // If it's the current pack, reload it
        if self.state.read().pack == name {
            self.set_pack(name);
        }

        Ok(())
    }

    /// Trigger sound playback for a key event.
    pub fn trigger_play(&self, key: String, velocity: f32) {
        {
            let state = self.state.read();
            if !state.enabled {
                return;
            }
        }

        // Send to audio thread via lock-free channel.
        // try_send is non-blocking: if the channel is full, the keypress is silently dropped
        // (better than blocking the input thread).
        match self.trigger_tx.try_send((key, velocity)) {
            Ok(_) => {}
            Err(crossbeam::channel::TrySendError::Full(_)) => {
                warn!("Audio trigger channel full — dropping keypress");
            }
            Err(crossbeam::channel::TrySendError::Disconnected(_)) => {
                error!("Audio trigger channel disconnected");
            }
        }
    }

    /// Trigger sound playback for a specific file (preview).
    pub fn trigger_play_direct(&self, path: &std::path::Path) {
        let _ = self.audio_signal_tx.try_send(AudioSignal::PlayFile(path.to_path_buf()));
    }

    /// Stop all playback.
    pub fn stop(&self) {
        self.state.write().playing = false;
        let _ = self.audio_signal_tx.try_send(AudioSignal::Stop);
        self.broadcast_state();
        info!("Playback stopped");
    }

    /// Reload configuration from disk and rescan packs.
    pub fn reload_config(&self) {
        info!("Reloading configuration and rescanning packs...");
        let packs_dir = self.state.read().config.sound_packs_dir.clone();
        let new_packs = AppState::scan_packs(&packs_dir);
        
        {
            let mut state = self.state.write();
            state.available_packs = new_packs;
        }

        self.broadcast_state();
    }

    /// Update connected client count.
    pub fn set_clients_connected(&self, count: usize) {
        self.state.write().clients_connected = count;
    }

    fn uptime_ms(&self) -> u64 {
        self.start_time.elapsed().as_millis() as u64
    }

    fn broadcast_state(&self) {
        let state = self.get_state();
        let event = Event::StateUpdated {
            volume: state.volume,
            pack: state.pack.clone(),
            enabled: state.enabled,
            playing: state.playing,
            clients_connected: state.clients_connected,
            uptime_ms: self.uptime_ms(),
            app_profiles: state.app_profiles.clone(),
            available_packs: state.available_packs.clone(),
            effects: state.effects.clone(),
        };
        let _ = self.ipc_tx.send(Message::new_event(event));
    }

    fn start_watcher(&self) {
        let packs_dir = self.state.read().config.sound_packs_dir.clone();
        
        // Ensure directory exists
        if !packs_dir.exists() {
            let _ = std::fs::create_dir_all(&packs_dir);
        }

        let (tx, rx) = std::sync::mpsc::channel();

        let mut watcher = match RecommendedWatcher::new(tx, WatcherConfig::default()) {
            Ok(w) => w,
            Err(e) => {
                error!("Failed to create watcher: {}", e);
                return;
            }
        };

        if let Err(e) = watcher.watch(&packs_dir, RecursiveMode::Recursive) {
            error!("Failed to watch directory {:?}: {}", packs_dir, e);
            return;
        }

        info!("Watching sound packs directory: {:?}", packs_dir);

        // Event loop for the watcher
        for res in rx {
            match res {
                Ok(_) => {
                    // Algo mudou! Re-escaneia os packs.
                    let new_packs = AppState::scan_packs(&packs_dir);
                    let mut state = self.state.write();
                    if state.available_packs != new_packs {
                        state.available_packs = new_packs;
                        drop(state);
                        info!("Sound packs directory changed, updating available packs.");
                        self.broadcast_state();
                    }
                }
                Err(e) => error!("Watcher error: {}", e),
            }
        }
    }

    /// Phase 7: Ensure the user has at least some default packs on launch.
    fn ensure_default_packs(&self) {
        let packs_dir = self.state.read().config.sound_packs_dir.clone();
        
        if !packs_dir.exists() {
            let _ = std::fs::create_dir_all(&packs_dir);
        }

        // List of default packs to "provision" if missing
        let defaults = ["classic-keyboard", "classic-mouse"];
        let mut created = false;

        for pack in defaults {
            let pack_path = packs_dir.join(pack);
            if !pack_path.exists() {
                info!("Provisioning default pack: {}", pack);
                let _ = std::fs::create_dir_all(&pack_path);
                
                // In a real app, we would extract files from an embedded archive here.
                // For now, we just create the directory so the UI sees it.
                // We'll also create a dummy config.json so it's recognized as a valid pack.
                let config_content = if pack == "classic-keyboard" {
                    r#"{"name": "Classic Keyboard", "key_define_type": "multi", "definitions": {}}"#
                } else {
                    r#"{"name": "Classic Mouse", "key_define_type": "multi", "definitions": {}}"#
                };
                let _ = std::fs::write(pack_path.join("config.json"), config_content);
                created = true;
            }
        }

        if created {
            let new_packs = AppState::scan_packs(&packs_dir);
            let mut state = self.state.write();
            state.available_packs = new_packs;
        }
    }
}
