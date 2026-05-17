//! Generates synthetic WAV sound files for the default Keyra sound pack.
//!
//! Run this with: cargo run --bin gen_pack
//!
//! Creates short mechanical keyboard click sounds using sine wave bursts
//! with fast attack and exponential decay envelopes.

use hound::{SampleFormat, WavSpec, WavWriter};
use std::f32::consts::PI;
use std::path::Path;

/// Envelope parameters for a click sound.
struct ClickParams {
    /// Base frequency in Hz.
    frequency: f32,
    /// Second harmonic frequency (gives body to the click).
    harmonic: f32,
    /// Harmonic mix ratio (0.0 = pure fundamental, 1.0 = pure harmonic).
    harmonic_mix: f32,
    /// Duration in seconds.
    duration: f32,
    /// Attack time in seconds (how fast the click rises).
    attack: f32,
    /// Decay curve steepness (higher = faster decay).
    decay_rate: f32,
    /// Peak amplitude (0.0..1.0).
    amplitude: f32,
    /// Optional noise mix (0.0..1.0) for realism.
    noise_mix: f32,
}

fn generate_click(spec: &WavSpec, params: &ClickParams) -> Vec<f32> {
    let total_samples = (params.duration * spec.sample_rate as f32) as usize;
    let attack_samples = (params.attack * spec.sample_rate as f32) as usize;
    let mut samples = Vec::with_capacity(total_samples);

    // Simple LCG for deterministic noise
    let mut noise_state: u32 = 12345;

    for i in 0..total_samples {
        let t = i as f32 / spec.sample_rate as f32;

        // Envelope: fast linear attack, exponential decay
        let envelope = if i < attack_samples {
            i as f32 / attack_samples as f32
        } else {
            let decay_t = (i - attack_samples) as f32 / spec.sample_rate as f32;
            (-decay_t * params.decay_rate).exp()
        };

        // Fundamental + harmonic
        let fundamental = (2.0 * PI * params.frequency * t).sin();
        let harmonic = (2.0 * PI * params.harmonic * t).sin();
        let tone = fundamental * (1.0 - params.harmonic_mix) + harmonic * params.harmonic_mix;

        // Deterministic noise
        noise_state = noise_state.wrapping_mul(1103515245).wrapping_add(12345);
        let noise = (noise_state as f32 / u32::MAX as f32) * 2.0 - 1.0;

        let mixed = tone * (1.0 - params.noise_mix) + noise * params.noise_mix;
        let sample = mixed * envelope * params.amplitude;

        samples.push(sample.clamp(-1.0, 1.0));
    }

    samples
}

fn write_wav(path: &Path, samples: &[f32], spec: &WavSpec) -> Result<(), Box<dyn std::error::Error>> {
    let mut writer = WavWriter::create(path, *spec)?;
    for &s in samples {
        writer.write_sample(s)?;
    }
    writer.finalize()?;
    println!("  Written: {} ({} samples, {:.1}ms)",
        path.display(), samples.len(),
        samples.len() as f32 / spec.sample_rate as f32 * 1000.0);
    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let pack_dir = Path::new("keyra-daemon/packs/default");
    std::fs::create_dir_all(pack_dir)?;

    let spec = WavSpec {
        channels: 1,
        sample_rate: 44100,
        bits_per_sample: 32,
        sample_format: SampleFormat::Float,
    };

    println!("Generating default sound pack...\n");

    // Default click — crisp mechanical switch
    let default_click = generate_click(&spec, &ClickParams {
        frequency: 4200.0,
        harmonic: 6800.0,
        harmonic_mix: 0.3,
        duration: 0.025, // 25ms
        attack: 0.0005,  // 0.5ms attack
        decay_rate: 120.0,
        amplitude: 0.85,
        noise_mix: 0.15,
    });
    write_wav(&pack_dir.join("default.wav"), &default_click, &spec)?;

    // Space bar — deeper, slightly longer thock
    let space_click = generate_click(&spec, &ClickParams {
        frequency: 1800.0,
        harmonic: 3200.0,
        harmonic_mix: 0.4,
        duration: 0.035, // 35ms
        attack: 0.001,
        decay_rate: 80.0,
        amplitude: 0.9,
        noise_mix: 0.2,
    });
    write_wav(&pack_dir.join("space.wav"), &space_click, &spec)?;

    // Enter key — a satisfying deeper thud
    let enter_click = generate_click(&spec, &ClickParams {
        frequency: 1200.0,
        harmonic: 2400.0,
        harmonic_mix: 0.5,
        duration: 0.040, // 40ms
        attack: 0.001,
        decay_rate: 70.0,
        amplitude: 0.88,
        noise_mix: 0.25,
    });
    write_wav(&pack_dir.join("enter.wav"), &enter_click, &spec)?;

    // Backspace — slightly muted click
    let backspace_click = generate_click(&spec, &ClickParams {
        frequency: 3600.0,
        harmonic: 5400.0,
        harmonic_mix: 0.25,
        duration: 0.020, // 20ms
        attack: 0.0005,
        decay_rate: 140.0,
        amplitude: 0.7,
        noise_mix: 0.1,
    });
    write_wav(&pack_dir.join("backspace.wav"), &backspace_click, &spec)?;

    println!("\nDone! Pack generated at: {}", pack_dir.display());
    Ok(())
}
