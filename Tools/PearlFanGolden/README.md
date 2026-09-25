# PearlFan golden harness

Produces the reference packet stream for `LedFanTests/PearlFanEncoderGoldenTests.swift` from
**pearlfan-rs** (MIT/Apache-2.0, https://github.com/mwja/pearlfan-rs, commit `3d9b32c`).
Nothing from Ventto/pearlfan (GPLv3) is used.

`grid.py` replicates the app's `ColumnRasterizer` (5x7 glyphs from `GlyphFont.swift`, one
blank column per character, glyph top at row 2 of the 11-row arm) and prints one image as
156 columns of 11 `0/1` rows. `src/main.rs` draws that grid through the reference library's
`Frame::draw_point`, then frames it the way `Device::send_animation` does. The two projects
use different fonts, so the grid is the shared input and the packets are the contract.

```bash
python3 grid.py ../../LedFan/Domain/GlyphFont.swift "A" > grids/grid-A.txt
cargo run --release < grids/grid-A.txt > golden/golden-A.hex
```

`grids/` and `golden/` hold the inputs and outputs the tests embed. `Cargo.toml` expects the
reference clone beside the repository; adjust the path if it lives elsewhere.
