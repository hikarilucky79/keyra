//! IPC client for testing and inter-process communication with the keyra daemon.

use crate::ipc::{Command, Message};
use anyhow::Result;
use std::path::PathBuf;
use std::time::Duration;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::UnixStream;

/// IPC client that connects to the keyra daemon via Unix Domain Socket.
pub struct IpcClient {
    stream: UnixStream,
}

impl IpcClient {
    /// Connect to the daemon at the given socket path.
    pub async fn connect(socket_path: PathBuf) -> Result<Self> {
        // Wait for socket to become available
        for _attempt in 0..10 {
            match UnixStream::connect(&socket_path).await {
                Ok(stream) => {
                    return Ok(Self { stream });
                }
                Err(_) => {
                    tokio::time::sleep(Duration::from_millis(100)).await;
                }
            }
        }
        Err(anyhow::anyhow!(
            "Failed to connect after retries: {}",
            socket_path.display()
        ))
    }

    /// Send a command to the daemon and return the message ID.
    pub async fn send_command(&mut self, cmd: Command) -> Result<uuid::Uuid> {
        let msg = Message::new_command(cmd);
        let id = msg.id;

        let json = serde_json::to_vec(&msg)?;
        let len_bytes = (json.len() as u32).to_le_bytes();

        self.stream.write_all(&len_bytes).await?;
        self.stream.write_all(&json).await?;
        self.stream.flush().await?;

        Ok(id)
    }

    /// Read a single message from the daemon.
    pub async fn recv_message(&mut self) -> Result<Option<Message>> {
        let mut len_buf = [0u8; 4];
        // read_exact returns Result<usize> or Result<()> depending on version
        match self.stream.read_exact(&mut len_buf).await {
            Ok(_n) => {}
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(None),
            Err(e) => return Err(e.into()),
        };

        let json_len = u32::from_le_bytes(len_buf) as usize;
        if json_len > 65536 || json_len == 0 {
            return Ok(None);
        }

        let mut json_buf = vec![0u8; json_len];
        self.stream.read_exact(&mut json_buf).await?;

        let msg: Message = serde_json::from_slice(&json_buf)?;
        Ok(Some(msg))
    }

    /// Get reconnection support - close and reconnect.
    pub async fn reconnect(socket_path: PathBuf) -> Result<Self> {
        tokio::time::sleep(Duration::from_millis(500)).await;
        Self::connect(socket_path).await
    }

    /// Check if the connection is still alive.
    pub fn is_connected(&self) -> bool {
        self.stream.peer_addr().is_ok()
    }
}