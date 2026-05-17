//! Integration tests for Keyra daemon IPC and state management.

use keyra_daemon::ipc::{Command, Event, Message, MessagePayload};

#[test]
fn test_command_serialization() {
    let cmd = Command::Play {
        key: "a".to_string(),
        velocity: 0.8,
    };
    let msg = Message::new_command(cmd);
    let json = serde_json::to_string(&msg).unwrap();
    let deserialized: Message = serde_json::from_str(&json).unwrap();

    match deserialized.payload {
        MessagePayload::Command(Command::Play { key, velocity }) => {
            assert_eq!(key, "a");
            assert!((velocity - 0.8).abs() < f32::EPSILON);
        }
        other => panic!("Expected Play command, got {:?}", other),
    }
}

#[test]
fn test_event_serialization() {
    let event = Event::StateUpdated {
        volume: 0.7,
        pack: "default".to_string(),
        enabled: true,
        playing: false,
        clients_connected: 2,
        uptime_ms: 1000,
        app_profiles: std::collections::HashMap::new(),
        available_packs: vec!["default".to_string()],
        effects: keyra_daemon::ipc::AudioEffects::default(),
    };
    let msg = Message::new_event(event);
    let json = serde_json::to_string(&msg).unwrap();
    let deserialized: Message = serde_json::from_str(&json).unwrap();

    match deserialized.payload {
        MessagePayload::Event(Event::StateUpdated {
            volume,
            pack,
            enabled,
            ..
        }) => {
            assert!((volume - 0.7).abs() < f32::EPSILON);
            assert_eq!(pack, "default");
            assert!(enabled);
        }
        other => panic!("Expected StateUpdated event, got {:?}", other),
    }
}

#[test]
fn test_ping_pong() {
    let nonce = uuid::Uuid::new_v4();
    let cmd = Command::Ping { nonce };
    let msg = Message::new_command(cmd);
    let reply = msg.reply_to(Event::Pong { nonce });

    let json = serde_json::to_string(&reply).unwrap();
    let deserialized: Message = serde_json::from_str(&json).unwrap();

    assert_eq!(deserialized.id, msg.id);
    match deserialized.payload {
        MessagePayload::Event(Event::Pong { nonce: r }) => assert_eq!(r, nonce),
        other => panic!("Expected Pong, got {:?}", other),
    }
}

#[test]
fn test_all_commands_serialize() {
    let commands = vec![
        Message::new_command(Command::Play {
            key: "a".into(),
            velocity: 1.0,
        }),
        Message::new_command(Command::Stop),
        Message::new_command(Command::Enable),
        Message::new_command(Command::Disable),
        Message::new_command(Command::SetVolume { volume: 0.5 }),
        Message::new_command(Command::SetPack {
            name: "test".into(),
        }),
        Message::new_command(Command::Status),
        Message::new_command(Command::Ping {
            nonce: uuid::Uuid::new_v4(),
        }),
        Message::new_command(Command::ReloadConfig),
    ];

    for cmd in commands {
        let json = serde_json::to_string(&cmd).expect("Failed to serialize command");
        let deserialized: Message = serde_json::from_str(&json).expect("Failed to deserialize");
        assert_eq!(deserialized.id, cmd.id);
    }
}

#[test]
fn test_message_id_uniqueness() {
    let ids: Vec<_> = (0..100)
        .map(|_| Message::new_command(Command::Status).id)
        .collect();

    let unique: std::collections::HashSet<_> = ids.iter().collect();
    assert_eq!(unique.len(), 100, "All 100 message IDs should be unique");
}

#[test]
fn test_config_defaults() {
    let cfg = keyra_daemon::state::Config::default();
    assert!((cfg.volume - 0.7).abs() < f32::EPSILON);
    assert_eq!(cfg.pack, "default");
    assert!(cfg.enabled);
    assert_eq!(cfg.latency_target_ms, 10);
}

#[test]
fn test_app_state_default() {
    let state = keyra_daemon::state::AppState::default();
    assert!((state.volume - 0.7).abs() < f32::EPSILON);
    assert_eq!(state.pack, "default");
    assert!(state.enabled);
    assert!(!state.playing);
    assert_eq!(state.clients_connected, 0);
}

// ── Phase 2: Audio Engine Tests ──────────────────────────────────

#[test]
fn test_audio_sample_decode() {
    // The gen_pack binary should have created this file
    let pack_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("packs/default");
    let default_wav = pack_dir.join("default.wav");

    if !default_wav.exists() {
        eprintln!("Skipping test_audio_sample_decode: default.wav not found (run gen_pack first)");
        return;
    }

    let sample = keyra_daemon::audio::AudioEngine::decode_file(&default_wav)
        .expect("Failed to decode default.wav");

    assert!(
        !sample.data.is_empty(),
        "Decoded PCM data should not be empty"
    );
    assert_eq!(sample.sample_rate, 44100, "Expected 44100Hz sample rate");
    assert_eq!(sample.channels, 1, "Expected mono");
    assert_eq!(sample.name, "default", "Sample name should be 'default'");

    // Verify all samples are in valid range
    for &s in sample.data.iter() {
        assert!(s >= -1.0 && s <= 1.0, "Sample out of range: {}", s);
    }

    // Verify it's approximately 25ms long (44100 * 0.025 ≈ 1102 samples)
    let expected_len = (44100.0 * 0.025) as usize;
    assert!(
        (sample.data.len() as i32 - expected_len as i32).unsigned_abs() < 10,
        "Expected ~{} samples, got {}",
        expected_len,
        sample.data.len()
    );
}

#[test]
fn test_default_pack_exists() {
    let pack_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("packs/default");

    if !pack_dir.exists() {
        eprintln!("Skipping test_default_pack_exists: pack dir not found (run gen_pack first)");
        return;
    }

    // Should contain at least default.wav
    let wav_files: Vec<_> = std::fs::read_dir(&pack_dir)
        .expect("Failed to read pack dir")
        .flatten()
        .filter(|e| {
            e.path()
                .extension()
                .and_then(|x| x.to_str())
                .map_or(false, |ext| ext == "wav")
        })
        .collect();

    assert!(
        !wav_files.is_empty(),
        "Default pack should contain at least one WAV file"
    );

    // Verify expected files exist
    let names: Vec<String> = wav_files
        .iter()
        .filter_map(|e| {
            e.path()
                .file_stem()
                .and_then(|s| s.to_str())
                .map(String::from)
        })
        .collect();

    assert!(
        names.contains(&"default".to_string()),
        "Missing default.wav"
    );
    assert!(names.contains(&"space".to_string()), "Missing space.wav");
    assert!(names.contains(&"enter".to_string()), "Missing enter.wav");
    assert!(
        names.contains(&"backspace".to_string()),
        "Missing backspace.wav"
    );
}

#[test]
fn test_all_pack_samples_decode() {
    let pack_dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("packs/default");

    if !pack_dir.exists() {
        eprintln!("Skipping: pack dir not found");
        return;
    }

    for entry in std::fs::read_dir(&pack_dir).unwrap().flatten() {
        let path = entry.path();
        if path.extension().and_then(|e| e.to_str()) == Some("wav") {
            let sample = keyra_daemon::audio::AudioEngine::decode_file(&path)
                .unwrap_or_else(|e| panic!("Failed to decode {:?}: {}", path, e));

            assert!(!sample.data.is_empty(), "{:?} decoded to empty", path);
            assert!(sample.sample_rate > 0, "{:?} has zero sample rate", path);
            assert!(sample.channels > 0, "{:?} has zero channels", path);
        }
    }
}

#[test]
fn test_audio_config_defaults() {
    let config = keyra_daemon::audio::AudioConfig::default();
    assert!(
        (config.volume - 0.7).abs() < f32::EPSILON,
        "Default volume should be 0.7"
    );
    assert_eq!(config.latency_ms, 10, "Default latency should be 10ms");
    assert!(
        config.output_device.is_none(),
        "Default device should be None"
    );
}

#[test]
fn test_audio_signal_types() {
    use keyra_daemon::state::AudioSignal;

    // Verify AudioSignal variants can be constructed
    let vol = AudioSignal::VolumeChanged(0.5);
    let reload = AudioSignal::ReloadPack {
        name: "test".to_string(),
        path: std::path::PathBuf::from("/tmp/test"),
    };
    let stop = AudioSignal::Stop;

    // Verify Debug formatting works
    assert!(format!("{:?}", vol).contains("0.5"));
    assert!(format!("{:?}", reload).contains("test"));
    assert!(format!("{:?}", stop).contains("Stop"));
}

// ── Phase 3: Input Integration Tests ─────────────────────────────

#[test]
fn test_keycode_mapping_critical_keys() {
    use evdev::Key;
    use keyra_daemon::input::key_to_name;

    // These were incorrect in the original implementation — verify the fix
    assert_eq!(
        key_to_name(Key::KEY_BACKSPACE),
        Some("backspace"),
        "Backspace should be keycode 14"
    );
    assert_eq!(key_to_name(Key::KEY_Q), Some("q"), "Q should be keycode 16");
    assert_eq!(key_to_name(Key::KEY_W), Some("w"), "W should be keycode 17");
    assert_eq!(key_to_name(Key::KEY_E), Some("e"), "E should be keycode 18");
    assert_eq!(
        key_to_name(Key::KEY_TAB),
        Some("tab"),
        "Tab should be keycode 15"
    );
    assert_eq!(
        key_to_name(Key::KEY_ENTER),
        Some("enter"),
        "Enter should be keycode 28"
    );
    assert_eq!(
        key_to_name(Key::KEY_SPACE),
        Some("space"),
        "Space should be keycode 57"
    );
}

#[test]
fn test_keycode_mapping_alphabetic() {
    use evdev::Key;
    use keyra_daemon::input::key_to_name;

    let alpha_keys = [
        (Key::KEY_A, "a"),
        (Key::KEY_B, "b"),
        (Key::KEY_C, "c"),
        (Key::KEY_D, "d"),
        (Key::KEY_E, "e"),
        (Key::KEY_F, "f"),
        (Key::KEY_G, "g"),
        (Key::KEY_H, "h"),
        (Key::KEY_I, "i"),
        (Key::KEY_J, "j"),
        (Key::KEY_K, "k"),
        (Key::KEY_L, "l"),
        (Key::KEY_M, "m"),
        (Key::KEY_N, "n"),
        (Key::KEY_O, "o"),
        (Key::KEY_P, "p"),
        (Key::KEY_Q, "q"),
        (Key::KEY_R, "r"),
        (Key::KEY_S, "s"),
        (Key::KEY_T, "t"),
        (Key::KEY_U, "u"),
        (Key::KEY_V, "v"),
        (Key::KEY_W, "w"),
        (Key::KEY_X, "x"),
        (Key::KEY_Y, "y"),
        (Key::KEY_Z, "z"),
    ];

    for (key, expected) in &alpha_keys {
        assert_eq!(
            key_to_name(*key),
            Some(*expected),
            "Key {:?} should map to '{}'",
            key,
            expected
        );
    }
}

#[test]
fn test_keycode_mapping_modifiers() {
    use evdev::Key;
    use keyra_daemon::input::key_to_name;

    assert_eq!(key_to_name(Key::KEY_LEFTCTRL), Some("left_ctrl"));
    assert_eq!(key_to_name(Key::KEY_RIGHTCTRL), Some("right_ctrl"));
    assert_eq!(key_to_name(Key::KEY_LEFTALT), Some("left_alt"));
    assert_eq!(key_to_name(Key::KEY_RIGHTALT), Some("right_alt"));
    assert_eq!(key_to_name(Key::KEY_LEFTSHIFT), Some("left_shift"));
    assert_eq!(key_to_name(Key::KEY_RIGHTSHIFT), Some("right_shift"));
    assert_eq!(key_to_name(Key::KEY_LEFTMETA), Some("left_meta"));
    assert_eq!(key_to_name(Key::KEY_CAPSLOCK), Some("capslock"));
}

#[test]
fn test_keycode_mapping_numpad() {
    use evdev::Key;
    use keyra_daemon::input::key_to_name;

    assert_eq!(key_to_name(Key::KEY_KP0), Some("kp_0"));
    assert_eq!(key_to_name(Key::KEY_KP9), Some("kp_9"));
    assert_eq!(key_to_name(Key::KEY_KPENTER), Some("kp_enter"));
    assert_eq!(key_to_name(Key::KEY_KPPLUS), Some("kp_plus"));
}

#[test]
fn test_keycode_mapping_navigation() {
    use evdev::Key;
    use keyra_daemon::input::key_to_name;

    assert_eq!(key_to_name(Key::KEY_UP), Some("up"));
    assert_eq!(key_to_name(Key::KEY_DOWN), Some("down"));
    assert_eq!(key_to_name(Key::KEY_LEFT), Some("left"));
    assert_eq!(key_to_name(Key::KEY_RIGHT), Some("right"));
    assert_eq!(key_to_name(Key::KEY_HOME), Some("home"));
    assert_eq!(key_to_name(Key::KEY_END), Some("end"));
    assert_eq!(key_to_name(Key::KEY_PAGEUP), Some("pageup"));
    assert_eq!(key_to_name(Key::KEY_PAGEDOWN), Some("pagedown"));
    assert_eq!(key_to_name(Key::KEY_DELETE), Some("delete"));
}

#[test]
fn test_keycode_unknown_returns_none() {
    use evdev::Key;
    use keyra_daemon::input::key_to_name;

    // KEY_UNKNOWN (0) should not be mapped
    assert_eq!(key_to_name(Key::KEY_RESERVED), None);
    // Some obscure multimedia key shouldn't be mapped
    assert_eq!(key_to_name(Key::KEY_MSDOS), None);
}
