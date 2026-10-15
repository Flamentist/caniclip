//! Streaming GIF encoder over gifski. Frames arrive one at a time from Swift;
//! gifski's Collector/Writer pair must run on different threads, so the writer
//! thread is spawned lazily on the first frame (when the frame size is known)
//! and streams into a temp file that `finish` moves into place.

use std::fs::{self, File};
use std::io::BufWriter;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::JoinHandle;

use gifski::progress::NoProgress;
use gifski::{Collector, Repeat, Settings};
use imgref::ImgVec;
use rgb::{FromSlice, RGBA8};

use crate::CoreError;

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum PixelFormat {
    Rgba,
    Bgra,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct GifSettings {
    /// Frames wider than this are downscaled to fit, aspect preserved.
    pub max_width: Option<u32>,
    /// Frames taller than this are downscaled to fit, aspect preserved.
    pub max_height: Option<u32>,
    /// gifski quality 1..=100.
    pub quality: u8,
    /// gifski fast mode: lower quality, faster.
    pub fast: bool,
    /// -1 = play once, 0 = loop forever, n = loop n times.
    pub repeat: i32,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct GifSummary {
    pub frame_count: u32,
    pub file_size_bytes: u64,
    pub duration_secs: f64,
}

enum State {
    /// No frame yet; gifski is not created because it needs the output size.
    Waiting(GifSettings),
    Running(Running),
    Finished,
}

struct Running {
    collector: Collector,
    writer: JoinHandle<Result<(), gifski::Error>>,
    temp_path: PathBuf,
    width: u32,
    height: u32,
    frame_index: usize,
    last_timestamp: f64,
    /// Copy of the most recent frame, re-added at the stop time so a static
    /// tail keeps its real duration (gifski ends a GIF at the last frame's pts).
    last_frame: Option<ImgVec<RGBA8>>,
}

#[derive(uniffi::Object)]
pub struct GifEncoder {
    state: Mutex<State>,
}

impl std::fmt::Debug for GifEncoder {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("GifEncoder")
    }
}

static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

fn temp_gif_path() -> PathBuf {
    let n = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
    std::env::temp_dir().join(format!("caniclip-{}-{}.gif", std::process::id(), n))
}

/// Output size that fits inside the optional maxima while preserving aspect.
fn fitted_size(width: u32, height: u32, max_w: Option<u32>, max_h: Option<u32>) -> (u32, u32) {
    let mut scale = 1.0f64;
    if let Some(mw) = max_w.filter(|m| *m > 0) {
        scale = scale.min(mw as f64 / width as f64);
    }
    if let Some(mh) = max_h.filter(|m| *m > 0) {
        scale = scale.min(mh as f64 / height as f64);
    }
    if scale >= 1.0 {
        return (width, height);
    }
    (
        ((width as f64 * scale).round() as u32).max(1),
        ((height as f64 * scale).round() as u32).max(1),
    )
}

/// Views `pixels` as RGBA without a second buffer: BGRA input has its blue and
/// red bytes swapped in place first. `pixels.len()` must be a multiple of 4.
fn as_rgba_in_place(pixels: &mut [u8], format: PixelFormat) -> &[RGBA8] {
    if format == PixelFormat::Bgra {
        for px in pixels.chunks_exact_mut(4) {
            px.swap(0, 2);
        }
    }
    pixels.as_rgba()
}

fn start(settings: &GifSettings, width: u32, height: u32) -> Result<Running, CoreError> {
    let (out_w, out_h) = fitted_size(width, height, settings.max_width, settings.max_height);
    let repeat = match settings.repeat {
        r if r < 0 => Repeat::Finite(0),
        0 => Repeat::Infinite,
        r => Repeat::Finite(r.min(u16::MAX as i32) as u16),
    };
    let gs = Settings {
        width: Some(out_w),
        height: Some(out_h),
        quality: settings.quality,
        fast: settings.fast,
        repeat,
    };
    let (collector, writer) =
        gifski::new(gs).map_err(|e| CoreError::Encoding { message: e.to_string() })?;
    let temp_path = temp_gif_path();
    let file = BufWriter::new(File::create(&temp_path)?);
    let handle = std::thread::Builder::new()
        .name("caniclip-gif-writer".into())
        .spawn(move || writer.write(file, &mut NoProgress {}))
        .map_err(|e| CoreError::Io { message: e.to_string() })?;
    Ok(Running {
        collector,
        writer: handle,
        temp_path,
        width,
        height,
        frame_index: 0,
        last_timestamp: 0.0,
        last_frame: None,
    })
}

#[uniffi::export]
impl GifEncoder {
    #[uniffi::constructor]
    pub fn new(settings: GifSettings) -> Result<Arc<Self>, CoreError> {
        if !(1..=100).contains(&settings.quality) {
            return Err(CoreError::InvalidInput {
                message: format!("quality must be 1..=100, got {}", settings.quality),
            });
        }
        Ok(Arc::new(Self { state: Mutex::new(State::Waiting(settings)) }))
    }

    pub fn add_frame(
        &self,
        pixels: Vec<u8>,
        width: u32,
        height: u32,
        format: PixelFormat,
        timestamp_secs: f64,
    ) -> Result<(), CoreError> {
        let expected = width as usize * height as usize * 4;
        if width == 0 || height == 0 || pixels.len() != expected {
            return Err(CoreError::InvalidInput {
                message: format!("expected {expected} bytes for {width}x{height}, got {}", pixels.len()),
            });
        }
        let mut guard = self.state.lock().map_err(|_| CoreError::Encoding { message: "encoder poisoned".into() })?;
        if let State::Waiting(settings) = &*guard {
            let running = start(settings, width, height)?;
            *guard = State::Running(running);
        }
        let running = match &mut *guard {
            State::Running(r) => r,
            State::Finished => return Err(CoreError::AlreadyFinished),
            State::Waiting(_) => return Err(CoreError::Encoding { message: "encoder failed to start".into() }),
        };
        if (width, height) != (running.width, running.height) {
            return Err(CoreError::InvalidInput {
                message: format!(
                    "frame size {width}x{height} differs from first frame {}x{}",
                    running.width, running.height
                ),
            });
        }
        // gifski's collector takes an owned ImgVec, so one memcpy remains here;
        // the swizzle itself no longer allocates a separate RGBA buffer.
        let mut pixels = pixels;
        let rgba = as_rgba_in_place(&mut pixels, format).to_vec();
        let img = ImgVec::new(rgba, width as usize, height as usize);
        running.last_frame = Some(img.clone());
        running
            .collector
            .add_frame_rgba(running.frame_index, img, timestamp_secs)
            .map_err(|e| CoreError::Encoding { message: e.to_string() })?;
        running.frame_index += 1;
        running.last_timestamp = timestamp_secs;
        Ok(())
    }

    /// Finalises the GIF at `output_path`. When `end_timestamp_secs` is later
    /// than the last frame, the last frame is held until then, so a recording
    /// that ends on a static screen keeps its full length.
    pub fn finish(&self, output_path: String, end_timestamp_secs: Option<f64>) -> Result<GifSummary, CoreError> {
        let mut guard = self.state.lock().map_err(|_| CoreError::Encoding { message: "encoder poisoned".into() })?;
        let previous = std::mem::replace(&mut *guard, State::Finished);
        let running = match previous {
            State::Running(r) => r,
            State::Waiting(_) => return Err(CoreError::Encoding { message: "no frames were added".into() }),
            State::Finished => return Err(CoreError::AlreadyFinished),
        };
        drop(guard);

        let Running { collector, writer, temp_path, frame_index, mut last_timestamp, last_frame, .. } = running;
        if let (Some(end), Some(frame)) = (end_timestamp_secs, last_frame) {
            if end > last_timestamp {
                // gifski gives the final frame the duration of the frame before it.
                // Re-adding the last frame at the midpoint splits the hold into two
                // equal halves, so the animation ends exactly at `end`.
                let midpoint = (end + last_timestamp) / 2.0;
                collector
                    .add_frame_rgba(frame_index, frame, midpoint)
                    .map_err(|e| CoreError::Encoding { message: e.to_string() })?;
                last_timestamp = end;
            }
        }
        drop(collector); // closes the channel so the writer drains and returns
        let write_result = writer.join().map_err(|_| CoreError::Encoding { message: "writer thread panicked".into() })?;
        if let Err(e) = write_result {
            let _ = fs::remove_file(&temp_path);
            return Err(CoreError::Encoding { message: e.to_string() });
        }

        let dest = PathBuf::from(&output_path);
        if fs::rename(&temp_path, &dest).is_err() {
            // Cross-volume move: copy then delete. If that fails too, keep the
            // temp file and tell the caller where it is rather than losing the GIF.
            if let Err(e) = fs::copy(&temp_path, &dest) {
                return Err(CoreError::OutputUnwritable {
                    message: format!("{}: {e}", dest.display()),
                    temp_path: temp_path.to_string_lossy().into_owned(),
                });
            }
            let _ = fs::remove_file(&temp_path);
        }
        let size = fs::metadata(&dest)?.len();
        Ok(GifSummary {
            frame_count: frame_index as u32,
            file_size_bytes: size,
            duration_secs: last_timestamp,
        })
    }

    /// Abandons the recording and deletes the temp file. Safe to call at any time.
    pub fn cancel(&self) {
        let Ok(mut guard) = self.state.lock() else { return };
        let previous = std::mem::replace(&mut *guard, State::Finished);
        drop(guard);
        if let State::Running(Running { collector, writer, temp_path, .. }) = previous {
            drop(collector);
            let _ = writer.join();
            let _ = fs::remove_file(temp_path);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fitted_size_respects_width_and_aspect() {
        assert_eq!(fitted_size(1000, 500, Some(500), None), (500, 250));
        assert_eq!(fitted_size(1000, 500, None, Some(100)), (200, 100));
        assert_eq!(fitted_size(100, 50, Some(500), Some(500)), (100, 50));
        assert_eq!(fitted_size(100, 50, Some(0), None), (100, 50));
    }

    #[test]
    fn cancel_removes_the_temp_file() {
        let enc = GifEncoder::new(GifSettings { max_width: None, max_height: None, quality: 90, fast: true, repeat: 0 })
            .unwrap();
        enc.add_frame(vec![0; 4 * 4 * 4], 4, 4, PixelFormat::Rgba, 0.0).unwrap();
        let temp = match &*enc.state.lock().unwrap() {
            State::Running(r) => r.temp_path.clone(),
            _ => panic!("encoder should be running after the first frame"),
        };
        assert!(temp.exists(), "temp file should exist while recording");
        enc.cancel();
        assert!(!temp.exists(), "cancel must delete {}", temp.display());
        assert!(matches!(
            enc.add_frame(vec![0; 4 * 4 * 4], 4, 4, PixelFormat::Rgba, 0.1).unwrap_err(),
            CoreError::AlreadyFinished
        ));
    }

    #[test]
    fn bgra_is_swizzled_in_place_and_viewed_as_rgba() {
        let mut bytes = vec![1, 2, 3, 4, 10, 20, 30, 40];
        let px = as_rgba_in_place(&mut bytes, PixelFormat::Bgra);
        assert_eq!(px, &[RGBA8::new(3, 2, 1, 4), RGBA8::new(30, 20, 10, 40)]);
        assert_eq!(bytes, vec![3, 2, 1, 4, 30, 20, 10, 40], "swizzle must happen in the caller's buffer");
    }

    #[test]
    fn rgba_is_viewed_without_changing_bytes() {
        let mut bytes = vec![1, 2, 3, 4];
        let px = as_rgba_in_place(&mut bytes, PixelFormat::Rgba);
        assert_eq!(px, &[RGBA8::new(1, 2, 3, 4)]);
        assert_eq!(bytes, vec![1, 2, 3, 4]);
    }
}
