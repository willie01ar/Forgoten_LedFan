//! Reference packet generator for LedFan's golden tests.
//!
//! Reads a grid file: one image per line, 156 whitespace-separated columns, each an
//! 11-character string of '0'/'1' for rows y = 0 (top) .. 10 (bottom). Draws it into a
//! pearlfan `Frame` through the library's own `draw_point`, then emits the packets exactly
//! as `Device::send_animation` would (pearlfan-rs src/device.rs lines 103-121), one hex
//! line per 8-byte packet. The data-packet composition is transcribed here because the
//! library couples it to an open HID handle; the header comes from `Effects::to_bytes`.
use pearlfan::draw::Frame;
use pearlfan::effects::{AnimationEffect, Effects, EntryExitEffect};
use std::io::Read;

fn main() {
    let mut text = String::new();
    std::io::stdin().read_to_string(&mut text).expect("read stdin");
    let effects = Effects::new_with_effects(
        EntryExitEffect::RightToLeft,
        EntryExitEffect::RightToLeft,
        AnimationEffect::None,
    );
    let mut frames: Vec<Frame> = Vec::new();
    for line in text.lines().filter(|l| !l.trim().is_empty()) {
        let mut frame = Frame::new();
        for (x, column) in line.split_whitespace().enumerate() {
            for (y, ch) in column.chars().enumerate() {
                if ch == '1' {
                    frame.draw_point(x, y);
                }
            }
        }
        frames.push(frame.with_effect(effects));
    }
    for (i, frame) in frames.iter().enumerate() {
        print_packet(&frame.effect.to_bytes(i as u8));
        for chunk in frame.screen.chunks_exact(4) {
            let mut packet = [0u8; 8];
            for (k, &word) in chunk.iter().enumerate() {
                let bytes = word.to_le_bytes();
                packet[k * 2] = bytes[0];
                packet[k * 2 + 1] = bytes[1];
            }
            print_packet(&packet);
        }
    }
}

fn print_packet(packet: &[u8; 8]) {
    let hex: Vec<String> = packet.iter().map(|b| format!("{:02X}", b)).collect();
    println!("{}", hex.join(" "));
}
