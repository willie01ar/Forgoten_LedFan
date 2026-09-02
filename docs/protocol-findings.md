# Protocol findings

Append-only log of what the SONiX `0x0C45:0x7701` fan does and does not respond to.
Negative results are recorded on purpose. Tool: `Tools/HIDFan/hidfan.swift`.

Conventions: `OUT` is an 8-byte output report via `IOHIDDeviceSetReport`, `FEAT` a feature
report, `IN` an input report arriving on the interrupt endpoint. Report ID is always 0.

---

## 2026-09-01 — first contact, no visual observer

Session ran without anyone watching the blades. Only what the USB side reports is recorded.

### Opening the device

| Path | `IOHIDDeviceOpen` | `GET_REPORT(Feature)` |
|---|---|---|
| `IOHIDManagerOpen` first, then `IOHIDManagerCopyDevices`, then `IOHIDDeviceOpen` | success | fails `0xE00002CD kIOReturnNotOpen` |
| `IOHIDManagerSetDeviceMatching` → `IOHIDManagerCopyDevices` → `IOHIDDeviceOpen`, manager never opened | success | succeeds |

Reproduced inside and outside this session's command sandbox, so it is not a sandbox
effect. **Rule: never call `IOHIDManagerOpen` on this device.** `HIDFanTransport` and the
probe both use the second path now.

### Listening

Opened and sent nothing for 8 s, then 5 s on a second run: **no unsolicited input
reports**. The device does not talk first.

### Feature report

`GET_REPORT(Feature, id 0)` returns `25 7F 75 08 95 08 B1 02`.

That is the last eight bytes of the device's own 41-byte report descriptor, minus the
closing `C0` (`… 25 7F 75 08 95 08 B1 02 C0`). The firmware appears to answer a feature
read from a buffer that still holds the descriptor tail. Reproducible across runs. It is
not device state, so the feature report is **not** a Rosetta stone. Not yet checked
whether it changes after a write.

### Output reports

See the entries below as they are added.

#### OUT `00 00 00 00 00 00 00 00`
`IOHIDDeviceSetReport` returned success. No input report followed. Immediately afterwards
`GET_REPORT(Feature)` returned `21 09 00 02 00 00 08 00`, which is byte for byte the USB
SETUP packet of the SET_REPORT transfer just sent: `bmRequestType 0x21`, `bRequest 0x09`
(SET_REPORT), `wValue 0x0200` (Output, id 0), `wIndex 0`, `wLength 8`.

So the feature report is an echo of the firmware's endpoint-0 buffer: it shows the last
control request the device processed, not our payload and not display state. Two uses:

- It proves a write reached the firmware, one level below `IOHIDDeviceSetReport` success.
- It cannot tell us what the payload did. Visual observation is still the only oracle.

#### Sweep: first byte `0x00`…`0xFF`, remaining seven bytes zero, 150 ms apart
All 256 writes returned success. **No input report at any value. No write failure at any
value.** Nobody was watching the blades, so whether any value changed the display is
unknown; the sweep must be repeated with an observer. What is established: the firmware
does not reject or acknowledge any first byte over USB.

#### Walking bit: a single 1-bit through all 64 bit positions, 150 ms apart
All 64 writes returned success, no input report, no failure. Same caveat: unobserved.

### Absent-device path, in the app
With the data cable out, the sandboxed app reports "No LED fan found. The USB-A cable
only powers the fan; the data cable must be in the fan's second port." via
`HardwareChecklistUITests` run with `LEDFAN_HARDWARE=absent`. Passed.

---

## 2026-09-01 — prior art: the Jaycar GH1031 protocol (SONiX 0x0C45:0x7160)

`github.com/fergofrog/microwave_usb_fan` documents a sibling device: same vendor, a POV
message fan with **11 pixels per column**, 8-byte HID output reports, and an
acknowledgement on the interrupt IN endpoint. Product ID differs (`0x7160` vs our
`0x7701`). Untested on our fan as of this entry; the next probing step is to send its
first packet and watch for the ack.

Wire format, from `usbfan/protocol.py` (the 9-byte hidapi buffer's leading `00` is the
report ID, so the fan sees 8 bytes):

```
first packet   40 40 d0 d1 d2 d3 d4 ck
later packets  40 23 d0 d1 d2 d3 d4 ck      ck = (40 + 40|23 + d0..d4) & 0xFF
ack (IN)       24 80 ...                     read after every packet
```

Data stream chunked five bytes per packet:

```
[ floor(log2(max(len>>6, 2))) ][ len lo ][ len hi ][ 00 ][ 00 ]        not subtracted
[ A4 ][ 24 - messageCount ][ message bytes... ][ A4 x10 ]                 subtracted
```

Every byte from the second packet on is sent as `(0xA4 - x) & 0xFF`. A message is
`[columnCount+2][00][style][open<<4 | close][00 00][columns reversed, 2 bytes each,
high byte first][00 00]`. A column is a 16-bit word: bits 0–10 pixels (bit 0 innermost),
bits 13–15 colour (red 0x2000, blue 0x4000, green 0x8000). Column count must be a
multiple of 8, at most 144; at most 7 messages. Styles: 0 anticlockwise, 1 clockwise,
2 flash, 3 remain.

If our fan answers `24 80` to the first packet, `FanPacketEncoding` gets a real
implementation and `SequencedColumnEncoder` goes.

### First Jaycar-format upload — 2026-09-01, no observer
Sent one program: one message, 8 columns alternating fully lit (red) and blank, style
"remain" (packets in `Tools/probe-output/jaycar-programA.hex`). All 8 `SET_REPORT`s
succeeded, 250–300 ms apart.

- **No interrupt-IN report** at any point, including 3 s after the last packet.
- **`GET_REPORT(Input)` is another endpoint-0 echo.** It returns 4 bytes: the last SETUP
  packet. After each program packet it reads `21 09 00 02` (SET_REPORT setup); read twice
  in a row it reads `A1 01 00 01`, the setup of the previous GET_REPORT(Input) itself. So
  the control pipe cannot carry the `24 80` ack; only the interrupt endpoint could.
- Whether the interrupt-IN listener in `hidfan` works at all is **unverified**: this
  device has never produced an input report through it, and there is no second device on
  a vendor usage page to use as a control. Treat "no ack seen" as inconclusive until the
  listener has a positive control or the blades are observed.

Second run of the same program was corrupted by a tool bug (all-zero reports interleaved
between packets) and is discarded; the bug is fixed (unknown REPL input is no longer sent).

### Observation after the Jaycar upload — 2026-09-01, Willie at the fan
Data cable out, power cable in, head spinning: **the factory default message is still
showing.** The Jaycar-format program did not replace it (or was not accepted). Also
established: the data port is on the rotating head, so uploads happen with the head
stationary and results are only visible after swapping cables. See `hardware.md`.

## 2026-09-01 — second prior-art variant: `marcin-osowski/usb_fan` (UF-211-06RGB)

Same family, newer hardware (`1a86:5537`, a WCH chip with bulk endpoints) but the author
states the older units were `0c45:7160` and believes the message format is identical.
The repository archives the original Windows "LED Fan Editor" software, old and new,
which is the route-1 artefact: the old version speaks to `0c45:7160`.

Framing is identical to the Jaycar variant: `40 40 order lenLo lenHi 00 00 ck` then
`40 23 d0..d4 ck`, `ck = sum of the 7 preceding bytes`, ack `40 24 80` (bad: `40 24 82`).
Message body differs: `00 81 [cols+2, 16-bit LE] 00 00 00 00` then columns reversed, two
bytes each big-endian, bits 0–10 pixels, bits 13–15 colour (red bit 13, blue 14, green
15). Every message byte is sent as `(0x1A4 - x) & 0xFF`. The driver sends the whole
message **twice**, one second apart, with the head stationary, "to work around timing
problems".

Uploaded this variant to our fan (8 columns, alternating full/empty red): all packets
accepted, no interrupt-IN report. Awaiting the cable swap to see whether the stored
message changed.

## 2026-09-01 — the archived "LED Fan Editor" (route 1), static analysis

Source: `assets/` in `marcin-osowski/usb_fan`. The "old" and "new" ISOs are byte-identical
(md5 `512bb546…`), volume label `LEDFAN_211_06RGB`. Contents: `LedFan.exe` (MFC),
`LIB/WxkUSB.dll` (imports `HID.DLL` + `SETUPAPI`, references `SonixUSB.DLL`), `LIB/She.dll`,
a WCH CH375 driver package, 11-row and 16-row font tables (`the_11ASCII.bin`,
`the_16ASCII.bin`), and `LedFan.Ini` (`LedType=2`, `LedColor=2`, `LedScrW11=142`, UI
strings for open/close/display effects that match the Jaycar enums exactly).

**The editor only knows product `0x7160`.** Every call to `OpenUSBDevice` in `LedFan.exe`
is `push 0x7160; push 0x0C45` (four sites). The bytes of `0x7701` do not occur as an
immediate anywhere in the binary. The CH375 path is for the `1a86:5537` hardware.

Conclusion: this editor, and therefore the two message formats derived from it, were
never meant for our `0c45:7701`. Its Windows-HID transport is the same as ours
(`HidD_SetOutputReport` = SET_REPORT over the control pipe), so the transport is not the
problem; the firmware on our head speaks something else. Our fan's own software has not
been located.

`WxkUSB.dll` transport, from disassembly: `OpenUSBDevice(vid, pid)` enumerates the HID
class with SetupDi, opens each path with `CreateFileA` and compares `HidD_GetAttributes`
VID/PID. `WriteUSB` is `WriteFile` + `GetOverlappedResult`, `ReadUSB` is `ReadFile` +
`GetOverlappedResult`. On Windows, `WriteFile` to a HID device without an interrupt OUT
endpoint becomes SET_REPORT on the control pipe (same as our `IOHIDDeviceSetReport`), and
`ReadFile` reads the **interrupt IN** endpoint. So for the `0x7160` fan the `40 24 80`
acknowledgement arrives on the interrupt endpoint, never via GET_REPORT. The library's
exported `HidD_GetInputReport` wrapper is not what the editor calls.

### Observation after the second-format upload — Willie at the fan
No change. The head still cycles its factory demo: **8 messages of up to 26 characters
each**, which matches the retail listing "USB LED fan with programmable text, up to 8
messages, 26 letters, comes with 3-inch CD". No box, CD, or markings survive, and the
rotating head cannot be opened without risk, so chip identification is off the table.

Net so far for `0c45:7701`: 256 first-byte values, 64 single-bit frames, all-zero frames,
and two complete programs in the sibling formats were all accepted at the USB level and
none changed the stored program. No reply on the interrupt endpoint, ever.

## 2026-09-01 — header sweep (route 3, shotgun then bisect)

Tool: `Tools/HIDFan/shotgun.py` via hidapi. Every two-byte header `00 00`…`FF FF`
followed by six `0xFF` bytes, 65,536 output reports, one write every ~3 ms (206 s total).

Pass 1: **65,535 accepted, 1 write failure, 0 input reports.** The failing header was not
logged; pass 1b repeats the run with it logged. Observation of the stored program after
both passes pending.

Pass 1b (identical packets, failure logged): **the one failure is header `A0 18`**, payload
`FF FF FF FF FF FF`. `IOHIDDeviceSetReport` returned `0xE00002D6 kIOReturnTimeout`. Same
packet in both passes, so deterministic. Every other packet before and after it succeeded,
so the firmware recovered on its own. A timeout, not a STALL, means the device accepted
the SETUP stage and then held the transfer: consistent with the firmware running a
blocking operation (EEPROM write/erase, or a long-running command) on receipt.

**First packet this fan has reacted to.** Observation of the stored program after the two
sweeps pending; then bisect the neighbourhood of `A0 18`.

### Observation after the two header sweeps — Willie at the fan
**All LEDs off. No message at all.** The factory demo that survived every previous
write is gone after a pass that sent every two-byte header with a `FF FF FF FF FF FF`
payload. Working hypothesis: some header family is a memory write, the all-ones payload
landed in program storage, and an all-ones program displays as nothing (erased-EEPROM
state). The demo is presumably recoverable once a program can be written properly.

### The stall is a 5 s SET_REPORT timeout, and it moves
From the sweep timestamps the `A0 18` failure cost ~5 s: macOS's control-transfer timeout,
so the firmware held the transfer for at least that long, then recovered. Sent alone,
`A0 18 FF…` completes in 2.5 ms. Re-sending only the `A0` block (`A0 00`…`A0 FF`, payload
`FF`) stalled at **`A0 23`** instead, with slow writes at `A0 1A` (27 ms) and `A0 24`
(61 ms); every other packet took ~3 ms. So the stall depends on preceding packets, and
tens-of-ms writes appear only in the `A0` family.

**Hypothesis: the packet is a raw I2C transaction and the head is a HID-to-I2C bridge.**
`0xA0` is the write address of a 24Cxx EEPROM (`0xA1` read; `0xA2/A4/A6` the upper 256-byte
blocks of a 24C08). `A0 18 FF FF FF FF FF FF` would mean "write six 0xFF bytes at EEPROM
address 0x18". The slow packets are EEPROM page-write cycles; the sweep's all-ones payload
erased the whole bitmap, which is why the display went dark. Being tested next.

Timing across families (256 packets each, `FF` payload): `A1`, `A2`, `A4`, `A6`, `A8`, `50`
all uniformly ~3 ms, no stalls. Only `A0` shows tens-of-ms writes and the 5 s stall.

Read attempts: `A1`-headed packets in six shapes produce **no interrupt-IN report** (hidapi,
800 ms timeout each) and the feature report stays the setup-packet echo. There is no read
path; the bridge is write-only from the host's point of view. The display remains the only
oracle.

### Experiment E1 — zeros everywhere, 8-bit address model
`[blk][addr][00 ×6]` for blk in `A0 A2 A4 A6`, addr 0…255 step 6 (172 packets, 10 ms
apart). Purpose: polarity and bitmap model. If zero means "LED on", the disc lights.
Observation pending.

### E1 result — Willie at the fan
**Still dark** with zeros everywhere. Together with the all-ones result: the storage is
not a raw bitmap with either polarity. It is a table the display firmware parses, and both
fills produce an empty table. Motor status not yet confirmed.

### Experiment E2a — the family's stored stream, un-obfuscated, at address 0
Both sibling reverse-engineerings agree on the stream once the `40 40`/`40 23` framing and
the 0xA4 obfuscation are removed: `00 81 N 00 S T 00 00`, columns reversed (2 bytes each,
big-endian, bits 0–10 pixels, bit 13 red), `00 00`, trailing zeros. `N` = columns + 2,
`S` style (3 = remain), `T` = open<<4 | close. Written for one message of 8 alternating
full/blank red columns, hedged for 8-bit and 16-bit EEPROM addressing in one pass
(`Tools/HIDFan/write_stream.py`, stream in `Tools/probe-output/stream-E2a.hex`).
Observation pending. If dark: E2b = the same stream with the 0xA4 obfuscation kept.

### E2a result — Willie at the fan
**Still dark. Motor spins normally**, so the head is alive.

### Experiment E2b — same stream, 0xA4 obfuscation kept
Every byte sent as `(0xA4 - x) & 0xFF`, written 16-bit model first then 8-bit model last
(an 8-bit device ends with the correct bytes; a 16-bit device gets the correct stream plus
six stray 5-byte chunks scattered at high addresses). Observation pending.

### E2b result — Willie at the fan
**Still dark, motor fine.** Both published formats of the family, in both encodings, are
rejected by this head. Whatever table it parses has not been published.

### Experiment E3 — full header sweep, patterned payload
Every two-byte header `00 00`…`FF FF` with payload `55 AA 55 AA 55 AA`
(`Tools/HIDFan/shotgun.py` with the payload changed). Purpose: does *any* header feed
displayable data? Observation pending.

E3 USB side: 65,536 packets, 0 input reports, 1 failure: the 5 s stall at **`A0 19`**.
Across three full runs and one `A0`-only run the stall has been at `A0 18`, `A0 18`,
`A0 23`, `A0 19`: always in the `A0` family, always in the 0x18–0x23 range, independent
of payload (`FF` or `55 AA`). Observation of the display pending.

### E3 result — Willie at the fan
**Still dark, motor fine.**

---

## State of knowledge at the end of 2026-09-01

**Established**
1. Programming and display are exclusive phases: the data port is on the rotating head.
   Every observation costs a cable swap. Nothing can be observed live.
2. The head is write-only over USB: no interrupt-IN report has ever been produced (own
   listener and hidapi), and every GET_REPORT, input or feature, returns the last USB
   SETUP packet. There is no acknowledgement and no read-back.
3. `IOHIDManagerOpen` must not be called; match, then open the `IOHIDDevice` directly.
4. Every 8-byte output report is accepted, except that packets whose first byte is `A0`
   sometimes take tens of milliseconds and, once per long run, block for the full 5 s
   host timeout, always with second byte in 0x18–0x23. No other first byte ever does
   this. `A0` is the only header the firmware demonstrably processes.
5. A sweep of all 65,536 two-byte headers with an all-ones payload **erased the factory
   demo** (8 messages × 26 characters). Since then the display has stayed dark through:
   zeros in blocks `A0`–`A6` (8-bit addressing), the Jaycar/UF-211 stored stream
   un-obfuscated and obfuscated (both addressing models), and a full header sweep with
   a `55 AA` payload. The display is driven by a parsed table, not a raw bitmap, and the
   table format is not the one used by the `0c45:7160` / `1a86:5537` siblings.
6. The archived vendor editor targets `0x7160` only; no software for `0x7701` was found
   anywhere, and the USB ID registry has no entry for it.

**Best current model.** The head's MCU is a HID-to-I2C bridge or something shaped like
one: `A0 <addr> <data…>` writes bytes into an EEPROM at address `A0`, which holds the
message table the display firmware parses. The table format is unknown and is not the
sibling format. The factory demo lived in that table and has been overwritten.

**Not tried, by decision:** feature-report writes (SET_REPORT Feature). The owner did not
authorise them. They remain the one untouched channel, and the one most likely to reach
configuration or firmware state.

**What would move this forward**
- The software that shipped with a `0c45:7701` fan, from anyone who still has the CD.
  Its upload routine would give the table format in an afternoon.
- A second, unmodified fan of the same model, to read nothing from (there is no read
  path) but to capture its programming traffic from the vendor software under a VM.
- Failing both: feature-report probing with the owner's consent, then structured guesses
  at the table (message count byte, per-message length, column pairs) each costing a swap.
