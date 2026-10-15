use caniclip_core::{CoreError, GifEncoder, GifSettings, PixelFormat};
use std::fs;

fn settings() -> GifSettings {
    GifSettings { max_width: None, max_height: None, quality: 90, fast: true, repeat: 0 }
}

fn frame(width: u32, height: u32, shade: u8) -> Vec<u8> {
    let mut v = Vec::with_capacity((width * height * 4) as usize);
    for y in 0..height {
        for x in 0..width {
            // A moving diagonal so frames differ and gifski keeps them all.
            let on = (x + y + shade as u32) % 8 < 4;
            let c = if on { shade } else { 255 - shade };
            v.extend_from_slice(&[c, c / 2, 255 - c, 255]);
        }
    }
    v
}

fn temp_out(name: &str) -> String {
    let p = std::env::temp_dir().join(format!("caniclip-test-{}-{}.gif", std::process::id(), name));
    let _ = fs::remove_file(&p);
    p.to_string_lossy().into_owned()
}

#[test]
fn encodes_ten_frames_to_a_valid_gif() {
    let enc = GifEncoder::new(settings()).unwrap();
    for i in 0..10u32 {
        enc.add_frame(frame(64, 48, (i * 20) as u8), 64, 48, PixelFormat::Rgba, i as f64 / 15.0).unwrap();
    }
    let out = temp_out("ten");
    let summary = enc.finish(out.clone(), None).unwrap();
    let bytes = fs::read(&out).unwrap();
    assert_eq!(&bytes[0..6], b"GIF89a");
    assert_eq!(summary.frame_count, 10);
    assert_eq!(summary.file_size_bytes, bytes.len() as u64);
    assert!((summary.duration_secs - 9.0 / 15.0).abs() < 1e-9);
    assert!(bytes.len() > 500, "gif suspiciously small: {}", bytes.len());
    fs::remove_file(out).unwrap();
}

#[test]
fn downscales_to_max_width_preserving_aspect() {
    let mut s = settings();
    s.max_width = Some(32);
    let enc = GifEncoder::new(s).unwrap();
    for i in 0..3u32 {
        enc.add_frame(frame(64, 48, (i * 40) as u8), 64, 48, PixelFormat::Rgba, i as f64 / 10.0).unwrap();
    }
    let out = temp_out("scaled");
    enc.finish(out.clone(), None).unwrap();
    let bytes = fs::read(&out).unwrap();
    // Logical screen width/height live at bytes 6..10, little endian.
    let w = u16::from_le_bytes([bytes[6], bytes[7]]);
    let h = u16::from_le_bytes([bytes[8], bytes[9]]);
    assert_eq!((w, h), (32, 24));
    fs::remove_file(out).unwrap();
}

#[test]
fn converts_bgra_input() {
    // A solid red image given as BGRA bytes must decode back to red pixels.
    let enc = GifEncoder::new(settings()).unwrap();
    let bgra = vec![0u8, 0, 255, 255].repeat(16 * 16);
    enc.add_frame(bgra.clone(), 16, 16, PixelFormat::Bgra, 0.0).unwrap();
    enc.add_frame(bgra, 16, 16, PixelFormat::Bgra, 0.1).unwrap();
    let out = temp_out("bgra");
    enc.finish(out.clone(), None).unwrap();

    let file = fs::File::open(&out).unwrap();
    let mut options = gif::DecodeOptions::new();
    options.set_color_output(gif::ColorOutput::RGBA);
    let mut decoder = options.read_info(file).unwrap();
    let frame = decoder.read_next_frame().unwrap().expect("at least one frame");
    let px = &frame.buffer[0..4];
    assert!(px[0] > 200 && px[1] < 60 && px[2] < 60, "first pixel was {:?}", px);
    fs::remove_file(out).unwrap();
}

#[test]
fn rejects_wrong_byte_length() {
    let enc = GifEncoder::new(settings()).unwrap();
    let err = enc.add_frame(vec![0; 10], 4, 4, PixelFormat::Rgba, 0.0).unwrap_err();
    assert!(matches!(err, CoreError::InvalidInput { .. }));
    enc.cancel();
}

#[test]
fn rejects_dimension_change_after_first_frame() {
    let enc = GifEncoder::new(settings()).unwrap();
    enc.add_frame(frame(8, 8, 0), 8, 8, PixelFormat::Rgba, 0.0).unwrap();
    let err = enc.add_frame(frame(9, 8, 0), 9, 8, PixelFormat::Rgba, 0.1).unwrap_err();
    assert!(matches!(err, CoreError::InvalidInput { .. }));
    enc.cancel();
}

#[test]
fn finish_without_frames_is_an_encoding_error() {
    let enc = GifEncoder::new(settings()).unwrap();
    let err = enc.finish(temp_out("empty"), None).unwrap_err();
    assert!(matches!(err, CoreError::Encoding { .. }));
}

#[test]
fn calls_after_finish_return_already_finished() {
    let enc = GifEncoder::new(settings()).unwrap();
    enc.add_frame(frame(8, 8, 0), 8, 8, PixelFormat::Rgba, 0.0).unwrap();
    enc.add_frame(frame(8, 8, 90), 8, 8, PixelFormat::Rgba, 0.1).unwrap();
    let out = temp_out("twice");
    enc.finish(out.clone(), None).unwrap();
    assert!(matches!(enc.finish(out.clone(), None).unwrap_err(), CoreError::AlreadyFinished));
    assert!(matches!(
        enc.add_frame(frame(8, 8, 0), 8, 8, PixelFormat::Rgba, 0.2).unwrap_err(),
        CoreError::AlreadyFinished
    ));
    fs::remove_file(out).unwrap();
}

#[test]
fn rejects_invalid_quality() {
    let mut s = settings();
    s.quality = 0;
    assert!(matches!(GifEncoder::new(s).unwrap_err(), CoreError::InvalidInput { .. }));
    let mut s = settings();
    s.quality = 101;
    assert!(matches!(GifEncoder::new(s).unwrap_err(), CoreError::InvalidInput { .. }));
}

#[test]
fn extends_static_tail_to_end_timestamp() {
    let enc = GifEncoder::new(settings()).unwrap();
    enc.add_frame(frame(16, 16, 0), 16, 16, PixelFormat::Rgba, 0.0).unwrap();
    enc.add_frame(frame(16, 16, 120), 16, 16, PixelFormat::Rgba, 0.1).unwrap();
    let out = temp_out("tail");
    let summary = enc.finish(out.clone(), Some(2.0)).unwrap();
    assert_eq!(summary.duration_secs, 2.0);

    let file = fs::File::open(&out).unwrap();
    let mut decoder = gif::DecodeOptions::new().read_info(file).unwrap();
    let mut total_centis = 0u32;
    while let Some(f) = decoder.read_next_frame().unwrap() {
        total_centis += u32::from(f.delay);
    }
    assert!((i64::from(total_centis) - 200).abs() <= 2, "total delay was {total_centis} centiseconds, expected ~200");
    fs::remove_file(out).unwrap();
}

#[test]
fn unwritable_output_keeps_temp_file_and_reports_it() {
    let enc = GifEncoder::new(settings()).unwrap();
    enc.add_frame(frame(8, 8, 0), 8, 8, PixelFormat::Rgba, 0.0).unwrap();
    enc.add_frame(frame(8, 8, 90), 8, 8, PixelFormat::Rgba, 0.1).unwrap();
    let err = enc.finish("/nonexistent-caniclip-dir/x.gif".to_string(), None).unwrap_err();
    match err {
        CoreError::OutputUnwritable { temp_path, .. } => {
            assert!(std::path::Path::new(&temp_path).exists(), "temp file should be kept at {temp_path}");
            fs::remove_file(temp_path).unwrap();
        }
        other => panic!("unexpected error {other:?}"),
    }
}
