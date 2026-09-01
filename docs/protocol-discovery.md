# Protocol discovery

The one genuinely unsolved problem. The app is straightforward; this is not.

## What we know

8-byte frames. Report ID 0. Output and Feature reports both available, both 8 bytes. An
interrupt IN endpoint exists, so the device *can* talk back — that feedback channel is the
most valuable asset in this effort.

No public documentation exists for `0c45:7701`.

## Routes, best first

### 1. The bundled Windows app — highest leverage by far

The fan shipped with a Windows utility. It has never been run (no Windows machine), but if
the installer can be found, `strings` and a disassembler give the VID/PID it opens and
usually the command framing directly. An afternoon of static analysis beats a week of
blind probing.

**Status: not yet located.** Worth real effort before falling back to route 3.

### 2. USB capture

Run the Windows app under a VM with USB passthrough and capture the traffic, or use
Wireshark with `usbmon` on Linux. Reliable when the app exists but resists static analysis.

### 3. Blind probing

Use `Tools/hidfan` (build with `Tools/HIDFan/build.sh`).

```
./hidfan              interactive: type hex bytes, watch the fan
./hidfan sweep        first byte 0x00...0xFF, one per 150ms
./hidfan bits         walk a single 1-bit through all 64 bits
```

Method, in order:

1. **Listen first.** Open the device and send nothing. Does it emit input reports
   unprompted? Anything it says unbidden is free information.
2. **Read the feature report** (`g`). Devices like this often expose current state there,
   and a readable state field is a Rosetta stone.
3. **Sweep the first byte.** Watch both the fan and the IN endpoint. A command byte that
   provokes *any* response — a change in the blades, an input report, a write failure —
   narrows the space enormously.
4. **Walk single bits.** If a column of LEDs lights in a pattern that tracks the bit
   position, the frame layout is direct-mapped and the problem is essentially solved.
5. **Look for framing.** Most devices of this vintage use a start marker, a length or index
   byte, payload, and sometimes a checksum. Try `0x00`-prefixed and `0xFF`-prefixed frames.

**Record every result in `protocol-findings.md`** — create it, append as you go, including
the negative results. Knowing that `0x00`–`0x3F` do nothing is worth as much as knowing
what `0x40` does, and it is exactly what gets forgotten between sessions.

## Guardrail

Writing arbitrary bytes to a device with unknown firmware can in principle brick it. This
device is old, cheap, and already unusable from macOS, so the risk is acceptable — but do
not write to the Feature report space blindly if the Output space is producing results.
Feature reports are more likely to touch configuration or firmware state.
