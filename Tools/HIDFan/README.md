# HIDFan probes

Throwaway reverse-engineering tools for the SONiX `0c45:7701` head. Not part of the app,
not held to the app's standards. Findings go in `docs/protocol-findings.md`.

- `hidfan.swift` — Swift/IOKit REPL: `./build.sh`, then `./hidfan`, `./hidfan listen`,
  `./hidfan feature`, `./hidfan sweep`, `./hidfan bits`. Never calls `IOHIDManagerOpen`.
- Python probes use hidapi, in a throwaway venv (third-party, tools only):

  ```bash
  python3 -m venv .venv && .venv/bin/pip install hidapi
  .venv/bin/python shotgun.py 00 FF        # every 2-byte header, 0xFF payload (erases the demo!)
  .venv/bin/python timed_sweep.py A0 A0    # one first-byte block, per-write timing
  .venv/bin/python fill.py 00 A0 A2 A4 A6  # fill EEPROM blocks, 8-bit address model
  .venv/bin/python write_stream.py --file ../probe-output/stream-E2a.hex
  .venv/bin/python probe_a018.py           # neighbourhood of the one reacting header
  ```

The data port is on the rotating head: plug the data cable in to program (head still),
swap to the power cable to see the result. One swap per observation.
