use crate::state::StateManager;
use active_win_pos_rs::get_active_window;
use std::sync::Arc;
use std::time::Duration;
use tracing::debug;

pub struct WindowMonitor {
    state_manager: Arc<StateManager>,
}

impl WindowMonitor {
    pub fn new(state_manager: Arc<StateManager>) -> Self {
        Self { state_manager }
    }

    pub fn start(&self, mut shutdown_rx: tokio::sync::broadcast::Receiver<()>) {
        let state_manager = self.state_manager.clone();

        std::thread::spawn(move || {
            let mut last_app = String::new();
            let mut base_pack = state_manager.get_state().pack.clone();

            loop {
                // Check for shutdown
                match shutdown_rx.try_recv() {
                    Ok(_) | Err(tokio::sync::broadcast::error::TryRecvError::Closed) => {
                        break;
                    }
                    _ => {}
                }

                // Sleep between polls
                std::thread::sleep(Duration::from_millis(500));

                let current_state = state_manager.get_state();
                
                // If there are no app profiles, don't do anything to save resources
                if current_state.app_profiles.is_empty() {
                    // But if we had an override applied, we need to revert it
                    if !last_app.is_empty() {
                        last_app.clear();
                    }
                    continue;
                }

                match get_active_window() {
                    Ok(active_window) => {
                        let app_name = active_window.app_name.to_lowercase();
                        
                        if app_name != last_app {
                            debug!("Active window changed to: {}", app_name);
                            last_app = app_name.clone();

                            if let Some(pack) = current_state.app_profiles.get(&app_name) {
                                debug!("Applying per-app profile '{}' for app '{}'", pack, app_name);
                                // Remember what the user's base pack was before we override
                                if current_state.pack != *pack {
                                    base_pack = current_state.pack.clone();
                                    state_manager.set_pack(pack.clone());
                                }
                            } else {
                                // Revert to base pack if we changed it due to a profile
                                if current_state.pack != base_pack {
                                    debug!("Reverting to base pack: {}", base_pack);
                                    state_manager.set_pack(base_pack.clone());
                                } else {
                                    // Base pack could have been changed manually by the user
                                    base_pack = current_state.pack.clone();
                                }
                            }
                        }
                    }
                    Err(()) => {
                        // Failed to get active window (could be Wayland permission issue or lock screen)
                        // Do not revert to avoid toggling when window is temporarily lost
                    }
                }
            }
        });
    }
}
