use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use regex::Regex;
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use hound::{WavSpec, WavWriter};
use rubato::{Resampler, SincFixedIn, SincInterpolationType, SincInterpolationParameters, WindowFunction};
use tracing::warn;
use crate::ipc::ImportFile;
use uuid::Uuid;

pub struct ImportSession {
    pub files: HashMap<String, ImportFileInfo>,
    pub temp_dir: PathBuf,
}

pub struct ImportFileInfo {
    pub id: String,
    pub original_path: PathBuf,
    pub inferred_key: String,
    pub waveform: Vec<f32>,
}

impl ImportSession {
    pub fn new() -> Self {
        let temp_dir = std::env::temp_dir().join(format!("keyra_import_{}", Uuid::new_v4()));
        let _ = fs::create_dir_all(&temp_dir);
        Self {
            files: HashMap::new(),
            temp_dir,
        }
    }

    pub fn scan(&mut self, source_path: &str) -> Result<Vec<ImportFile>, String> {
        self.files.clear();
        let path = Path::new(source_path);

        if !path.exists() {
            return Err(format!("Path does not exist: {}", source_path));
        }

        let mut audio_paths = Vec::new();

        if path.is_file() && source_path.to_lowercase().ends_with(".zip") {
            // Extract ZIP to temp dir and scan
            self.extract_zip(path)?;
            self.collect_audio_files(&self.temp_dir, &mut audio_paths);
        } else if path.is_dir() {
            self.collect_audio_files(path, &mut audio_paths);
        } else {
            return Err("Unsupported file format. Please use a folder or a ZIP file.".to_string());
        }

        if audio_paths.is_empty() {
            return Err("No audio files found in the source.".to_string());
        }

        let mut result = Vec::new();
        for p in audio_paths {
            let id = Uuid::new_v4().to_string();
            let inferred_key = infer_key_from_filename(&p);
            
            // Generate basic waveform (envelope)
            let waveform = generate_waveform(&p).unwrap_or_default();

            let info = ImportFileInfo {
                id: id.clone(),
                original_path: p.clone(),
                inferred_key: inferred_key.clone(),
                waveform: waveform.clone(),
            };

            result.push(ImportFile {
                id: id.clone(),
                original_path: p.to_string_lossy().to_string(),
                inferred_key,
                waveform,
            });

            self.files.insert(id, info);
        }

        Ok(result)
    }

    fn extract_zip(&self, zip_path: &Path) -> Result<(), String> {
        let file = fs::File::open(zip_path).map_err(|e| e.to_string())?;
        let mut archive = zip::ZipArchive::new(file).map_err(|e| e.to_string())?;

        for i in 0..archive.len() {
            let mut file = archive.by_index(i).map_err(|e| e.to_string())?;
            let outpath = match file.enclosed_name() {
                Some(path) => self.temp_dir.join(path),
                None => continue,
            };

            if (*file.name()).ends_with('/') {
                fs::create_dir_all(&outpath).map_err(|e| e.to_string())?;
            } else {
                if let Some(p) = outpath.parent() {
                    if !p.exists() {
                        fs::create_dir_all(&p).map_err(|e| e.to_string())?;
                    }
                }
                let mut outfile = fs::File::create(&outpath).map_err(|e| e.to_string())?;
                std::io::copy(&mut file, &mut outfile).map_err(|e| e.to_string())?;
            }
        }
        Ok(())
    }

    fn collect_audio_files(&self, dir: &Path, paths: &mut Vec<PathBuf>) {
        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                let p = entry.path();
                if p.is_dir() {
                    self.collect_audio_files(&p, paths);
                } else if let Some(ext) = p.extension().and_then(|e| e.to_str()) {
                    let ext_lower = ext.to_lowercase();
                    if matches!(ext_lower.as_str(), "wav" | "mp3" | "ogg" | "flac") {
                        paths.push(p);
                    }
                }
            }
        }
    }

    pub fn process_all(&self, name: &str, author: &str, dest_root: &Path, progress_tx: Arc<Mutex<dyn Fn(f32, String) + Send>>) -> Result<String, String> {
        let pack_name = name.replace("/", "_").replace(" ", "_");
        let pack_dir = dest_root.join(&pack_name);
        let sounds_dir = pack_dir.join("sounds");

        if pack_dir.exists() {
            let _ = fs::remove_dir_all(&pack_dir);
        }
        fs::create_dir_all(&sounds_dir).map_err(|e| e.to_string())?;

        let total = self.files.len() as f32;
        let mut current = 0.0;

        let mut manifest_sounds = HashMap::new();

        for (id, info) in &self.files {
            current += 1.0;
            let progress = current / total;
            
            let filename = format!("{}.wav", id);
            let output_path = sounds_dir.join(&filename);

            {
                let tx = progress_tx.lock().unwrap();
                tx(progress, format!("Processing {}...", info.original_path.file_name().unwrap_or_default().to_string_lossy()));
            }

            match process_audio_file(&info.original_path, &output_path) {
                Ok(_) => {
                    manifest_sounds.insert(info.inferred_key.clone(), format!("sounds/{}", filename));
                }
                Err(e) => {
                    warn!("Failed to process {:?}: {}", info.original_path, e);
                }
            }
        }

        // Generate manifest
        let manifest = serde_json::json!({
            "name": name,
            "author": author,
            "version": "1.0.0",
            "sounds": manifest_sounds
        });

        let manifest_path = pack_dir.join("manifest.json");
        fs::write(manifest_path, serde_json::to_string_pretty(&manifest).unwrap()).map_err(|e| e.to_string())?;

        Ok(pack_name)
    }
}

fn infer_key_from_filename(path: &Path) -> String {
    let name = path.file_stem().and_then(|s| s.to_str()).unwrap_or("").to_lowercase();
    
    let rules = vec![
        (Regex::new(r"enter|return").unwrap(), "enter"),
        (Regex::new(r"space|bar").unwrap(), "space"),
        (Regex::new(r"shift|sft").unwrap(), "shift"),
        (Regex::new(r"backspace|del|delete").unwrap(), "backspace"),
        (Regex::new(r"tab").unwrap(), "tab"),
        (Regex::new(r"esc|escape").unwrap(), "escape"),
        (Regex::new(r"ctrl|control").unwrap(), "control"),
        (Regex::new(r"alt|opt").unwrap(), "alt"),
        (Regex::new(r"super|win|cmd|meta").unwrap(), "super"),
        (Regex::new(r"caps").unwrap(), "capslock"),
        (Regex::new(r"up").unwrap(), "up"),
        (Regex::new(r"down").unwrap(), "down"),
        (Regex::new(r"left").unwrap(), "left"),
        (Regex::new(r"right").unwrap(), "right"),
        (Regex::new(r"click|key|default|press").unwrap(), "default"),
    ];

    for (re, key) in rules {
        if re.is_match(&name) {
            return key.to_string();
        }
    }

    "default".to_string()
}

fn generate_waveform(path: &Path) -> Result<Vec<f32>, String> {
    // Basic waveform generation: peak envelope with 100 points
    let (samples, _, _) = decode_to_pcm_with_meta(path)?;
    let points = 100;
    let chunk_size = (samples.len() / points).max(1);
    let mut waveform = Vec::with_capacity(points);

    for chunk in samples.chunks(chunk_size) {
        let max = chunk.iter().map(|s| s.abs()).fold(0.0f32, |a, b| a.max(b));
        waveform.push(max);
    }

    while waveform.len() < points {
        waveform.push(0.0);
    }

    Ok(waveform)
}

fn process_audio_file(input_path: &Path, output_path: &Path) -> Result<(), String> {
    // 1. Decode
    let (mut samples, sample_rate, channels) = decode_to_pcm_with_meta(input_path)?;

    // 2. Mono downmix
    if channels > 1 {
        let mut mono = Vec::with_capacity(samples.len() / channels as usize);
        for chunk in samples.chunks(channels as usize) {
            let sum: f32 = chunk.iter().sum();
            mono.push(sum / channels as f32);
        }
        samples = mono;
    }

    // 3. Trim silence
    let threshold = 0.001; // -60dB approx
    let start = samples.iter().position(|&s| s.abs() > threshold).unwrap_or(0);
    let end = samples.iter().rposition(|&s| s.abs() > threshold).unwrap_or(samples.len());
    if start < end {
        samples = samples[start..end].to_vec();
    }

    // 4. Normalize
    let peak = samples.iter().map(|s| s.abs()).fold(0.0f32, |a, b| a.max(b));
    if peak > 0.0 {
        let factor = 0.9 / peak;
        for s in samples.iter_mut() {
            *s *= factor;
        }
    }

    // 5. Resample to 48kHz
    if sample_rate != 48000 {
        let params = SincInterpolationParameters {
            sinc_len: 256,
            f_cutoff: 0.95,
            interpolation: SincInterpolationType::Linear,
            window: WindowFunction::BlackmanHarris2,
            oversampling_factor: 128,
        };
        let mut resampler = SincFixedIn::<f32>::new(
            48000 as f64 / sample_rate as f64,
            2.0,
            params,
            samples.len(),
            1,
        ).map_err(|e| e.to_string())?;

        let resampled = resampler.process(&[samples], None).map_err(|e| e.to_string())?;
        samples = resampled[0].clone();
    }

    // 6. Encode to 16-bit WAV
    let spec = WavSpec {
        channels: 1,
        sample_rate: 48000,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };

    let mut writer = WavWriter::create(output_path, spec).map_err(|e| e.to_string())?;
    for &sample in &samples {
        let s = (sample * 32767.0) as i16;
        writer.write_sample(s).map_err(|e| e.to_string())?;
    }
    writer.finalize().map_err(|e| e.to_string())?;

    Ok(())
}

fn decode_to_pcm_with_meta(path: &Path) -> Result<(Vec<f32>, u32, u16), String> {
    let src = fs::File::open(path).map_err(|e| e.to_string())?;
    let mss = MediaSourceStream::new(Box::new(src), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .map_err(|e| e.to_string())?;

    let mut format = probed.format;
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
        .ok_or("No supported audio track found")?;

    let sample_rate = track.codec_params.sample_rate.unwrap_or(44100);
    let channels = track.codec_params.channels.map(|c| c.count() as u16).unwrap_or(2);

    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &DecoderOptions::default())
        .map_err(|e| e.to_string())?;

    let track_id = track.id;
    let mut samples = Vec::new();

    loop {
        let packet = match format.next_packet() {
            Ok(packet) => packet,
            Err(Error::IoError(ref e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(e) => return Err(e.to_string()),
        };

        if packet.track_id() != track_id {
            continue;
        }

        let decoded = decoder.decode(&packet).map_err(|e| e.to_string())?;
        let mut sample_buf = SampleBuffer::<f32>::new(decoded.capacity() as u64, *decoded.spec());
        sample_buf.copy_interleaved_ref(decoded);
        samples.extend_from_slice(sample_buf.samples());
    }

    Ok((samples, sample_rate, channels))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_infer_key_from_filename() {
        let cases = vec![
            ("enter_thock.wav", "enter"),
            ("return.mp3", "enter"),
            ("spacebar.ogg", "space"),
            ("shift_left.flac", "shift"),
            ("backspace_click.wav", "backspace"),
            ("delete_key.wav", "backspace"),
            ("escape.wav", "escape"),
            ("cmd_key.wav", "super"),
            ("win_key.wav", "super"),
            ("random_sound.wav", "default"),
        ];

        for (filename, expected) in cases {
            assert_eq!(infer_key_from_filename(Path::new(filename)), expected);
        }
    }
}
