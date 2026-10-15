//! Streaming GIF encoder. Frames arrive one at a time from Swift; each is
//! scaled, compared with the previous one, and held until the next distinct
//! frame arrives so its delay is known (GIF delays are per frame, in
//! centiseconds). Identical consecutive frames are merged into one longer frame.
//!
//! Encoding uses the `gif` crate (MIT OR Apache-2.0) with NeuQuant colour
//! quantisation from `color_quant` (MIT). Output goes to a temp file that
//! `finish` moves into place.

use std::fs::{self, File};
use std::io::{BufWriter, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use rgb::{FromSlice, RGBA8};

use crate::CoreError;

/// GIF viewers commonly bump delays under 2 cs up to 10 cs, which would slow
/// the animation down, so no frame is written shorter than this.
const MIN_DELAY_CS: u64 = 2;
/// Duration of the last frame when nothing else tells us how long it lasts.
const DEFAULT_LAST_FRAME_CS: u64 = 10;

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
    /// Quality 1..=100; higher spends more time choosing each frame's palette.
    pub quality: u8,
    /// Fastest palette selection, lower quality.
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
    /// No frame yet; the encoder is not created because it needs the output size.
    Waiting(GifSettings),
    Running(Running),
    Finished,
}

struct Running {
    encoder: gif::Encoder<BufWriter<File>>,
    temp_path: PathBuf,
    width: u32,
    height: u32,
    out_w: u32,
    out_h: u32,
    speed: i32,
    /// Frames fed, including merged duplicates.
    frame_index: usize,
    origin: f64,
    last_timestamp: f64,
    /// Last distinct frame (already scaled to the output size), not yet written.
    pending: Option<Vec<u8>>,
    /// Timeline position in centiseconds where the pending frame starts.
    cursor_cs: u64,
    last_delay_cs: Option<u64>,
}

impl Running {
    fn centis(&self, t: f64) -> u64 {
        ((t - self.origin) * 100.0).round().max(0.0) as u64
    }

    /// Writes the pending frame so that it ends at `end_cs` on the timeline.
    fn flush_pending(&mut self, end_cs: u64) -> Result<(), CoreError> {
        let Some(mut rgba) = self.pending.take() else { return Ok(()) };
        let delay = end_cs.saturating_sub(self.cursor_cs).max(MIN_DELAY_CS);
        let mut frame = gif::Frame::from_rgba_speed(self.out_w as u16, self.out_h as u16, &mut rgba, self.speed);
        frame.delay = delay.min(u16::MAX as u64) as u16;
        self.encoder
            .write_frame(&frame)
            .map_err(|e| CoreError::Encoding { message: e.to_string() })?;
        self.cursor_cs += delay;
        self.last_delay_cs = Some(delay);
        Ok(())
    }
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

/// Box-filter downscale of tightly packed RGBA: each output pixel averages the
/// source pixels it covers, which keeps text and UI edges smooth.
fn downscale(src: &[u8], w: u32, h: u32, ow: u32, oh: u32) -> Vec<u8> {
    let (w, h, ow, oh) = (w as usize, h as usize, ow as usize, oh as usize);
    let mut out = vec![0u8; ow * oh * 4];
    for oy in 0..oh {
        let y0 = oy * h / oh;
        let y1 = ((oy + 1) * h / oh).max(y0 + 1).min(h);
        for ox in 0..ow {
            let x0 = ox * w / ow;
            let x1 = ((ox + 1) * w / ow).max(x0 + 1).min(w);
            let mut sum = [0u32; 4];
            for y in y0..y1 {
                let row = y * w * 4;
                for x in x0..x1 {
                    let i = row + x * 4;
                    for c in 0..4 {
                        sum[c] += src[i + c] as u32;
                    }
                }
            }
            let n = ((y1 - y0) * (x1 - x0)) as u32;
            let o = (oy * ow + ox) * 4;
            for c in 0..4 {
                out[o + c] = ((sum[c] + n / 2) / n) as u8;
            }
        }
    }
    out
}

/// NeuQuant sampling factor (1 = slowest/best, 30 = fastest) for a 1..=100
/// quality. Quality 100 maps to 10, the crate's recommended balance; anything
/// slower cannot keep up with a 15 fps recording at 1200 px wide.
fn speed_for(quality: u8, fast: bool) -> i32 {
    if fast {
        return 30;
    }
    (30 - quality as i32 / 5).clamp(10, 30)
}

fn start(settings: &GifSettings, width: u32, height: u32) -> Result<Running, CoreError> {
    let (out_w, out_h) = fitted_size(width, height, settings.max_width, settings.max_height);
    if out_w > u16::MAX as u32 || out_h > u16::MAX as u32 {
        return Err(CoreError::InvalidInput { message: format!("GIF frames are limited to 65535 px, got {out_w}x{out_h}") });
    }
    let temp_path = temp_gif_path();
    let file = BufWriter::new(File::create(&temp_path)?);
    let mut encoder = gif::Encoder::new(file, out_w as u16, out_h as u16, &[])
        .map_err(|e| CoreError::Encoding { message: e.to_string() })?;
    // No loop extension at all means "play once".
    let repeat = match settings.repeat {
        r if r < 0 => None,
        0 => Some(gif::Repeat::Infinite),
        r => Some(gif::Repeat::Finite(r.min(u16::MAX as i32) as u16)),
    };
    if let Some(repeat) = repeat {
        encoder.set_repeat(repeat).map_err(|e| CoreError::Encoding { message: e.to_string() })?;
    }
    Ok(Running {
        encoder,
        temp_path,
        width,
        height,
        out_w,
        out_h,
        speed: speed_for(settings.quality, settings.fast),
        frame_index: 0,
        origin: 0.0,
        last_timestamp: 0.0,
        pending: None,
        cursor_cs: 0,
        last_delay_cs: None,
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

        let mut pixels = pixels;
        as_rgba_in_place(&mut pixels, format);
        let scaled = if (running.out_w, running.out_h) == (width, height) {
            pixels
        } else {
            downscale(&pixels, width, height, running.out_w, running.out_h)
        };

        if running.frame_index == 0 {
            running.origin = timestamp_secs;
        }
        if running.pending.as_deref() != Some(scaled.as_slice()) {
            let start_cs = running.centis(timestamp_secs);
            running.flush_pending(start_cs)?;
            running.pending = Some(scaled);
        }
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
        let mut running = match previous {
            State::Running(r) => r,
            State::Waiting(_) => return Err(CoreError::Encoding { message: "no frames were added".into() }),
            State::Finished => return Err(CoreError::AlreadyFinished),
        };
        drop(guard);

        let last_cs = running.centis(running.last_timestamp);
        let mut duration = running.last_timestamp - running.origin;
        let end_cs = match end_timestamp_secs {
            Some(end) if end > running.last_timestamp => {
                duration = end - running.origin;
                running.centis(end)
            }
            // Without a stop time the last frame lasts as long as the one before it.
            _ => last_cs + running.last_delay_cs.unwrap_or(DEFAULT_LAST_FRAME_CS),
        };
        let temp_path = running.temp_path.clone();
        let written = running.flush_pending(end_cs).and_then(|_| {
            let mut file = running
                .encoder
                .into_inner()
                .map_err(|e| CoreError::Encoding { message: e.to_string() })?;
            file.flush()?;
            Ok(())
        });
        if let Err(e) = written {
            let _ = fs::remove_file(&temp_path);
            return Err(e);
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
            frame_count: running.frame_index as u32,
            file_size_bytes: size,
            duration_secs: duration,
        })
    }

    /// Abandons the recording and deletes the temp file. Safe to call at any time.
    pub fn cancel(&self) {
        let Ok(mut guard) = self.state.lock() else { return };
        let previous = std::mem::replace(&mut *guard, State::Finished);
        drop(guard);
        if let State::Running(running) = previous {
            let temp_path = running.temp_path.clone();
            drop(running);
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
    fn downscale_averages_each_covered_block() {
        // 2x2 → 1x1: the average of black, white, black, white is mid grey.
        let src = vec![0, 0, 0, 255, 255, 255, 255, 255, 0, 0, 0, 255, 255, 255, 255, 255];
        assert_eq!(downscale(&src, 2, 2, 1, 1), vec![128, 128, 128, 255]);
    }

    #[test]
    fn speed_tracks_quality() {
        assert_eq!(speed_for(100, false), 10);
        assert_eq!(speed_for(90, false), 12);
        assert_eq!(speed_for(50, false), 20);
        assert_eq!(speed_for(1, false), 30);
        assert_eq!(speed_for(100, true), 30);
    }

    #[test]
    fn rgba_is_viewed_without_changing_bytes() {
        let mut bytes = vec![1, 2, 3, 4];
        let px = as_rgba_in_place(&mut bytes, PixelFormat::Rgba);
        assert_eq!(px, &[RGBA8::new(1, 2, 3, 4)]);
        assert_eq!(bytes, vec![1, 2, 3, 4]);
    }
}
