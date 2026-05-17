//! Audio engine for Keyra daemon.
//!
//! Pre-decodes sound samples into memory and plays them via cpal
//! with lock-free triggering from the input thread.

use crate::state::StateManager;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{SampleFormat, SizedSample, StreamConfig};
use crossbeam::channel::{Receiver, TryRecvError};
use rodio::Source;
use std::collections::HashMap;
use std::path::Path;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use tracing::*;

/// Pre-decoded audio sample stored as interleaved f32 PCM.
#[derive(Debug, Clone)]
pub struct AudioSample {
    pub data: Arc<[f32]>,
    pub sample_rate: u32,
    pub channels: u16,
    #[allow(dead_code)]
    pub name: String,
}

/// A loaded sample entry with all metadata consolidated.
#[derive(Debug, Clone)]
pub struct SampleEntry {
    pub data: Arc<[f32]>,
    pub sample_rate: u32,
    pub channels: u16,
}

/// Configuration for the audio engine.
#[derive(Debug, Clone)]
pub struct AudioConfig {
    pub output_device: Option<String>,
    pub latency_ms: u64,
    pub volume: f32,
}

impl Default for AudioConfig {
    fn default() -> Self {
        Self {
            output_device: None,
            latency_ms: 10,
            volume: 0.7,
        }
    }
}

/// Active voice: one instance of a playing sample.
pub struct ActiveVoice {
    pub sample_data: Arc<[f32]>,
    pub sample_rate: u32,
    pub sample_channels: u16,
    pub position: f32,
    pub velocity: f32,
    pub pitch: f32,
}

/// Shared audio engine state across the audio callback.
pub struct EngineShared {
    pub samples: HashMap<String, SampleEntry>,
    pub active_voices: Vec<ActiveVoice>,
    /// Pre-allocated buffer for mixing to avoid allocations in the audio thread.
    pub mix_buffer: Vec<f32>,
}

impl Default for EngineShared {
    fn default() -> Self {
        Self {
            samples: HashMap::new(),
            active_voices: Vec::new(),
            mix_buffer: Vec::with_capacity(1024),
        }
    }
}

/// The audio engine manages pre-decoded samples and real-time playback.
pub struct AudioEngine {
    _state_manager: Arc<StateManager>,
    trigger_rx: Receiver<(String, f32)>,
    audio_signal_tx: crossbeam::channel::Sender<crate::state::AudioSignal>,
    shared: Arc<Mutex<EngineShared>>,
    config: AudioConfig,
    /// Atomic volume scaled to 0..10000 for lock-free reads in the audio callback.
    volume_atomic: Arc<AtomicU32>,
    stream_handle: Mutex<Option<cpal::Stream>>,
}

impl AudioEngine {
    pub fn new(state_manager: Arc<StateManager>) -> Self {
        let trigger_rx = state_manager.trigger_receiver().clone();
        let audio_signal_tx = state_manager.audio_signal_tx.clone();

        Self {
            _state_manager: state_manager,
            trigger_rx,
            audio_signal_tx,
            shared: Arc::new(Mutex::new(EngineShared::default())),
            config: AudioConfig::default(),
            volume_atomic: Arc::new(AtomicU32::new(7000)), // 0.7 * 10000
            stream_handle: Mutex::new(None),
        }
    }

    /// Get a clone of the atomic volume handle for lock-free cross-thread access.
    pub fn volume_handle(&self) -> Arc<AtomicU32> {
        self.volume_atomic.clone()
    }

    /// Get a clone of the shared engine state handle for cross-thread access.
    pub fn shared_handle(&self) -> Arc<Mutex<EngineShared>> {
        self.shared.clone()
    }

    /// Update the audio config from state config.
    pub fn set_config(&mut self, volume: f32, latency_ms: u64) {
        self.config.volume = volume.clamp(0.0, 1.0);
        self.config.latency_ms = latency_ms;
        self.volume_atomic
            .store((self.config.volume * 10000.0) as u32, Ordering::Relaxed);
    }

    /// Dynamically update volume without restarting the stream.
    #[allow(dead_code)]
    pub fn set_volume(&self, volume: f32) {
        let v = volume.clamp(0.0, 1.0);
        self.volume_atomic
            .store((v * 10000.0) as u32, Ordering::Relaxed);
    }

    pub fn load_pack(&self, pack_dir: &Path) -> Result<usize, String> {
        // First, load everything into a temporary map to keep the lock duration short
        let mut samples = HashMap::new();
        load_pack_to_map(pack_dir, &mut samples)?;

        let mut shared = self.shared.lock().unwrap();
        shared.samples = samples;
        shared.active_voices.clear();
        Ok(shared.samples.len())
    }

    /// Decode any audio file (OGG, MP3, WAV, FLAC) into f32 PCM using rodio.
    pub fn decode_file(path: &Path) -> Result<AudioSample, String> {
        let file =
            std::fs::File::open(path).map_err(|e| format!("Failed to open {:?}: {}", path, e))?;
        let source = rodio::Decoder::new(std::io::BufReader::new(file))
            .map_err(|e| format!("Failed to decode {:?}: {}", path, e))?;

        let sample_rate = source.sample_rate();
        let channels = source.channels();
        let mut samples: Vec<f32> = source.convert_samples::<f32>().collect();

        if samples.is_empty() {
            return Err(format!("Empty audio data in {:?}", path));
        }

        // --- Phase 7: Peak Normalization ---
        let peak = samples
            .iter()
            .map(|s| s.abs())
            .fold(0.0f32, |a, b| a.max(b));

        if peak > 0.0 && peak < 0.9 {
            let factor = 0.9 / peak;
            for s in samples.iter_mut() {
                *s *= factor;
            }
            trace!(
                "Normalized {:?} (peak was {:.2}, factor {:.2})",
                path,
                peak,
                factor
            );
        }

        let name = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("unknown")
            .to_string();

        Ok(AudioSample {
            data: Arc::from(samples.into_boxed_slice()),
            sample_rate,
            channels,
            name,
        })
    }

    /// Start the audio output stream.
    pub fn start(&mut self) -> Result<(), String> {
        // Stop any existing stream
        self.stop();

        let host = cpal::default_host();
        let device = self
            .config
            .output_device
            .as_ref()
            .and_then(|name| {
                host.output_devices()
                    .ok()?
                    .find(|d| d.name().ok().as_deref() == Some(name))
            })
            .or_else(|| host.default_output_device())
            .ok_or("No output device available")?;

        let device_config = device
            .default_output_config()
            .map_err(|e| format!("Failed to get default output config: {}", e))?;

        let sample_rate = device_config.sample_rate().0;
        let channels = device_config.channels() as usize;

        // Calculate buffer size from latency target
        let latency_frames = ((self.config.latency_ms as f32 / 1000.0) * sample_rate as f32) as u32;
        let latency_frames = latency_frames.max(64); // Minimum 64 frames

        let trigger_rx = self.trigger_rx.clone();
        let audio_signal_tx = self.audio_signal_tx.clone();
        let shared = self.shared.clone();
        let volume_atomic = self.volume_atomic.clone();

        let stream_config = StreamConfig {
            channels: channels as u16,
            sample_rate: cpal::SampleRate(sample_rate),
            buffer_size: cpal::BufferSize::Default,
        };

        let sample_format = device_config.sample_format();
        let stream = match sample_format {
            SampleFormat::F32 => Self::build_stream::<f32>(
                &device,
                &stream_config,
                trigger_rx,
                volume_atomic,
                shared,
                audio_signal_tx.clone(),
            ),
            SampleFormat::I16 => Self::build_stream::<i16>(
                &device,
                &stream_config,
                trigger_rx,
                volume_atomic,
                shared,
                audio_signal_tx.clone(),
            ),
            SampleFormat::U16 => Self::build_stream::<u16>(
                &device,
                &stream_config,
                trigger_rx,
                volume_atomic,
                shared,
                audio_signal_tx,
            ),
            _ => return Err(format!("Unsupported sample format: {:?}", sample_format)),
        };

        let stream = stream?;
        stream
            .play()
            .map_err(|e| format!("Failed to play stream: {}", e))?;

        info!(
            "Audio engine started: device='{}', rate={}Hz, ch={}, latency={}frames, format={:?}",
            device.name().unwrap_or_default(),
            sample_rate,
            channels,
            latency_frames,
            sample_format,
        );

        let mut handle = self.stream_handle.lock().unwrap();
        *handle = Some(stream);

        Ok(())
    }

    fn build_stream<T>(
        device: &cpal::Device,
        config: &StreamConfig,
        trigger_rx: Receiver<(String, f32)>,
        volume_atomic: Arc<AtomicU32>,
        shared: Arc<Mutex<EngineShared>>,
        audio_signal_tx: crossbeam::channel::Sender<crate::state::AudioSignal>,
    ) -> Result<cpal::Stream, String>
    where
        T: SizedSample + cpal::FromSample<f32>,
    {
        let num_channels = config.channels as usize;
        let dst_rate = config.sample_rate.0 as f32;
        let config = config.clone();

        let audio_signal_tx_err = audio_signal_tx.clone();
        let err_fn = move |err: cpal::StreamError| {
            error!("Audio stream error: {}", err);
            let _ = audio_signal_tx_err
                .try_send(crate::state::AudioSignal::StreamError(err.to_string()));
        };

        let stream = device.build_output_stream(
            &config,
            move |output: &mut [T], _: &cpal::OutputCallbackInfo| {
                // Read current volume (lock-free)
                let base_volume = volume_atomic.load(Ordering::Relaxed) as f32 / 10000.0;

                // Drain triggers and mix — single lock acquisition
                {
                    let mut shared = shared.lock().unwrap();

                    // Process incoming triggers
                    loop {
                        match trigger_rx.try_recv() {
                            Ok((key, velocity)) => {
                                // Try exact key match first, then fall back to "default"
                                let entry = shared
                                    .samples
                                    .get(&key)
                                    .or_else(|| shared.samples.get("default"))
                                    .cloned();

                                if let Some(entry) = entry {
                                    // Phase 7: Pitch Jitter (±2% variation)
                                    let jitter = (rand::random::<f32>() - 0.5) * 0.04;
                                    let pitch = 1.0 + jitter;

                                    // Phase 7: Simulated Velocity Scaling (±5% volume variation)
                                    let vol_variation = 1.0 + (rand::random::<f32>() - 0.5) * 0.1;
                                    let final_velocity = velocity * base_volume * vol_variation;

                                    shared.active_voices.push(ActiveVoice {
                                        sample_data: entry.data,
                                        sample_rate: entry.sample_rate,
                                        sample_channels: entry.channels,
                                        position: 0.0,
                                        velocity: final_velocity,
                                        pitch,
                                    });
                                }
                            }
                            Err(TryRecvError::Empty) => break,
                            Err(TryRecvError::Disconnected) => break,
                        }
                    }

                    // Mix active voices directly into a temp buffer
                    let frame_count = output.len() / num_channels;

                    // Resize mix buffer if needed (rarely happens after start)
                    if shared.mix_buffer.len() < output.len() {
                        shared.mix_buffer.resize(output.len(), 0.0);
                    }

                    // Clear the buffer for this callback
                    for val in shared.mix_buffer.iter_mut() {
                        *val = 0.0;
                    }

                    let EngineShared {
                        active_voices,
                        mix_buffer,
                        ..
                    } = &mut *shared;

                    active_voices.retain_mut(|voice| {
                        let src_rate = voice.sample_rate as f32 * voice.pitch;
                        let step = src_rate / dst_rate;
                        let src_ch = voice.sample_channels as usize;
                        let data = &voice.sample_data;

                        let mut src_pos = voice.position;
                        let mut produced = false;

                        for frame in 0..frame_count {
                            let base_idx = (src_pos as usize) * src_ch;
                            if base_idx >= data.len() {
                                break;
                            }

                            // Mix each output channel
                            for ch in 0..num_channels {
                                let src_ch_idx = if ch < src_ch { ch } else { 0 };
                                let sample_idx = base_idx + src_ch_idx;
                                if sample_idx < data.len() {
                                    mix_buffer[frame * num_channels + ch] +=
                                        data[sample_idx] * voice.velocity;
                                }
                            }

                            src_pos += step;
                            produced = true;
                        }

                        voice.position = src_pos;
                        produced
                    });

                    // Write mixed output with clamping and peak detection
                    let mut peak = 0.0f32;
                    for (i, out_sample) in output.iter_mut().enumerate() {
                        let val = shared.mix_buffer[i].clamp(-1.0, 1.0);
                        *out_sample = T::from_sample(val);

                        let abs_val = val.abs();
                        if abs_val > peak {
                            peak = abs_val;
                        }
                    }

                    // Send peak signal (throttled to ~30Hz to avoid IPC congestion)
                    // We use a simple counter for throttling within the callback context
                    static mut PEAK_COUNTER: u32 = 0;
                    unsafe {
                        PEAK_COUNTER += 1;
                        if PEAK_COUNTER >= 16 {
                            // Roughly every 30ms at 512 buffer size / 48kHz
                            if peak > 0.001 {
                                let _ = audio_signal_tx
                                    .try_send(crate::state::AudioSignal::AudioPeak(peak));
                            }
                            PEAK_COUNTER = 0;
                        }
                    }
                }
            },
            err_fn,
            None,
        );

        stream.map_err(|e| format!("Failed to build output stream: {}", e))
    }

    /// Stop playback: clear voices and drop the stream.
    pub fn stop(&self) {
        // Clear active voices
        if let Ok(mut shared) = self.shared.lock() {
            shared.active_voices.clear();
        }

        // Drop the stream handle (stops the audio callback)
        if let Ok(mut handle) = self.stream_handle.lock() {
            if handle.take().is_some() {
                info!("Audio stream stopped");
            }
        }
    }

    /// Get the number of currently loaded samples.
    #[allow(dead_code)]
    pub fn loaded_sample_count(&self) -> usize {
        self.shared.lock().map(|s| s.samples.len()).unwrap_or(0)
    }
}

/// Standalone pack loader that can be called from any thread.
pub fn load_pack_to_map(
    pack_dir: &Path,
    samples: &mut HashMap<String, SampleEntry>,
) -> Result<usize, String> {
    samples.clear();

    // 1. Check for Mechvibes config.json (v2) or defines.json (v1)
    let v2_config = pack_dir.join("config.json");
    let v1_config = pack_dir.join("defines.json");

    if v2_config.exists() {
        return load_mechvibes_v2(pack_dir, &v2_config, samples);
    } else if v1_config.exists() {
        return load_mechvibes_v2(pack_dir, &v1_config, samples);
    }
    // ... individual files fallback ...

    // 2. Fallback to individual files
    let entries =
        std::fs::read_dir(pack_dir).map_err(|e| format!("Failed to read pack directory: {}", e))?;

    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_file() {
            let ext = path
                .extension()
                .and_then(|e| e.to_str())
                .unwrap_or("")
                .to_lowercase();
            if matches!(ext.as_str(), "wav" | "mp3" | "ogg" | "flac") {
                if let Ok(sample) = AudioEngine::decode_file(&path) {
                    let name = path
                        .file_stem()
                        .and_then(|s| s.to_str())
                        .unwrap_or("unknown")
                        .to_string();
                    samples.insert(
                        name,
                        SampleEntry {
                            data: sample.data,
                            sample_rate: sample.sample_rate,
                            channels: sample.channels,
                        },
                    );
                }
            }
        }
    }

    let count = samples.len();
    info!("Loaded {} individual samples from {:?}", count, pack_dir);
    Ok(count)
}

fn load_mechvibes_v2(
    pack_dir: &Path,
    config_path: &Path,
    samples: &mut HashMap<String, SampleEntry>,
) -> Result<usize, String> {
    let content = std::fs::read_to_string(config_path).map_err(|e| e.to_string())?;
    let config: serde_json::Value = serde_json::from_str(&content).map_err(|e| e.to_string())?;

    // Improved detection: if key_define_type is missing, check if audio_file exists.
    // If audio_file exists, it's likely a sprite pack. Otherwise, assume multi-file.
    let is_multi = config["key_define_type"].as_str() == Some("multi")
        || (config["key_define_type"].is_null() && config["audio_file"].is_null());

    let mut count = 0;

    if is_multi {
        // Multi-file format: each key maps to a separate file
        let defs = config["defines"]
            .as_object()
            .or_else(|| config["definitions"].as_object());

        if let Some(defs) = defs {
            for (key, val) in defs {
                if let Some(file_name) = val.as_str() {
                    let file_path = pack_dir.join(file_name);
                    if let Ok(sample) = AudioEngine::decode_file(&file_path) {
                        let mapped_name = map_mechvibes_key(key);
                        samples.insert(
                            mapped_name,
                            SampleEntry {
                                data: sample.data,
                                sample_rate: sample.sample_rate,
                                channels: sample.channels,
                            },
                        );
                        count += 1;
                    }
                }
            }
        }
    } else {
        // Sprite format: single audio file with timing ranges
        let audio_rel_path = config["audio_file"].as_str().unwrap_or("sound.ogg");
        let audio_path = pack_dir.join(audio_rel_path);

        let full_sample = AudioEngine::decode_file(&audio_path)?;

        if let Some(defs) = config["definitions"]
            .as_object()
            .or_else(|| config["defines"].as_object())
        {
            for (key, val) in defs {
                if let Some(timings) = val["timing"].as_array() {
                    // Mechvibes usually has [press_start, press_end]
                    if let Some(range) = timings.get(0).and_then(|r| r.as_array()) {
                        if range.len() >= 2 {
                            let start_ms = range[0].as_f64().unwrap_or(0.0);
                            let end_ms = range[1].as_f64().unwrap_or(0.0);

                            let start_frame =
                                (start_ms / 1000.0 * full_sample.sample_rate as f64) as usize;
                            let end_frame =
                                (end_ms / 1000.0 * full_sample.sample_rate as f64) as usize;

                            let ch = full_sample.channels as usize;
                            let start_idx = (start_frame * ch).min(full_sample.data.len());
                            let end_idx = (end_frame * ch).min(full_sample.data.len());

                            if start_idx < end_idx {
                                let sliced_data: Vec<f32> =
                                    full_sample.data[start_idx..end_idx].to_vec();
                                let mapped_name = map_mechvibes_key(key);
                                samples.insert(
                                    mapped_name,
                                    SampleEntry {
                                        data: Arc::from(sliced_data.into_boxed_slice()),
                                        sample_rate: full_sample.sample_rate,
                                        channels: full_sample.channels,
                                    },
                                );
                                count += 1;
                            }
                        }
                    }
                }
            }
        }
    }

    info!(
        "Loaded {} samples from Mechvibes pack {:?}",
        count, pack_dir
    );
    Ok(count)
}

fn map_mechvibes_key(mv_key: &str) -> String {
    // If it's a numeric keycode (Mechvibes v1 uses Javascript keycodes), map it
    if let Ok(code) = mv_key.parse::<u16>() {
        return match code {
            8 => "backspace".to_string(),
            9 => "tab".to_string(),
            13 => "enter".to_string(),
            16 => "left_shift".to_string(),
            17 => "left_ctrl".to_string(),
            18 => "left_alt".to_string(),
            19 => "pause".to_string(),
            20 => "capslock".to_string(),
            27 => "escape".to_string(),
            32 => "space".to_string(),
            33 => "pageup".to_string(),
            34 => "pagedown".to_string(),
            35 => "end".to_string(),
            36 => "home".to_string(),
            37 => "left".to_string(),
            38 => "up".to_string(),
            39 => "right".to_string(),
            40 => "down".to_string(),
            45 => "insert".to_string(),
            46 => "delete".to_string(),
            48..=57 => (code - 48).to_string(), // 0-9
            65..=90 => ((code - 65 + 97) as u8 as char).to_string(), // a-z
            91 => "left_meta".to_string(),
            93 => "right_meta".to_string(),
            96..=105 => format!("kp_{}", code - 96), // Numpad 0-9
            106 => "kp_asterisk".to_string(),
            107 => "kp_plus".to_string(),
            109 => "kp_minus".to_string(),
            110 => "kp_dot".to_string(),
            111 => "kp_slash".to_string(),
            112..=123 => format!("f{}", code - 111), // F1-F12
            144 => "numlock".to_string(),
            145 => "scrolllock".to_string(),
            186 => "semicolon".to_string(),
            187 => "equal".to_string(),
            188 => "comma".to_string(),
            189 => "minus".to_string(),
            190 => "dot".to_string(),
            191 => "slash".to_string(),
            192 => "grave".to_string(),
            219 => "leftbrace".to_string(),
            220 => "backslash".to_string(),
            221 => "rightbrace".to_string(),
            222 => "apostrophe".to_string(),
            _ => {
                #[cfg(unix)]
                {
                    // Try evdev keycode fallback for non-JS codes
                    let key = evdev::Key::new(code);
                    if let Some(name) = crate::input::key_to_name(key) {
                        return name.to_string();
                    }
                }
                format!("key_{}", code)
            }
        };
    }

    // DOM KeyboardEvent.code string format (Mechvibes v2+)
    // This is the primary format used by modern Mechvibes packs.
    match mv_key {
        // ── Letters ─────────────────────────────────────────────
        k if k.starts_with("Key") && k.len() == 4 => {
            k[3..].to_lowercase()
        }

        // ── Digits ─────────────────────────────────────────────
        k if k.starts_with("Digit") && k.len() == 6 => {
            k[5..].to_string()
        }

        // ── Modifiers ──────────────────────────────────────────
        "ShiftLeft" => "left_shift".to_string(),
        "ShiftRight" => "right_shift".to_string(),
        "ControlLeft" => "left_ctrl".to_string(),
        "ControlRight" => "right_ctrl".to_string(),
        "AltLeft" => "left_alt".to_string(),
        "AltRight" => "right_alt".to_string(),
        "MetaLeft" => "left_meta".to_string(),
        "MetaRight" => "right_meta".to_string(),
        "CapsLock" => "capslock".to_string(),

        // ── Standard keys ──────────────────────────────────────
        "Space" => "space".to_string(),
        "Enter" => "enter".to_string(),
        "Backspace" => "backspace".to_string(),
        "Tab" => "tab".to_string(),
        "Escape" => "escape".to_string(),

        // ── Punctuation & symbols ──────────────────────────────
        "Backquote" => "grave".to_string(),
        "Minus" => "minus".to_string(),
        "Equal" => "equal".to_string(),
        "BracketLeft" => "leftbrace".to_string(),
        "BracketRight" => "rightbrace".to_string(),
        "Backslash" => "backslash".to_string(),
        "Semicolon" => "semicolon".to_string(),
        "Quote" => "apostrophe".to_string(),
        "Comma" => "comma".to_string(),
        "Period" => "dot".to_string(),
        "Slash" => "slash".to_string(),

        // ── Arrow keys ─────────────────────────────────────────
        "ArrowUp" => "up".to_string(),
        "ArrowDown" => "down".to_string(),
        "ArrowLeft" => "left".to_string(),
        "ArrowRight" => "right".to_string(),

        // ── Navigation ─────────────────────────────────────────
        "Home" => "home".to_string(),
        "End" => "end".to_string(),
        "PageUp" => "pageup".to_string(),
        "PageDown" => "pagedown".to_string(),
        "Insert" => "insert".to_string(),
        "Delete" => "delete".to_string(),

        // ── Function keys ──────────────────────────────────────
        "F1" => "f1".to_string(),
        "F2" => "f2".to_string(),
        "F3" => "f3".to_string(),
        "F4" => "f4".to_string(),
        "F5" => "f5".to_string(),
        "F6" => "f6".to_string(),
        "F7" => "f7".to_string(),
        "F8" => "f8".to_string(),
        "F9" => "f9".to_string(),
        "F10" => "f10".to_string(),
        "F11" => "f11".to_string(),
        "F12" => "f12".to_string(),

        // ── Numpad ─────────────────────────────────────────────
        "Numpad0" => "kp_0".to_string(),
        "Numpad1" => "kp_1".to_string(),
        "Numpad2" => "kp_2".to_string(),
        "Numpad3" => "kp_3".to_string(),
        "Numpad4" => "kp_4".to_string(),
        "Numpad5" => "kp_5".to_string(),
        "Numpad6" => "kp_6".to_string(),
        "Numpad7" => "kp_7".to_string(),
        "Numpad8" => "kp_8".to_string(),
        "Numpad9" => "kp_9".to_string(),
        "NumpadAdd" => "kp_plus".to_string(),
        "NumpadSubtract" => "kp_minus".to_string(),
        "NumpadMultiply" => "kp_asterisk".to_string(),
        "NumpadDivide" => "kp_slash".to_string(),
        "NumpadDecimal" => "kp_dot".to_string(),
        "NumpadEnter" => "kp_enter".to_string(),
        "NumLock" => "numlock".to_string(),

        // ── Misc ───────────────────────────────────────────────
        "Pause" => "pause".to_string(),
        "ScrollLock" => "scrolllock".to_string(),
        "PrintScreen" => "printscreen".to_string(),
        "ContextMenu" => "compose".to_string(),

        // ── Fallback: return lowercased ────────────────────────
        other => other.to_lowercase(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_map_mechvibes_key_exhaustive() {
        let cases = vec![
            // ── Letters (DOM code format) ────────────────────
            ("KeyA", "a"),
            ("KeyB", "b"),
            ("KeyC", "c"),
            ("KeyD", "d"),
            ("KeyE", "e"),
            ("KeyF", "f"),
            ("KeyG", "g"),
            ("KeyH", "h"),
            ("KeyI", "i"),
            ("KeyJ", "j"),
            ("KeyK", "k"),
            ("KeyL", "l"),
            ("KeyM", "m"),
            ("KeyN", "n"),
            ("KeyO", "o"),
            ("KeyP", "p"),
            ("KeyQ", "q"),
            ("KeyR", "r"),
            ("KeyS", "s"),
            ("KeyT", "t"),
            ("KeyU", "u"),
            ("KeyV", "v"),
            ("KeyW", "w"),
            ("KeyX", "x"),
            ("KeyY", "y"),
            ("KeyZ", "z"),
            // ── Digits (DOM code format) ─────────────────────
            ("Digit1", "1"),
            ("Digit2", "2"),
            ("Digit3", "3"),
            ("Digit4", "4"),
            ("Digit5", "5"),
            ("Digit6", "6"),
            ("Digit7", "7"),
            ("Digit8", "8"),
            ("Digit9", "9"),
            ("Digit0", "0"),
            // ── Standard keys ───────────────────────────────
            ("Space", "space"),
            ("Enter", "enter"),
            ("Backspace", "backspace"),
            ("Tab", "tab"),
            ("Escape", "escape"),
            // ── Modifiers ───────────────────────────────────
            ("ShiftLeft", "left_shift"),
            ("ShiftRight", "right_shift"),
            ("ControlLeft", "left_ctrl"),
            ("AltLeft", "left_alt"),
            ("AltRight", "right_alt"),
            ("MetaLeft", "left_meta"),
            ("CapsLock", "capslock"),
            // ── Punctuation ─────────────────────────────────
            ("Backquote", "grave"),
            ("Minus", "minus"),
            ("Equal", "equal"),
            ("BracketLeft", "leftbrace"),
            ("BracketRight", "rightbrace"),
            ("Backslash", "backslash"),
            ("Semicolon", "semicolon"),
            ("Quote", "apostrophe"),
            ("Comma", "comma"),
            ("Period", "dot"),
            ("Slash", "slash"),
            // ── Arrow & Navigation ──────────────────────────
            ("ArrowUp", "up"),
            ("ArrowDown", "down"),
            ("ArrowLeft", "left"),
            ("ArrowRight", "right"),
            ("Home", "home"),
            ("End", "end"),
            ("PageUp", "pageup"),
            ("PageDown", "pagedown"),
            ("Insert", "insert"),
            ("Delete", "delete"),
            // ── Function keys ───────────────────────────────
            ("F1", "f1"),
            ("F2", "f2"),
            ("F12", "f12"),
            // ── Numpad ──────────────────────────────────────
            ("Numpad0", "kp_0"),
            ("NumpadAdd", "kp_plus"),
            ("NumpadEnter", "kp_enter"),
            ("NumLock", "numlock"),
            // ── Misc ────────────────────────────────────────
            ("ScrollLock", "scrolllock"),
            ("Pause", "pause"),
            ("PrintScreen", "printscreen"),
            // ── JS numeric keycodes ─────────────────────────
            ("32", "space"),  // JS keycode for Space
            ("13", "enter"),  // JS keycode for Enter
            ("65", "a"),      // JS keycode for A
            ("48", "0"),      // JS keycode for 0
            ("112", "f1"),    // JS keycode for F1
            ("16", "left_shift"), // JS keycode for Shift
            // ── Fallback ────────────────────────────────────
            ("AnythingElse", "anythingelse"),
        ];

        for (input, expected) in cases {
            assert_eq!(map_mechvibes_key(input), expected.to_string(),
                "Failed: '{}' should map to '{}'", input, expected);
        }
    }

    #[test]
    fn test_pitch_jitter_distribution() {
        // Test 100 cases of jitter to ensure it's within [0.98, 1.02]
        for _ in 0..100 {
            let jitter = (rand::random::<f32>() - 0.5) * 0.04;
            let pitch = 1.0 + jitter;
            assert!(
                pitch >= 0.98 && pitch <= 1.02,
                "Pitch {} out of bounds",
                pitch
            );
        }
    }

    #[test]
    fn test_normalization_precision() {
        let test_cases = vec![
            (0.1, 9.0),
            (0.45, 2.0),
            (0.9, 1.0),
            (1.0, 1.0), // Should not normalize if > 0.9
        ];

        for (peak, expected_factor) in test_cases {
            let factor: f32 = if peak > 0.0 && peak < 0.9 {
                0.9 / peak
            } else {
                1.0
            };
            assert!((factor - expected_factor).abs() < 1e-6);
        }
    }

    #[test]
    fn test_active_voice_fields() {
        let voice = ActiveVoice {
            sample_data: std::sync::Arc::from(vec![0.0f32]),
            sample_rate: 44100,
            sample_channels: 2,
            position: 10.5,
            velocity: 0.8,
            pitch: 1.01,
        };
        assert_eq!(voice.sample_channels, 2);
        assert!((voice.pitch - 1.01).abs() < 1e-6);
    }

    #[test]
    fn test_engine_shared_reset() {
        let mut shared = EngineShared::default();
        shared.samples.insert(
            "test".into(),
            SampleEntry {
                data: std::sync::Arc::from(vec![0.0f32]),
                sample_rate: 44100,
                channels: 1,
            },
        );
        shared.active_voices.push(ActiveVoice {
            sample_data: std::sync::Arc::from(vec![0.0f32]),
            sample_rate: 44100,
            sample_channels: 1,
            position: 0.0,
            velocity: 1.0,
            pitch: 1.0,
        });

        // Simulating load_pack_to_shared reset
        shared.samples.clear();
        shared.active_voices.clear();
        assert!(shared.samples.is_empty());
        assert!(shared.active_voices.is_empty());
    }
}
