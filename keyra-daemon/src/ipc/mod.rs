//! Keyra IPC Protocol
//!
//! Defines the message schema for Unix Domain Socket communication
//! between the frontend client and the keyra daemon.

#[allow(dead_code)]
pub mod client;
pub mod server;

use serde::{Deserialize, Serialize};

/// Advanced audio effects configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AudioEffects {
    pub filter_enabled: bool,
    pub filter_frequency: f32,
    pub reverb_enabled: bool,
    pub reverb_wet: f32,
}

impl Default for AudioEffects {
    fn default() -> Self {
        Self {
            filter_enabled: false,
            filter_frequency: 1000.0,
            reverb_enabled: false,
            reverb_wet: 0.2,
        }
    }
}

pub type MessageId = uuid::Uuid;

/// Commands sent from the frontend UI to the daemon.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum Command {
    /// Start playback of the current sound for the given key event.
    Play { key: String, velocity: f32 },
    /// Stop all currently playing sounds.
    Stop,
    /// Enable sound playback globally.
    Enable,
    /// Disable sound playback globally.
    Disable,
    /// Set master volume (0.0..=1.0).
    SetVolume { volume: f32 },
    /// Switch to a different sound pack by name.
    SetPack { name: String },
    /// Request current daemon status.
    Status,
    /// Ping for heartbeat / latency measurement.
    Ping { nonce: MessageId },
    /// Reload configuration from disk.
    ReloadConfig,
    /// Import a sound pack from a zip file.
    ImportSoundpack { path: String },
    /// Set or remove an application-specific profile.
    SetAppProfile { app_name: String, pack_name: Option<String> },
    /// Save a sound pack configuration (for the editor).
    SavePackConfig { name: String, config: serde_json::Value },
    /// Check for daemon/UI updates.
    CheckUpdate,
    /// Download and apply the latest update.
    PerformUpdate,
    /// --- Sound Pack Import ---
    /// Request to start an import session for a file or folder.
    ImportRequest { path: String },
    /// Update a mapping in the current import session.
    ImportUpdateMapping { file_id: String, key: String },
    /// Finalize the import and process audio.
    ImportProcess { name: String, author: String },
    /// Play a preview of a file in the import session.
    ImportPreview { file_id: String },
    /// Cancel the current import session.
    ImportCancel,
    /// Play a specific file directly from disk (preview).
    PlayDirect { path: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportFile {
    pub id: String,
    pub original_path: String,
    pub inferred_key: String,
    /// Peak data for waveform visualization (0..1.0)
    pub waveform: Vec<f32>,
}

/// Events sent from the daemon to the frontend.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "SCREAMING_SNAKE_CASE")]
pub enum Event {
    /// Full state update pushed on any state change.
    StateUpdated {
        volume: f32,
        pack: String,
        enabled: bool,
        playing: bool,
        clients_connected: usize,
        uptime_ms: u64,
        app_profiles: std::collections::HashMap<String, String>,
        available_packs: Vec<String>,
        #[serde(default)]
        effects: AudioEffects,
    },
    /// Real-time audio peak level for visualization.
    AudioPeak { peak: f32 },
    /// Error event from daemon.
    Error { message: String },
    /// Response to a Ping command.
    Pong { nonce: MessageId },
    /// Response to a Status command.
    StatusResponse {
        volume: f32,
        pack: String,
        enabled: bool,
        playing: bool,
        clients_connected: usize,
        latency_ms: f64,
        uptime_ms: u64,
        app_profiles: std::collections::HashMap<String, String>,
        available_packs: Vec<String>,
        effects: AudioEffects,
    },
    /// Notification that a newer version of Keyra is available.
    UpdateAvailable {
        version: String,
        changelog: String,
        url: String,
    },
    /// --- Sound Pack Import ---
    /// An import session has started with these files.
    ImportSessionStarted { files: Vec<ImportFile> },
    /// Progress update for audio processing.
    ImportProgress { progress: f32, message: String },
    /// Import completed successfully.
    ImportFinished { pack_name: String },
}

/// A single IPC message wrapping either a command or an event.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub id: MessageId,
    pub timestamp_ms: u64,
    pub payload: MessagePayload,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum MessagePayload {
    Command(Command),
    Event(Event),
}

impl Message {
    pub fn new_command(command: Command) -> Self {
        Self {
            id: MessageId::new_v4(),
            timestamp_ms: Self::now_ms(),
            payload: MessagePayload::Command(command),
        }
    }

    pub fn new_event(event: Event) -> Self {
        Self {
            id: MessageId::new_v4(),
            timestamp_ms: Self::now_ms(),
            payload: MessagePayload::Event(event),
        }
    }

    #[allow(dead_code)]
    pub fn reply_to(&self, event: Event) -> Self {
        Self {
            id: self.id,
            timestamp_ms: Self::now_ms(),
            payload: MessagePayload::Event(event),
        }
    }

    fn now_ms() -> u64 {
        use std::time::{SystemTime, UNIX_EPOCH};
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0)
    }
}
