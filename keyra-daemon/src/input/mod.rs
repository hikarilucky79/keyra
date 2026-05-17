//! Input handling subsystem for Keyra daemon.

use crate::state::StateManager;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tracing::{info, warn};

// ═══════════════════════════════════════════════════════════════════
//  🐧 Linux Implementation (evdev + epoll)
// ═══════════════════════════════════════════════════════════════════
#[cfg(unix)]
use evdev::{Device, EventType, InputEventKind, Key};
#[cfg(unix)]
use std::os::fd::AsRawFd;
#[cfg(unix)]
use tracing::error;

#[cfg(unix)]
pub fn key_to_name(key: Key) -> Option<&'static str> {
    match key {
        // ── Row 0: Escape & Function keys ──────────────────────────
        Key::KEY_ESC => Some("escape"),
        Key::KEY_F1 => Some("f1"),
        Key::KEY_F2 => Some("f2"),
        Key::KEY_F3 => Some("f3"),
        Key::KEY_F4 => Some("f4"),
        Key::KEY_F5 => Some("f5"),
        Key::KEY_F6 => Some("f6"),
        Key::KEY_F7 => Some("f7"),
        Key::KEY_F8 => Some("f8"),
        Key::KEY_F9 => Some("f9"),
        Key::KEY_F10 => Some("f10"),
        Key::KEY_F11 => Some("f11"),
        Key::KEY_F12 => Some("f12"),

        // ── Row 1: Number row ──────────────────────────────────────
        Key::KEY_GRAVE => Some("grave"),
        Key::KEY_1 => Some("1"),
        Key::KEY_2 => Some("2"),
        Key::KEY_3 => Some("3"),
        Key::KEY_4 => Some("4"),
        Key::KEY_5 => Some("5"),
        Key::KEY_6 => Some("6"),
        Key::KEY_7 => Some("7"),
        Key::KEY_8 => Some("8"),
        Key::KEY_9 => Some("9"),
        Key::KEY_0 => Some("0"),
        Key::KEY_MINUS => Some("minus"),
        Key::KEY_EQUAL => Some("equal"),
        Key::KEY_BACKSPACE => Some("backspace"),

        // ── Row 2: QWERTY ──────────────────────────────────────────
        Key::KEY_TAB => Some("tab"),
        Key::KEY_Q => Some("q"),
        Key::KEY_W => Some("w"),
        Key::KEY_E => Some("e"),
        Key::KEY_R => Some("r"),
        Key::KEY_T => Some("t"),
        Key::KEY_Y => Some("y"),
        Key::KEY_U => Some("u"),
        Key::KEY_I => Some("i"),
        Key::KEY_O => Some("o"),
        Key::KEY_P => Some("p"),
        Key::KEY_LEFTBRACE => Some("leftbrace"),
        Key::KEY_RIGHTBRACE => Some("rightbrace"),
        Key::KEY_BACKSLASH => Some("backslash"),

        // ── Row 3: Home row ────────────────────────────────────────
        Key::KEY_CAPSLOCK => Some("capslock"),
        Key::KEY_A => Some("a"),
        Key::KEY_S => Some("s"),
        Key::KEY_D => Some("d"),
        Key::KEY_F => Some("f"),
        Key::KEY_G => Some("g"),
        Key::KEY_H => Some("h"),
        Key::KEY_J => Some("j"),
        Key::KEY_K => Some("k"),
        Key::KEY_L => Some("l"),
        Key::KEY_SEMICOLON => Some("semicolon"),
        Key::KEY_APOSTROPHE => Some("apostrophe"),
        Key::KEY_ENTER => Some("enter"),

        // ── Row 4: Bottom row ──────────────────────────────────────
        Key::KEY_LEFTSHIFT => Some("left_shift"),
        Key::KEY_Z => Some("z"),
        Key::KEY_X => Some("x"),
        Key::KEY_C => Some("c"),
        Key::KEY_V => Some("v"),
        Key::KEY_B => Some("b"),
        Key::KEY_N => Some("n"),
        Key::KEY_M => Some("m"),
        Key::KEY_COMMA => Some("comma"),
        Key::KEY_DOT => Some("dot"),
        Key::KEY_SLASH => Some("slash"),
        Key::KEY_RIGHTSHIFT => Some("right_shift"),

        // ── Row 5: Bottom modifiers ────────────────────────────────
        Key::KEY_LEFTCTRL => Some("left_ctrl"),
        Key::KEY_LEFTMETA => Some("left_meta"),
        Key::KEY_LEFTALT => Some("left_alt"),
        Key::KEY_SPACE => Some("space"),
        Key::KEY_RIGHTALT => Some("right_alt"),
        Key::KEY_RIGHTMETA => Some("right_meta"),
        Key::KEY_RIGHTCTRL => Some("right_ctrl"),

        // ── Navigation cluster ─────────────────────────────────────
        Key::KEY_INSERT => Some("insert"),
        Key::KEY_DELETE => Some("delete"),
        Key::KEY_HOME => Some("home"),
        Key::KEY_END => Some("end"),
        Key::KEY_PAGEUP => Some("pageup"),
        Key::KEY_PAGEDOWN => Some("pagedown"),

        // ── Arrow keys ─────────────────────────────────────────────
        Key::KEY_UP => Some("up"),
        Key::KEY_DOWN => Some("down"),
        Key::KEY_LEFT => Some("left"),
        Key::KEY_RIGHT => Some("right"),

        // ── Numpad ─────────────────────────────────────────────────
        Key::KEY_NUMLOCK => Some("numlock"),
        Key::KEY_KPSLASH => Some("kp_slash"),
        Key::KEY_KPASTERISK => Some("kp_asterisk"),
        Key::KEY_KPMINUS => Some("kp_minus"),
        Key::KEY_KPPLUS => Some("kp_plus"),
        Key::KEY_KPENTER => Some("kp_enter"),
        Key::KEY_KPDOT => Some("kp_dot"),
        Key::KEY_KP0 => Some("kp_0"),
        Key::KEY_KP1 => Some("kp_1"),
        Key::KEY_KP2 => Some("kp_2"),
        Key::KEY_KP3 => Some("kp_3"),
        Key::KEY_KP4 => Some("kp_4"),
        Key::KEY_KP5 => Some("kp_5"),
        Key::KEY_KP6 => Some("kp_6"),
        Key::KEY_KP7 => Some("kp_7"),
        Key::KEY_KP8 => Some("kp_8"),
        Key::KEY_KP9 => Some("kp_9"),

        // ── Misc ───────────────────────────────────────────────────
        Key::KEY_PAUSE => Some("pause"),

        _ => None,
    }
}

#[cfg(unix)]
pub struct InputMonitor {
    state_manager: Arc<StateManager>,
    running: Arc<AtomicBool>,
    thread_handle: Option<std::thread::JoinHandle<()>>,
}

#[cfg(unix)]
impl InputMonitor {
    pub fn new(state_manager: Arc<StateManager>) -> Self {
        Self {
            state_manager,
            running: Arc::new(AtomicBool::new(false)),
            thread_handle: None,
        }
    }

    fn find_keyboard_devices() -> Vec<Device> {
        let mut keyboards = Vec::new();
        let devices = evdev::enumerate();

        for (path, device) in devices {
            let name = device.name().unwrap_or("unknown");
            let supported_events = device.supported_events();
            if !supported_events.contains(EventType::KEY) {
                continue;
            }

            let supported_keys = match device.supported_keys() {
                Some(keys) => keys,
                None => continue,
            };

            let has_alpha_keys = supported_keys.contains(Key::KEY_A)
                && supported_keys.contains(Key::KEY_Z)
                && supported_keys.contains(Key::KEY_SPACE);

            if has_alpha_keys {
                info!("Found keyboard: '{}' at {}", name, path.display());
                keyboards.push(device);
            }
        }

        if keyboards.is_empty() {
            warn!("No keyboard input devices found. Ensure user is in 'input' group");
        } else {
            info!("Discovered {} keyboard device(s)", keyboards.len());
        }

        keyboards
    }

    pub fn start(&mut self) {
        if self.running.load(Ordering::SeqCst) {
            warn!("Input monitor already running");
            return;
        }

        let running = self.running.clone();
        let state_manager = self.state_manager.clone();
        running.store(true, Ordering::SeqCst);

        let handle = std::thread::Builder::new()
            .name("keyra-input".into())
            .spawn(move || {
                info!("Input monitor thread started");
                Self::input_loop(&running, &state_manager);
                info!("Input monitor thread stopped");
            })
            .expect("Failed to spawn input monitor thread");

        self.thread_handle = Some(handle);
    }

    fn input_loop(running: &AtomicBool, state_manager: &StateManager) {
        let mut devices = Self::find_keyboard_devices();
        if devices.is_empty() {
            error!("No keyboard devices could be opened. Input monitoring disabled.");
            return;
        }

        for device in &devices {
            let fd = device.as_raw_fd();
            let flags = unsafe { libc::fcntl(fd, libc::F_GETFL) };
            if flags < 0 {
                continue;
            }
            let _ = unsafe { libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) };
        }

        let epoll_fd = unsafe { libc::epoll_create1(0) };
        if epoll_fd < 0 {
            error!("Failed to create epoll");
            return;
        }

        for (idx, device) in devices.iter().enumerate() {
            let fd = device.as_raw_fd();
            let mut event = libc::epoll_event {
                events: libc::EPOLLIN as u32,
                u64: idx as u64,
            };
            let _ = unsafe { libc::epoll_ctl(epoll_fd, libc::EPOLL_CTL_ADD, fd, &mut event) };
        }

        let mut epoll_events = vec![libc::epoll_event { events: 0, u64: 0 }; devices.len().max(1)];

        while running.load(Ordering::Relaxed) {
            let nfds = unsafe {
                libc::epoll_wait(
                    epoll_fd,
                    epoll_events.as_mut_ptr(),
                    epoll_events.len() as i32,
                    100,
                )
            };

            if nfds < 0 {
                let err = std::io::Error::last_os_error();
                if err.raw_os_error() == Some(libc::EINTR) {
                    continue;
                }
                break;
            }

            for i in 0..nfds as usize {
                let device_idx = epoll_events[i].u64 as usize;
                if device_idx < devices.len() {
                    Self::drain_device_events(&mut devices[device_idx], state_manager);
                }
            }
        }

        unsafe {
            let _ = libc::close(epoll_fd);
        }
    }

    fn drain_device_events(device: &mut Device, state_manager: &StateManager) {
        static mut CTRL_HELD: bool = false;
        static mut ALT_HELD: bool = false;

        loop {
            match device.fetch_events() {
                Ok(events) => {
                    for event in events {
                        if let InputEventKind::Key(key) = event.kind() {
                            let value = event.value();
                            match key {
                                Key::KEY_LEFTCTRL | Key::KEY_RIGHTCTRL => unsafe { CTRL_HELD = value != 0 },
                                Key::KEY_LEFTALT | Key::KEY_RIGHTALT => unsafe { ALT_HELD = value != 0 },
                                _ => {}
                            }

                            if value == 1 {
                                unsafe {
                                    if CTRL_HELD && ALT_HELD {
                                        match key {
                                            Key::KEY_M => {
                                                let enabled = state_manager.get_state().enabled;
                                                state_manager.set_enabled(!enabled);
                                                continue;
                                            }
                                            Key::KEY_RIGHT => {
                                                let state = state_manager.get_state();
                                                if let Some(pos) = state.available_packs.iter().position(|p| p == &state.pack) {
                                                    let next = (pos + 1) % state.available_packs.len();
                                                    state_manager.set_pack(state.available_packs[next].clone());
                                                }
                                                continue;
                                            }
                                            Key::KEY_LEFT => {
                                                let state = state_manager.get_state();
                                                if let Some(pos) = state.available_packs.iter().position(|p| p == &state.pack) {
                                                    let prev = if pos == 0 { state.available_packs.len() - 1 } else { pos - 1 };
                                                    state_manager.set_pack(state.available_packs[prev].clone());
                                                }
                                                continue;
                                            }
                                            _ => {}
                                        }
                                    }
                                }

                                if let Some(key_name) = key_to_name(key) {
                                    state_manager.trigger_play(key_name.to_string(), 1.0);
                                } else {
                                    state_manager.trigger_play(format!("key_{}", key.code()), 1.0);
                                }
                            }
                        }
                    }
                    break;
                }
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    break;
                }
                Err(_) => {
                    break;
                }
            }
        }
    }

    pub fn stop(&mut self) {
        if self.running.swap(false, Ordering::SeqCst) {
            info!("Stopping input monitor...");
        }
        if let Some(handle) = self.thread_handle.take() {
            let _ = handle.join();
        }
    }
}

#[cfg(unix)]
impl Drop for InputMonitor {
    fn drop(&mut self) {
        self.stop();
    }
}

// ═══════════════════════════════════════════════════════════
//  🪟 Windows / Stub Implementation
// ═══════════════════════════════════════════════════════════
#[cfg(not(unix))]
pub struct InputMonitor {
    running: Arc<AtomicBool>,
}

#[cfg(not(unix))]
impl InputMonitor {
    pub fn new(_state_manager: Arc<StateManager>) -> Self {
        Self {
            running: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn start(&mut self) {
        self.running.store(true, Ordering::SeqCst);
        warn!("Input monitoring via evdev/epoll is not supported on Windows. Keypress sounds will rely on direct UI messages.");
    }

    pub fn stop(&mut self) {
        self.running.store(false, Ordering::SeqCst);
    }
}