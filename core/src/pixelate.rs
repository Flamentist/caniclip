use crate::CoreError;

/// Replaces every `block_size`×`block_size` square inside the rect with the
/// square's average colour. The rect is clamped to the image; a rect that falls
/// entirely outside returns the input unchanged.
#[uniffi::export]
pub fn pixelate(
    pixels: Vec<u8>,
    width: u32,
    height: u32,
    x: u32,
    y: u32,
    w: u32,
    h: u32,
    block_size: u32,
) -> Result<Vec<u8>, CoreError> {
    let expected_len = (width as usize) * (height as usize) * 4;
    if pixels.len() != expected_len {
        return Err(CoreError::InvalidInput {
            message: format!("expected {expected_len} bytes for {width}x{height} RGBA, got {}", pixels.len()),
        });
    }
    if block_size == 0 {
        return Err(CoreError::InvalidInput { message: "block_size must be at least 1".into() });
    }

    let x0 = x.min(width);
    let y0 = y.min(height);
    let x1 = x.saturating_add(w).min(width);
    let y1 = y.saturating_add(h).min(height);
    if x0 >= x1 || y0 >= y1 {
        return Ok(pixels);
    }

    let mut out = pixels;
    let stride = width as usize * 4;
    let mut by = y0;
    while by < y1 {
        let bh = block_size.min(y1 - by);
        let mut bx = x0;
        while bx < x1 {
            let bw = block_size.min(x1 - bx);
            let mut sum = [0u64; 4];
            for yy in by..by + bh {
                let row = yy as usize * stride;
                for xx in bx..bx + bw {
                    let i = row + xx as usize * 4;
                    for c in 0..4 {
                        sum[c] += out[i + c] as u64;
                    }
                }
            }
            let n = (bw as u64) * (bh as u64);
            let avg = [
                (sum[0] / n) as u8,
                (sum[1] / n) as u8,
                (sum[2] / n) as u8,
                (sum[3] / n) as u8,
            ];
            for yy in by..by + bh {
                let row = yy as usize * stride;
                for xx in bx..bx + bw {
                    let i = row + xx as usize * 4;
                    out[i..i + 4].copy_from_slice(&avg);
                }
            }
            bx += bw;
        }
        by += bh;
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn solid(width: u32, height: u32, rgba: [u8; 4]) -> Vec<u8> {
        rgba.iter().copied().cycle().take((width * height * 4) as usize).collect()
    }

    fn px(buf: &[u8], width: u32, x: u32, y: u32) -> [u8; 4] {
        let i = ((y * width + x) * 4) as usize;
        [buf[i], buf[i + 1], buf[i + 2], buf[i + 3]]
    }

    #[test]
    fn rejects_buffer_with_wrong_length() {
        let err = pixelate(vec![0; 10], 2, 2, 0, 0, 2, 2, 1).unwrap_err();
        assert!(matches!(err, CoreError::InvalidInput { .. }));
    }

    #[test]
    fn rejects_zero_block_size() {
        let err = pixelate(solid(2, 2, [0, 0, 0, 255]), 2, 2, 0, 0, 2, 2, 0).unwrap_err();
        assert!(matches!(err, CoreError::InvalidInput { .. }));
    }

    #[test]
    fn averages_each_block() {
        // 4x2 image: left 2 columns black, right 2 columns white.
        let mut buf = solid(4, 2, [0, 0, 0, 255]);
        for y in 0..2 {
            for x in 2..4 {
                let i = ((y * 4 + x) * 4) as usize;
                buf[i..i + 3].copy_from_slice(&[255, 255, 255]);
            }
        }
        // One 4x2 block covering everything averages to mid grey.
        let out = pixelate(buf, 4, 2, 0, 0, 4, 2, 4).unwrap();
        assert_eq!(px(&out, 4, 0, 0), [127, 127, 127, 255]);
        assert_eq!(px(&out, 4, 3, 1), [127, 127, 127, 255]);
    }

    #[test]
    fn leaves_pixels_outside_rect_untouched() {
        let mut buf = solid(4, 4, [10, 20, 30, 255]);
        // Make the top-left 2x2 region white; pixelate only it.
        for y in 0..2 {
            for x in 0..2 {
                let i = ((y * 4 + x) * 4) as usize;
                buf[i..i + 3].copy_from_slice(&[255, 255, 255]);
            }
        }
        let out = pixelate(buf.clone(), 4, 4, 0, 0, 2, 2, 2).unwrap();
        assert_eq!(px(&out, 4, 0, 0), [255, 255, 255, 255]);
        assert_eq!(px(&out, 4, 3, 3), [10, 20, 30, 255]);
        assert_eq!(out.len(), buf.len());
    }

    #[test]
    fn clamps_rect_to_image_bounds() {
        let buf = solid(3, 3, [50, 60, 70, 255]);
        let out = pixelate(buf.clone(), 3, 3, 2, 2, 10, 10, 8).unwrap();
        assert_eq!(out, buf);
        let out = pixelate(buf.clone(), 3, 3, 5, 5, 2, 2, 2).unwrap();
        assert_eq!(out, buf);
    }
}
