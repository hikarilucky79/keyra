use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use tracing::info;
use zip::ZipArchive;

/// Imports a soundpack from a zip file into the destination directory.
/// Returns the name of the imported pack on success, or an error message.
pub fn import_soundpack(zip_path: &str, dest_dir: &PathBuf) -> Result<String, String> {
    let file = fs::File::open(zip_path).map_err(|e| format!("Failed to open zip file: {}", e))?;
    let mut archive =
        ZipArchive::new(file).map_err(|e| format!("Failed to read zip archive: {}", e))?;

    // We need to determine the pack name.
    // It's either the name of the single root folder inside the zip,
    // or the name of the zip file itself if files are directly at the root.
    let zip_path_obj = Path::new(zip_path);
    let fallback_name = zip_path_obj
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("imported_pack")
        .to_string();

    let mut pack_name = fallback_name.clone();
    let mut has_audio_files = false;

    // Check structure and find root folder if any
    if archive.len() > 0 {
        if let Ok(first_file) = archive.by_index(0) {
            let name = first_file.name();
            if let Some(first_component) = Path::new(name).components().next() {
                if let std::path::Component::Normal(os_str) = first_component {
                    pack_name = os_str.to_string_lossy().to_string();
                }
            }
        }
    }

    let target_dir = dest_dir.join(&pack_name);

    // If pack already exists, remove it for re-install
    if target_dir.exists() {
        info!("Removing existing pack '{}' for re-install", pack_name);
        let _ = fs::remove_dir_all(&target_dir);
    }

    fs::create_dir_all(&target_dir)
        .map_err(|e| format!("Failed to create pack directory: {}", e))?;

    for i in 0..archive.len() {
        let mut file = archive
            .by_index(i)
            .map_err(|e| format!("Error reading file in zip: {}", e))?;
        let outpath = match file.enclosed_name() {
            Some(path) => {
                // If the zip contains a root folder, we want to strip it if we are already
                // placing it into `target_dir` which is named after that folder.
                // Alternatively, we just extract everything as-is into `dest_dir`.
                // Actually, extracting into `dest_dir` is safer if the zip already contains the folder.
                dest_dir.join(path)
            }
            None => continue,
        };

        if (*file.name()).ends_with('/') {
            fs::create_dir_all(&outpath)
                .map_err(|e| format!("Failed to create directory {:?}: {}", outpath, e))?;
        } else {
            if let Some(p) = outpath.parent() {
                if !p.exists() {
                    fs::create_dir_all(&p)
                        .map_err(|e| format!("Failed to create directory {:?}: {}", p, e))?;
                }
            }
            let mut outfile = fs::File::create(&outpath)
                .map_err(|e| format!("Failed to create file {:?}: {}", outpath, e))?;
            io::copy(&mut file, &mut outfile)
                .map_err(|e| format!("Failed to extract file {:?}: {}", outpath, e))?;

            // Check if it's an audio file
            if let Some(ext) = outpath.extension().and_then(|s| s.to_str()) {
                let ext_lower = ext.to_lowercase();
                if matches!(ext_lower.as_str(), "wav" | "mp3" | "ogg" | "flac") {
                    has_audio_files = true;
                }
            }
        }
    }

    if !has_audio_files {
        // Cleanup if no audio files were found
        let _ = fs::remove_dir_all(&target_dir);
        return Err("Invalid soundpack: No audio files (.wav, .mp3) found.".to_string());
    }

    info!("Successfully imported soundpack: {}", pack_name);
    Ok(pack_name)
}
