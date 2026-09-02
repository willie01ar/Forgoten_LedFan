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

### 1b. Get a read path onto the EEPROM — the strongest untried route

**There is only one fan.** Willie owns no second unit of this or any other class, so
anything requiring a sibling device is off the table. This route is about *his* fan.

The USB bridge is write-only. The EEPROM, if there is one, is not. An SOIC clip plus a ~$10
CH341A programmer — or a Raspberry Pi / Arduino I2C bus — reads and writes it directly,
bypassing the bridge. Four reasons that matters even though the table was erased:

1. **It closes the loop.** Today a write goes into the dark: no ack, no read-back, and the
   only oracle is a cable swap. With a clip, every `A0 <addr> <data>` packet can be verified
   byte for byte. That turns blind guessing into measurement, and it is the single biggest
   change available to this project.
2. **It confirms or kills the bridge hypothesis in one measurement.** If the bytes we sent
   are sitting at the addresses we sent them to, `A0 <addr> <data>` as a raw I2C write is
   proven. If the chip is untouched, the model is wrong and a day of inference goes with it.
3. **Some of the factory table may survive.** Probing addressed blocks `A0`–`A8` with a
   single address byte — 256 bytes per block. If the part is larger than what was swept
   (a 24C16 spans eight blocks, `A0`–`AE`), untouched regions may still hold original data,
   and the surviving fragments would show the table's structure directly.
4. **It identifies the part**, and therefore the real capacity and addressing model, which
   the probing had to hedge across.

Direct writes then become the fast experiment loop: write a candidate table over I2C, swap
to power, observe. Same cable-swap cost, but with the USB bridge removed as a variable.

**Cheap first step, costing nothing:** open the head and photograph the PCB. Look for an
8-pin SOIC marked `24C02` / `24C08` / `24C16`, `AT24…`, `BR24…`, or `FM24…`, and note the
MCU marking. If there is no discrete EEPROM, the storage is internal to the MCU, this route
closes, and we have learned that for the price of a screwdriver.

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

**Start with the text hypothesis, not the byte sweep.** The fan stores 8 messages of 26
characters, so try sending ASCII before anything else: a header byte followed by 7
characters, four packets to a message, with a slot index somewhere in the header. Vary one
thing at a time — slot, packet index, first byte — and watch for the text appearing at all,
even garbled. Garbled text is a solved protocol; a blank fan is not.

Only fall back to the sweep below if the text hypothesis produces nothing.

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
