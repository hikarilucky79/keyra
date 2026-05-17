//! IPC server for Keyra daemon.

use crate::state::StateManager;
use anyhow::{Result};
use std::path::PathBuf;
use std::sync::mpsc;
use std::sync::Arc;
use tokio::sync::broadcast;

/// Events from the IPC server to the async runtime.
#[allow(dead_code)]
pub enum ServerEvent {
    ClientConnected(usize),
    ClientDisconnected(usize),
}

// ═══════════════════════════════════════════════════════════
//  🐧 Linux / Unix Implementation (Unix Domain Sockets)
// ═══════════════════════════════════════════════════════════
#[cfg(unix)]
use crate::ipc::{Command, Event, Message, MessagePayload};
#[cfg(unix)]
use anyhow::Context;
#[cfg(unix)]
use nix::unistd::unlink;
#[cfg(unix)]
use std::collections::HashMap;
#[cfg(unix)]
use std::io::{self, Read, Write};
#[cfg(unix)]
use std::os::unix::net::{UnixListener, UnixStream};
#[cfg(unix)]
use std::time::{Duration, Instant};
#[cfg(unix)]
use crate::packs::import_soundpack;

#[cfg(unix)]
const STALE_SOCKET_MAX_AGE_SECS: u64 = 5;

#[cfg(unix)]
pub struct IpcServer {
    socket_path: PathBuf,
    fallback_socket_path: PathBuf,
    state_manager: Arc<StateManager>,
    update_manager: Arc<crate::updater::UpdateManager>,
    shutdown_rx: broadcast::Receiver<()>,
    import_session: Arc<parking_lot::Mutex<Option<crate::importer::ImportSession>>>,
}

#[cfg(unix)]
impl IpcServer {
    pub fn new(
        socket_path: PathBuf,
        fallback_socket_path: PathBuf,
        state_manager: Arc<StateManager>,
        update_manager: Arc<crate::updater::UpdateManager>,
        shutdown_rx: broadcast::Receiver<()>,
    ) -> Self {
        Self {
            socket_path,
            fallback_socket_path,
            state_manager,
            update_manager,
            shutdown_rx,
            import_session: Arc::new(parking_lot::Mutex::new(None)),
        }
    }

    fn cleanup_stale_socket(&self, path: &std::path::Path) {
        if path.exists() {
            tracing::info!("Removing stale socket: {}", path.display());
            if let Err(e) = unlink(path) {
                tracing::warn!("Failed to remove stale socket: {}", e);
            }
        }
    }

    fn try_read_message(stream: &mut UnixStream) -> io::Result<Option<Message>> {
        let mut len_buf = [0u8; 4];
        match stream.read_exact(&mut len_buf) {
            Ok(()) => {}
            Err(e)
                if e.kind() == io::ErrorKind::WouldBlock
                    || e.kind() == io::ErrorKind::TimedOut =>
            {
                return Ok(None);
            }
            Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => return Ok(None),
            Err(e) => return Err(e),
        }

        let json_len = u32::from_le_bytes(len_buf) as usize;
        if json_len > 1048576 || json_len == 0 {
            return Ok(None);
        }

        let mut json_buf = vec![0u8; json_len];
        match stream.read_exact(&mut json_buf) {
            Ok(()) => {}
            Err(e) if e.kind() == io::ErrorKind::WouldBlock || e.kind() == io::ErrorKind::TimedOut => {
                stream.set_nonblocking(false)?;
                let res = stream.read_exact(&mut json_buf);
                stream.set_nonblocking(true)?;
                res?;
            }
            Err(e) => return Err(e),
        }

        let msg: Message = serde_json::from_slice(&json_buf)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        Ok(Some(msg))
    }

    fn send_message(stream: &mut UnixStream, msg: &Message) -> io::Result<()> {
        let json = serde_json::to_vec(msg)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        let len_bytes = (json.len() as u32).to_le_bytes();
        stream.write_all(&len_bytes)?;
        stream.write_all(&json)?;
        stream.flush()
    }

    fn dispatch_command(
        state_manager: &Arc<StateManager>,
        update_manager: &Arc<crate::updater::UpdateManager>,
        import_session: &Arc<parking_lot::Mutex<Option<crate::importer::ImportSession>>>,
        tokio_handle: &tokio::runtime::Handle,
        cmd: Command,
    ) -> Option<Event> {
        match cmd {
            Command::Play { key, velocity } => {
                state_manager.trigger_play(key, velocity);
            }
            Command::Stop => {
                state_manager.stop();
            }
            Command::Enable => {
                state_manager.set_enabled(true);
            }
            Command::Disable => {
                state_manager.set_enabled(false);
            }
            Command::SetVolume { volume } => {
                state_manager.set_volume(volume.clamp(0.0, 1.0));
            }
            Command::SetPack { name } => {
                state_manager.set_pack(name);
            }
            Command::Status => {
                let state = state_manager.get_state();
                return Some(Event::StatusResponse {
                    volume: state.volume,
                    pack: state.pack.clone(),
                    enabled: state.enabled,
                    playing: state.playing,
                    clients_connected: 0,
                    latency_ms: 0.0,
                    uptime_ms: 0,
                    app_profiles: state.app_profiles.clone(),
                    available_packs: state.available_packs.clone(),
                    effects: state.effects.clone(),
                });
            }
            Command::Ping { nonce } => {
                return Some(Event::Pong { nonce });
            }
            Command::ReloadConfig => {
                state_manager.reload_config();
            }
            Command::ImportSoundpack { path } => {
                let state = state_manager.get_state();
                match import_soundpack(&path, &state.config.sound_packs_dir) {
                    Ok(pack_name) => {
                        tracing::info!("Imported soundpack: {}", pack_name);
                        state_manager.set_pack(pack_name);
                    }
                    Err(e) => {
                        tracing::error!("Failed to import soundpack: {}", e);
                    }
                }
            }
            Command::SetAppProfile { app_name, pack_name } => {
                state_manager.set_app_profile(app_name, pack_name);
            }
            Command::SavePackConfig { name, config } => {
                if let Err(e) = state_manager.save_pack_config(name, config) {
                    tracing::error!("Failed to save pack config: {}", e);
                }
            }
            Command::CheckUpdate => {
                let updater = update_manager.clone_handle();
                tokio_handle.spawn(async move {
                    if let Err(e) = updater.check_for_updates().await {
                        tracing::error!("Update check failed: {}", e);
                    }
                });
            }
            Command::PerformUpdate => {
                let updater = update_manager.clone_handle();
                tokio_handle.spawn(async move {
                    if let Err(e) = updater.perform_update("").await {
                        tracing::error!("Update failed: {}", e);
                    }
                });
            }
            Command::ImportRequest { path } => {
                let mut session_lock = import_session.lock();
                let mut session = crate::importer::ImportSession::new();
                match session.scan(&path) {
                    Ok(files) => {
                        *session_lock = Some(session);
                        return Some(Event::ImportSessionStarted { files });
                    }
                    Err(e) => return Some(Event::Error { message: e }),
                }
            }
            Command::ImportUpdateMapping { file_id, key } => {
                let mut session_lock = import_session.lock();
                if let Some(session) = session_lock.as_mut() {
                    if let Some(info) = session.files.get_mut(&file_id) {
                        info.inferred_key = key;
                    }
                }
            }
            Command::ImportProcess { name, author } => {
                let import_session_clone = import_session.clone();
                let state_manager_clone = state_manager.clone();
                
                tokio_handle.spawn(async move {
                    let session_opt = import_session_clone.lock().take();
                    if let Some(session) = session_opt {
                        let ipc_tx = state_manager_clone.ipc_tx().clone();
                        let progress_fn = Arc::new(std::sync::Mutex::new(move |p: f32, m: String| {
                            let _ = ipc_tx.send(Message::new_event(Event::ImportProgress { progress: p, message: m }));
                        }));

                        let dest_root = state_manager_clone.get_state().config.sound_packs_dir.clone();
                        match session.process_all(&name, &author, &dest_root, progress_fn) {
                            Ok(pack_name) => {
                                let _ = state_manager_clone.ipc_tx().send(Message::new_event(Event::ImportFinished { pack_name: pack_name.clone() }));
                                state_manager_clone.set_pack(pack_name);
                            }
                            Err(e) => {
                                let _ = state_manager_clone.ipc_tx().send(Message::new_event(Event::Error { message: e }));
                            }
                        }
                    }
                });
            }
            Command::ImportPreview { file_id } => {
                let session_lock = import_session.lock();
                if let Some(session) = session_lock.as_ref() {
                    if let Some(info) = session.files.get(&file_id) {
                        state_manager.trigger_play_direct(&info.original_path);
                    }
                }
            }
            Command::ImportCancel => {
                *import_session.lock() = None;
            }
            Command::PlayDirect { path } => {
                state_manager.trigger_play_direct(std::path::Path::new(&path));
            }
            #[allow(unreachable_patterns)]
            _ => {
                tracing::warn!("Received unhandled or unknown command: {:?}", cmd);
            }
        }
        None
    }

    pub fn run(self) -> Result<mpsc::Receiver<ServerEvent>> {
        self.cleanup_stale_socket(&self.socket_path);
        self.cleanup_stale_socket(&self.fallback_socket_path);

        let (event_tx, event_rx) = mpsc::channel();

        let listener = match UnixListener::bind(&self.socket_path) {
            Ok(l) => {
                tracing::info!("IPC server bound to {}", self.socket_path.display());
                l.set_nonblocking(true)?;
                l
            }
            Err(e) => {
                tracing::warn!(
                    "Failed to bind primary socket ({}): {}, trying fallback",
                    self.socket_path.display(),
                    e
                );
                self.cleanup_stale_socket(&self.fallback_socket_path);
                let l = UnixListener::bind(&self.fallback_socket_path)
                    .context("Failed to bind fallback socket")?;
                l.set_nonblocking(true)?;
                tracing::info!("IPC server bound to fallback path");
                l
            }
        };

        let state_manager = self.state_manager.clone();
        let mut shutdown_rx = self.shutdown_rx;
        let tokio_handle = tokio::runtime::Handle::current();

        std::thread::spawn(move || {
            let mut clients: HashMap<usize, (UnixStream, Instant)> = HashMap::new();
            let mut next_id = 0usize;
            let mut ipc_rx = state_manager.ipc_tx().subscribe();

            loop {
                match shutdown_rx.try_recv() {
                    Ok(_) | Err(tokio::sync::broadcast::error::TryRecvError::Closed) => {
                        tracing::info!("IPC server shutting down");
                        break;
                    }
                    _ => {}
                }

                match listener.accept() {
                    Ok((mut stream, _addr)) => {
                        let id = next_id;
                        next_id += 1;
                        tracing::debug!("New IPC client connected: id={}", id);

                        if stream.set_nonblocking(true).is_err() {
                            continue;
                        }
                        let _ = stream.set_read_timeout(Some(Duration::from_millis(100)));

                        let state = state_manager.get_state();
                        let event = Event::StateUpdated {
                            volume: state.volume,
                            pack: state.pack.clone(),
                            enabled: state.enabled,
                            playing: state.playing,
                            clients_connected: clients.len() + 1,
                            uptime_ms: 0,
                            app_profiles: state.app_profiles.clone(),
                            available_packs: state.available_packs.clone(),
                            effects: state.effects.clone(),
                        };
                        let _ = Self::send_message(&mut stream, &Message::new_event(event));

                        let _ = event_tx.send(ServerEvent::ClientConnected(id));
                        clients.insert(id, (stream, Instant::now()));
                    }
                    Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => {}
                    Err(e) => tracing::warn!("Accept error: {}", e),
                }

                let client_ids: Vec<usize> = clients.keys().cloned().collect();
                let mut dead_clients = Vec::new();

                for id in &client_ids {
                    if let Some((stream, last_seen)) = clients.get_mut(id) {
                        match Self::try_read_message(stream) {
                            Ok(Some(msg)) => {
                                *last_seen = Instant::now();
                                if let MessagePayload::Command(cmd) = msg.payload {
                                    if let Some(resp) = Self::dispatch_command(
                                        &state_manager,
                                        &self.update_manager,
                                        &self.import_session,
                                        &tokio_handle,
                                        cmd,
                                    ) {
                                        let _ = Self::send_message(stream, &Message::new_event(resp));
                                    }
                                }
                            }
                            Ok(None) => {}
                            Err(_) => {
                                dead_clients.push(*id);
                            }
                        }
                    }
                }

                let mut changed = false;
                for id in &dead_clients {
                    clients.remove(id);
                    let _ = event_tx.send(ServerEvent::ClientDisconnected(*id));
                    changed = true;
                }

                let now = Instant::now();
                let stale: Vec<usize> = clients
                    .iter()
                    .filter(|(_, (_, ts))| now.duration_since(*ts).as_secs() > STALE_SOCKET_MAX_AGE_SECS)
                    .map(|(&id, _)| id)
                    .collect();

                for id in &stale {
                    clients.remove(id);
                    let _ = event_tx.send(ServerEvent::ClientDisconnected(*id));
                    changed = true;
                }

                loop {
                    match ipc_rx.try_recv() {
                        Ok(msg) => {
                            for (stream, _) in clients.values_mut() {
                                let _ = Self::send_message(stream, &msg);
                            }
                        }
                        Err(tokio::sync::broadcast::error::TryRecvError::Empty) => break,
                        Err(tokio::sync::broadcast::error::TryRecvError::Closed) => break,
                        Err(tokio::sync::broadcast::error::TryRecvError::Lagged(_)) => {
                            continue;
                        }
                    }
                }

                if changed {
                    state_manager.set_clients_connected(clients.len());
                }

                std::thread::sleep(Duration::from_micros(100));
            }
        });

        Ok(event_rx)
    }
}

// ═══════════════════════════════════════════════════════════
//  🪟 Windows / Stub Implementation
// ═══════════════════════════════════════════════════════════
#[cfg(not(unix))]
pub struct IpcServer {
    shutdown_rx: broadcast::Receiver<()>,
}

#[cfg(not(unix))]
impl IpcServer {
    pub fn new(
        _socket_path: PathBuf,
        _fallback_socket_path: PathBuf,
        _state_manager: Arc<StateManager>,
        _update_manager: Arc<crate::updater::UpdateManager>,
        shutdown_rx: broadcast::Receiver<()>,
    ) -> Self {
        Self { shutdown_rx }
    }

    pub fn run(self) -> Result<mpsc::Receiver<ServerEvent>> {
        let (event_tx, event_rx) = mpsc::channel();
        let mut shutdown_rx = self.shutdown_rx;

        std::thread::spawn(move || {
            tracing::warn!("IPC UDS server is not supported on Windows. Running in background stub mode.");
            loop {
                // Check shutdown signal
                match shutdown_rx.try_recv() {
                    Ok(_) | Err(tokio::sync::broadcast::error::TryRecvError::Closed) => {
                        tracing::info!("IPC stub server shutting down");
                        break;
                    }
                    _ => {}
                }
                std::thread::sleep(std::time::Duration::from_millis(500));
            }
            // Keep compiler happy about unused sender
            drop(event_tx);
        });

        Ok(event_rx)
    }
}