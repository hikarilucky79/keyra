use include_dir::{include_dir, Dir};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use tracing::{info, warn};

static PACKS_DIR: Dir = include_dir!("$CARGO_MANIFEST_DIR/packs");

pub fn provision_default_packs() {
    let config_dir = match dirs::config_dir() {
        Some(dir) => dir,
        None => return,
    };

    let keyra_packs = config_dir.join("keyra").join("packs");

    // Garantir que a pasta de packs existe
    if let Err(e) = fs::create_dir_all(&keyra_packs) {
        warn!("Failed to create packs directory: {}", e);
        return;
    }

    // Provisionar cada pack embutido se ele ainda não existir no disco
    for entry in PACKS_DIR.entries() {
        if let Some(dir) = entry.as_dir() {
            let pack_name = dir.path().file_name().unwrap().to_str().unwrap();
            let target_pack_path = keyra_packs.join(pack_name);

            if !target_pack_path.exists() {
                info!("Provisioning default sound pack: {}", pack_name);
                if let Err(e) = extract_dir(dir, &target_pack_path) {
                    warn!("Failed to provision pack {}: {}", pack_name, e);
                }
            }
        }
    }
}

fn extract_dir(dir: &Dir, target: &PathBuf) -> std::io::Result<()> {
    fs::create_dir_all(target)?;
    for entry in dir.entries() {
        match entry {
            include_dir::DirEntry::Dir(d) => {
                extract_dir(d, &target.join(d.path().file_name().unwrap()))?;
            }
            include_dir::DirEntry::File(f) => {
                let file_path = target.join(f.path().file_name().unwrap());
                fs::write(file_path, f.contents())?;
            }
        }
    }
    Ok(())
}

#[derive(Debug, Deserialize)]
struct KlickityConfig {
    volume: Option<f32>,
    theme: Option<String>,
    #[serde(default)]
    enabled: bool,
}

#[derive(Debug, Serialize, Deserialize)]
struct KeyraConfig {
    volume: f32,
    pack: String,
    enabled: bool,
    latency_target_ms: u64,
}

pub fn migrate_klickity_if_needed() {
    let config_dir = match dirs::config_dir() {
        Some(dir) => dir,
        None => return,
    };

    let klickity_dir = config_dir.join("klickity");
    let keyra_dir = config_dir.join("keyra");

    // Se o klickity não existe, não há o que migrar
    if !klickity_dir.exists() {
        return;
    }

    // Se o Keyra já foi configurado, não sobrescrever
    let keyra_config_path = keyra_dir.join("config.json");
    if keyra_config_path.exists() {
        return;
    }

    info!("Klickity legacy configuration detected. Starting migration to Keyra...");

    // 1. Criar diretório do Keyra
    if let Err(e) = fs::create_dir_all(keyra_dir.join("packs")) {
        warn!("Failed to create Keyra directory structure: {}", e);
        return;
    }

    // 2. Migrar configurações
    let klickity_config_path = klickity_dir.join("config.json");
    if klickity_config_path.exists() {
        match fs::read_to_string(&klickity_config_path) {
            Ok(content) => match serde_json::from_str::<KlickityConfig>(&content) {
                Ok(klickity_cfg) => {
                    let new_cfg = KeyraConfig {
                        volume: klickity_cfg.volume.unwrap_or(0.7),
                        pack: klickity_cfg.theme.unwrap_or_else(|| "default".to_string()),
                        enabled: klickity_cfg.enabled,
                        latency_target_ms: 10,
                    };

                    if let Ok(new_content) = serde_json::to_string_pretty(&new_cfg) {
                        if let Err(e) = fs::write(&keyra_config_path, new_content) {
                            warn!("Failed to write migrated Keyra config: {}", e);
                        } else {
                            info!("Migrated config.json successfully.");
                        }
                    }
                }
                Err(e) => warn!("Failed to parse Klickity config: {}", e),
            },
            Err(e) => warn!("Failed to read Klickity config: {}", e),
        }
    }

    // 3. Migrar temas (Klickity usava "themes", Keyra usa "packs")
    let klickity_themes = klickity_dir.join("themes");
    let keyra_packs = keyra_dir.join("packs");

    if klickity_themes.exists() {
        if let Ok(entries) = fs::read_dir(klickity_themes) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    let dir_name = path.file_name().unwrap();
                    let target_dir = keyra_packs.join(dir_name);

                    if !target_dir.exists() {
                        if let Err(e) = copy_dir_all(&path, &target_dir) {
                            warn!("Failed to migrate theme {:?}: {}", dir_name, e);
                        } else {
                            info!("Migrated sound pack: {:?}", dir_name);
                        }
                    }
                }
            }
        }
    }

    info!("Klickity migration completed.");
}

fn copy_dir_all(src: &PathBuf, dst: &PathBuf) -> std::io::Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let ty = entry.file_type()?;
        if ty.is_dir() {
            copy_dir_all(&entry.path(), &dst.join(entry.file_name()))?;
        } else {
            fs::copy(entry.path(), dst.join(entry.file_name()))?;
        }
    }
    Ok(())
}
