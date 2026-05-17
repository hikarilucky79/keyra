use crate::ipc::{Event, Message};
use anyhow::{anyhow, Result};
use serde::{Deserialize, Serialize};
use tracing::{info, warn};

const GITHUB_API_URL: &str = "https://api.github.com/repos/keyra-org/keyra/releases/latest";

#[derive(Debug, Serialize, Deserialize)]
struct GitHubRelease {
    tag_name: String,
    body: String,
    assets: Vec<GitHubAsset>,
}

#[derive(Debug, Serialize, Deserialize)]
struct GitHubAsset {
    name: String,
    browser_download_url: String,
}

pub struct UpdateManager {
    client: reqwest::Client,
    ipc_tx: tokio::sync::broadcast::Sender<Message>,
    current_version: String,
}

impl UpdateManager {
    pub fn new(ipc_tx: tokio::sync::broadcast::Sender<Message>, version: String) -> Self {
        Self {
            client: reqwest::Client::builder()
                .user_agent("keyra-daemon")
                .build()
                .unwrap_or_default(),
            ipc_tx,
            current_version: version,
        }
    }

    pub fn clone_handle(self: &std::sync::Arc<Self>) -> std::sync::Arc<Self> {
        std::sync::Arc::clone(self)
    }

    pub fn ipc_tx(&self) -> &tokio::sync::broadcast::Sender<Message> {
        &self.ipc_tx
    }

    pub async fn check_for_updates(&self) -> Result<()> {
        info!("Checking for updates at {}", GITHUB_API_URL);

        let response = self.client.get(GITHUB_API_URL).send().await?;

        if !response.status().is_success() {
            return Err(anyhow!(
                "Failed to check for updates: HTTP {}",
                response.status()
            ));
        }

        let release: GitHubRelease = response.json().await?;
        let latest_version = release.tag_name.trim_start_matches('v');

        if self.is_newer(latest_version) {
            info!(
                "New version available: {} (current: {})",
                latest_version, self.current_version
            );

            // Find the appropriate asset (e.g., AppImage or binary)
            let download_url = release
                .assets
                .iter()
                .find(|a| a.name.contains("linux") || a.name.contains("AppImage"))
                .map(|a| a.browser_download_url.clone())
                .unwrap_or_default();

            let _ = self.ipc_tx.send(Message::new_event(Event::UpdateAvailable {
                version: latest_version.to_string(),
                changelog: release.body,
                url: download_url,
            }));
        } else {
            info!("Already on the latest version: {}", self.current_version);
        }

        Ok(())
    }

    fn is_newer(&self, latest: &str) -> bool {
        // Simple semantic version comparison
        let current_parts: Vec<u32> = self
            .current_version
            .split('.')
            .filter_map(|s| s.parse().ok())
            .collect();
        let latest_parts: Vec<u32> = latest.split('.').filter_map(|s| s.parse().ok()).collect();

        for (c, l) in current_parts.iter().zip(latest_parts.iter()) {
            if l > c {
                return true;
            }
            if c > l {
                return false;
            }
        }

        latest_parts.len() > current_parts.len()
    }

    pub async fn perform_update(&self, _url: &str) -> Result<()> {
        warn!("Self-update is not fully implemented for standard Linux installs. Please update via your package manager.");
        // In a real AppImage scenario, we would download and replace the binary here.
        Ok(())
    }
}
