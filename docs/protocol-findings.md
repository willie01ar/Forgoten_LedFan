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

---

## 2026-09-02 — THE VENDOR SOFTWARE WAS FOUND

Route 1d (search in Chinese / non-English sources) succeeded where the English-language
search of slice 3 failed. The editor is **"LedFan Editor"**, mirrored on a French hobbyist
site: `https://www.zpag.net/Electroniques/Zip/LedFan.zip`. Now in `Vendor/`.

Contents: `LedFan.exe` (MFC, PE32, dated 2014-05-08), `LIB/WxkUSB.dll` (45 KB),
`LIB/LedFan.Ini` (UTF-16), font tables `THE_7ASCII.bin` / `the_11ASCII.bin` /
`the_16ASCII.bin` / `the_11FH.bin` / `the_16FH.bin`, Chinese fonts `UserZK11.fnt` (1.4 MB)
and `UserZK16.fnt` (2.0 MB), a vendor manual PDF, and a saved project
`Rien compris.LDAT` (7532 bytes) containing real message data.

### The transport layer is confirmed
`WxkUSB.dll` is a renamed **`SonixUSB.DLL`** — the export directory still carries the
original name. Exports: `OpenUSBDevice`, `CloseUSBDevice`, `ReadUSB`, `WriteUSB`,
`SetOutputReport`, `GetInputReport`, `GetInputLength`, `GetOutputLength`, `GetErrorMsgA/W`.
Imports: `SetupDiGetClassDevsA`, `SetupDiEnumDeviceInterfaces`, `HidD_GetHidGuid`,
`HidD_GetAttributes`, `HidD_GetPreparsedData`, `HidP_GetCaps`, `HidD_SetOutputReport`,
`HidD_GetInputReport`, `CreateFileA`, `WriteFile`.

This is exactly the mechanism slice 3 inferred: HID enumeration, then output reports.

**`WriteUSB` (RVA 0x1180) is a thin wrapper over `WriteFile`.** It does no framing. The
packet structure is therefore built in `LedFan.exe`, which is where the remaining work is.

### The PID is the sibling, not ours
`LedFan.exe` calls `OpenUSBDevice` at three sites, each as
`push 0x00007160 / push 0x00000C45 / call OpenUSBDevice` — file offsets 0x1fdde, 0x2019f,
0x20314. Hardcoded to **0x0C45:0x7160**. Our head is **0x0C45:0x7701**: same vendor, same
DLL family, different product. No occurrence of 0x7701 as an immediate anywhere in the exe.

So this editor will not drive our fan as-is. Its value is that it reveals the family's
framing, which the community reconstructions slice 3 tested may have gotten wrong.

### `LedFan.Ini`
`LedType=2`, `LedGap11=1`, **`LedScrW11=142`**, `LedColor=255`, `UseMidMode=0`, `bUserFont=0`.
Effect vocabulary matches the sibling format's style/effect bytes: nine opening effects
(B1-B9), four middle (D1-D4: contra/clockwise rotation, flash 3 times, remain), seven
closing (E1-E7). Character limits vary by LED type and font: 20 English per segment, 13 or
10 Chinese.

Note our fan holds **26** characters, and this build's limit is 20 — further evidence
0x7701 is a different, probably later, variant.

### Font tables — the host rasterises, the fan does not
Sizes are exactly `80 + 256 * n`: `THE_7ASCII.bin` = 80 + 256x8, `the_11ASCII.bin` and
`the_16ASCII.bin` = 80 + 256x16. That reads as an 80-byte header plus 256 glyphs of
8 columns, at 1 byte per column for 7 LEDs and 2 bytes per column for 11 and 16.

**The editor shipping its own font tables is strong evidence the host rasterises text and
uploads columns, rather than sending characters to a firmware font.** This contradicts the
assumption behind D5 and needs an architect decision once confirmed.

**The font data is obfuscated.** High bytes are uniformly 0x2f or 0x3f and glyphs do not
render under a direct reading. It is NOT the 0xA4 subtract scheme from the sibling
reverse-engineerings — that yields no small high bytes. A decoding constant or scheme has
to be recovered; the ASCII tables are ideal for this because the plaintext is known: glyph
0x41 must look like an "A".

### What this changes
- Route 1 is no longer closed. The artefact exists and is in the repository.
- The remaining question is narrow and static: how does `LedFan.exe` build the buffer it
  hands to `WriteUSB`, and how are the font tables encoded?
- No cable swaps are needed for any of it.

---

## 2026-09-02 — Slice 5: static analysis of `Vendor/LedFan/LedFan/LedFan.exe`

Build analysed: `LedFan.exe` md5 `49ac6bd7f675e027aad49b9c4f52f656`, PE32, ImageBase
`0x400000`, `.text` RVA `0x1000` at file offset `0x400` (so `VA = file + 0x400C00`).
`LIB/WxkUSB.dll` md5 `4e3f3bffbffa1da1d32e5b9e13cbd1c9`, byte-identical to the DLL in
the ISO analysed in slice 3; the exe is a different build from that ISO's (`92df5dfb…`), so
the ISO offsets do not apply here. Tools: pefile 2024.8.26, capstone 5.0.7, in a throwaway
venv. Nothing in `Vendor/` was executed or modified.

### Task 1 — how the exe builds what it hands to `WriteUSB`

**Dynamic import.** `WxkUSB.dll` is not in the import table. At file `0x019866`–
`0x0198cd` the exe resolves four names with `GetProcAddress` (via `[0x550418]`) into
globals: `[0x5abd9c] = OpenUSBDevice`, `[0x5abd98] = CloseUSBDevice`,
`[0x5abd94] = WriteUSB`, `[0x5abd90] = ReadUSB`. Every USB call goes through those.
`GetOutputLength` and the other exports are never resolved.

**The send routine, VA `0x420d70` (file `0x020170`).** Takes `esi` = a 9-byte buffer and
`edi` = handle (0 means "open now"):

```
020170  al = buf[7]+buf[6]+buf[5]+buf[4]+buf[3]+buf[2]+buf[1]; buf[8] = al   ; checksum of bytes 1..7
02019e  if no handle: OpenUSBDevice(0x0C45, 0x7160); -1 -> "USB Device Connect Failure!!!"
0201f6  WriteUSB(handle, buf, 9, &written)                                   ; 9 = report id + 8
020238  ReadUSB(handle, ack, 3, &read)                                       ; 3 bytes
02025c  ack[2] -> lookup table at 0x420d0c (index ack[2]-0x2a, 0x2a..0x8a) ; error text
020261  ack[2] == 0x80 -> success
```

So the **report is `00` + 8 bytes**: 7 payload bytes and a trailing checksum that is the
byte sum of the 7. The **acknowledgement is 3 bytes** read from the input report; the
third byte must be `0x80`. On Windows the first byte of a read is the report id (0), so the
device's own reply begins at the second byte: two meaningful bytes, of which the second is
the status. That is the sibling reconstructions' `24 80` exactly.

**The upload routine, VA `0x420e90` (file `0x020290`).** Reads the serialised stream at
`this+0x4fdac` with length `this+0x4fda8`, and the mode at `this+0x54510`:

```
020307  size class: len < 0x100 -> 1, < 0x200 -> 2, < 0x400 -> 3, < 0x800 -> 4,
        else "IC ROM Over"                                          ; store is 2 KB
02031d  OpenUSBDevice(0x0C45, 0x7160)
0203d6  header report:  40 40 <size class> <b4> <b5> 00 00 (+ checksum)
            mode == 1:  b4 b5 = 0A 00                                (0203f4)
            otherwise:  b4 b5 = len & 0xFF, len >> 8                 (020420)
020477  packet count = len / 5 (integer division; any remainder is never sent)
0204d3  data reports:   40 23 d0 d1 d2 d3 d4 (+ checksum), five stream bytes each,
            mode == 1:  each byte sent as (0xA4 - byte) & 0xFF        (0204e2 ...)
            otherwise:  bytes sent raw
0205a2  CloseUSBDevice. No terminator report.
```

Every report goes through the send routine above, so every one of them waits for the
3-byte acknowledgement. Progress-bar messages `0x401`/`0x402` are interleaved.

**The serializer, VA `0x4203f0` (file `0x01f7f0`).** Builds the stream in a 0x4000-byte
member buffer. Offsets below are file offsets.

```
01f826  zero the buffer, len = 0
01f83e  count = number of non-empty messages (call 0x41ec70); 0 -> "No Data Send!"
01f86c  mode 1: emit 00, then (count | 0x80)          ; mode 0: emit 00, count ; else: count only
01f8f4  for each message i (dialog controls 0x1005+i, at most 12):
01f90a     open   = combo (id-0x64)  ; middle = combo (id) ; close = combo (id+0x384)   (CB_GETCURSEL 0x147)
01f99c     total  = message column count (from the character table, [ebp+0xfc] chars)
01f9ae     emit  total + 2
01f9cb     emit  00
01f9ec     emit  middle if UseMidMode (global 0x5aeb6c) else 03            ; "remain"
01fa10     emit  (open << 4) | close
01fa2a     emit  00 ; and a second 00 unless mode == 0
01fa56     rasterise the characters into n records of 0x54 (84) bytes, sort (qsort, cmp 0x415db0)
01fab3     for each character from the LAST to the first:                 ; reversed
01fad6        for each of rec[0x0b] bytes starting at rec[0x0c]:          ; 2*width bytes, LE words
01faeb           mode 0: bits 1,2,3 -> 0,1,2 (7-LED row remap)
01fb27           mode 1 and (byte & index) != 0: in-place bit permutation over bits 15..5
                 of the last two bytes (0x1fb3b–0x1fbc5; not fully decoded, see below)
01fb0f           emit byte
01fc05     emit 00 ; and a second 00 unless mode == 0
01fc8e  after the last message: emit 8 x 00
01fd48  call the upload routine
```

The 84-byte character record is the same one the `.LDAT` project file stores (Task 3):
`u16 char, u16 width, u16 0, u16 height, u16 0, u8 0, u8 length = 2*width, u16 0`, then
`width` little-endian 16-bit columns from offset 12, zero padded to 84 bytes.

**Modes.** `this+0x54510` is set by VA `0x41fe90` (file `0x01f290`) from its first
argument. Callers push `0` (file `0x01f1b5`), `1` (`0x01f215`) and `2` (`0x01f275`) from
three adjacent menu handlers, and the saved value from `this+0x54518` on startup
(`0x01ece1`). Together with the three font tables (7, 11, 16 rows) and the 7-LED row remap
in mode 0, the reading is: **mode 0 = 7 LEDs, mode 1 = 11 LEDs, mode 2 = 16 LEDs.** The
INI's `LedType=2` is this value.

**What this settles about the sibling reconstructions.** For mode 1 (the 11-LED
`0x7160` fan) the exe produces exactly the stream the Jaycar project reverse-engineered:
`00`, `0x80|count`, per message `[cols+2][00][style][open<<4|close][00 00]`, columns
reversed, `[00 00]`, trailing zeros, all 0xA4-subtracted on the wire behind `40 40` /
`40 23` reports with a byte-sum checksum. Two differences from that reconstruction: this
build's mode-1 header carries a fixed `0A 00` where the Jaycar code puts the real length,
and this build appends 8 trailing zeros, not 10. Neither matters for the 0x7701 question:
the sibling stream was already tried on our head, in both encodings, and rejected.

**Not fully decoded.** The mode-1 bit permutation at `0x01fb3b`–`0x01fbc5` runs only when
`(byte & byte_index) != 0`, walks bit positions 15 down to 5 of the two most recent bytes,
and sets or clears one destination bit per source bit. Its exact mapping was not derived;
on the evidence of the Jaycar capture it leaves the pixel bits 0–10 in place, so it most
likely touches only the colour/flag bits. It is recorded here as a gap, not guessed at.

**Secondary sites.** File `0x01fdcf`: a connection test that opens the device, reports to
dialog items `0x172`/`0x173`, and closes. File `0x0201a8`, `0x02031d`: the opens listed in
the brief (`0x1fdde`, `0x2019f`, `0x20314` are the `push 0x7160` instructions immediately
before them). Strings: "USB Device Connect Failure!!!", "USB Write Data Error", "USB Read
Data Error", "USB Write Data Failure!", "IC ROM Over", "No Data Send!".

### Task 3 — `Rien compris.LDAT`

7532 bytes = a 140-byte header + 88 records of 84 bytes. Header (little-endian u16):
`0x2345 0x3011` (magic), `1` (version), `0x00A0`, `0x000B` (11 = LED rows), `5`, `0x0420`,
`0x0130`, `0x0010`, `0x0400`, zeros, then at `0x4c` **eight u16 character counts, one per
slot**: `17, 25, 22, 24, 0, 0, 0, 0`. The records follow in slot order with no separators.
The four messages are French: "T'as Rien compris", "M, Vomis n'a rien compris", "Serge n'a
rien compris", "Michel a toujours raison" — 102, 157, 133 and 143 columns.

Each record is the serializer's character record (layout above). The column word maps
**row 0 to bit 15 and rows 1–8 to bits 0–7** (rows 9–10 would be bits 8–9): it is
"row r at bit r" rotated right by one. Rendering with that mapping gives clean Arial-style
glyphs, for example:

```
'T' 0000 0000 8000 8000 801f 8000 0000    'R' 0000 0011 800e 8002 8002 801f 0000
    ..####.                                   ..####.
    ....#..                                   .#...#.
    ....#..                                   ..####.
    ....#..                                   ..#..#.
    ....#..                                   ..#..#.
    ....#..                                   .#...#.
```

**No per-message effect bytes are in the file.** Opening, middle and closing effects are
read from the dialog's combo boxes at upload time (serializer, `0x01f90a`), not saved with
the project. The header's `0x00A0`, `5`, `0x0420`, `0x0130`, `0x0010` and `0x0400` are
unidentified; the last four look like editor window geometry.

**Relationship to the wire.** The project stores exactly what the serializer emits per
character: width, then `width` 16-bit columns, in the same bit layout, little-endian. The
wire adds only the per-message envelope and the reversal.

### Task 2 — the font tables

**The decoder, not a cipher.** The exe's glyph readers, not the loader, define the format.
File `0x01aea0` (16-row ASCII, table global `[0x5aec2c]`): offset = `4 + (code - 0x20) * 32`,
copy 16 bytes taking **only the even byte of each 16-bit slot** and inverting it (`not dl`,
`0x01aee9`), into an 8-column record (width 8, height 16). File `0x01ae20` (7-row ASCII,
`[0x5aec28]`): offset = `4 + (code - 0x20) * 10`, seven even bytes with stride 2, **not
inverted**, remapped `((b & 7) << 1) | (b & 0xF0)` so bit 3 is dropped and bits 0–2 move up.
File `0x01b8fa` is a 12-column 16-row reader for a "FH" table (stride 64, skip 16). The
11-row ASCII table follows the 16-row rule empirically (stride 32, even bytes inverted).

So: the files begin with a 4-byte magic `ff 3f 7d 3c`; glyph 0 is the space (0x20); there
is no 80-byte header; the odd bytes (`0x2f`/`0x3f`) are never read. That is why every
byte-level scheme failed. Eliminated before the decoder was found: XOR with any single
byte constant, ADD with any constant, the sibling 0xA4 subtraction, position-dependent
XOR keyed on a blank space, bit reversal and nibble swap (no fixed-stride glyph index put a
blank at 0x20 under any of them).

**Row order inside a column word**, per source, with bit 0 = the even data byte's bit 0:

| Source | Rows | Column word | Row r lives in bit |
|---|---|---|---|
| `THE_7ASCII.bin` | 7 | one byte | 0,1,2,4,5,6,7 (bit 3 unused) |
| `the_11ASCII.bin` | 11 (9 used) | LE u16 | rows 0–7 → bits 8–15, rows 8–10 → bits 0–2 |
| `the_16ASCII.bin` | 16 | LE u16 | rows 0–2 → bits 13–15, rows 3–15 → bits 0–12 |
| `.LDAT` / system-font raster | 11 | LE u16 | row 0 → bit 15, rows 1–10 → bits 0–9 |

Four different rotations of "row r at bit r". The serializer copies record bytes verbatim,
so the wire carries the source's layout; only the mode-1 permutation at `0x01fb3b` could
normalise it, and that loop was not decoded. Recorded as a gap.

Evidence, decoded straight from the files:

```
THE_7ASCII.bin  'A' 'B' 'I' 'L' '0' '8'  (stride 10, 5 columns, rows = bits 0,1,2,4,5,6,7 of the even byte)
  ..#..   .####   .###.   ....#   ..##.   .###.
  .#.#.   #...#   ..#..   ....#   .#..#   #...#
  .#.#.   #...#   ..#..   ....#   .#..#   #...#
  #...#   #####   ..#..   ....#   .#..#   .###.
  #####   #...#   ..#..   ....#   .#..#   #...#
  #...#   #...#   ..#..   ....#   .#..#   #...#
  #...#   .####   .###.   #####   ..##.   .###.

the_16ASCII.bin 'A' 'B' 'I' 'L' '0' '8'  (stride 32, 8 columns, even bytes inverted, rows = bits 13,14,15,0..12 of the LE word)
  ....#...   ...#####   ..#####.   .......#   ...###..   ...###..
  ....#...   ..#....#   ....#...   .......#   ..#...#.   ..#...#.
  ...#....   .#.....#   ....#...   .......#   .#.....#   .#.....#
  ...#.#..   .#.....#   ....#...   .......#   .#.....#   .#.....#
  ..#...#.   ..#....#   ....#...   .......#   .#.....#   ..#...#.
  ..#...#.   ...#####   ....#...   .......#   .#.....#   ...###..
  ..#####.   ..#....#   ....#...   .......#   .#.....#   ..#...#.
  .#.....#   .#.....#   ....#...   .......#   .#.....#   .#.....#
  .#.....#   .#.....#   ....#...   .......#   .#.....#   .#.....#
  .#.....#   ..#....#   ....#...   .......#   ..#...#.   ..#...#.
  .#.....#   ...#####   ..#####.   .#######   ...###..   ...###..
  ........   ........   ........   ........   ........   ........
  ........   ........   ........   ........   ........   ........
  ........   ........   ........   ........   ........   ........
  ........   ........   ........   ........   ........   ........
  ........   ........   ........   ........   ........   ........

the_11ASCII.bin 'A' 'B' 'I' 'L' '0' '8'  (stride 32, 8 columns, even bytes inverted, rows = bits 8..15,0,1,2 of the LE word)
  ...#....   .######.   .#####..   ......#.   ..###...   .#####..
  ..#.#...   #.....#.   ...#....   ......#.   .#...#..   #.....#.
  ..#.#...   #.....#.   ...#....   ......#.   #.....#.   #.....#.
  .#...#..   #.....#.   ...#....   ......#.   #.....#.   #.....#.
  .#...#..   .######.   ...#....   ......#.   #.....#.   .#####..
  .#####..   #.....#.   ...#....   ......#.   #.....#.   #.....#.
  #.....#.   #.....#.   ...#....   ......#.   #.....#.   #.....#.
  #.....#.   #.....#.   ...#....   ......#.   .#...#..   #.....#.
  #.....#.   .######.   .#####..   #######.   ..###...   .#####..
  ........   ........   ........   ........   ........   ........
  ........   ........   ........   ........   ........   ........

```

### Task 4 — what transfers to `0x7701`

**Transfers (same vendor, same DLL, same product family):**
- Host-side rasterisation. The editor renders text to 16-bit columns with its own tables or
  the system font, stores columns in the project, and uploads columns. No character codes
  ever go to the fan.
- The message-table model: a message count, per-message `[columns+2][00][style][open<<4|close]`,
  reversed 16-bit columns, and effect vocabularies of 9/4/7 (matching our head's manual).
- A 2 KB store ("IC ROM Over" above 0x800 bytes), consistent with a 24C16 behind a bridge.

**Specific to `0x7160` (and its bridge firmware), not to our head:**
- The `40 40` / `40 23` report framing with the byte-sum checksum and the `24 80` ack.
  Our head answered nothing on the interrupt endpoint to any of it, and a full sweep of all
  two-byte headers with the `40`-family included changed nothing on the blades. The ack
  this exe insists on cannot be produced by our head.
- The 0xA4 obfuscation and the `0A 00` header field are bridge-firmware conventions.

**The `A0` behaviour is inconsistent with this framing.** This exe never emits a report
whose first byte is `A0`; the only way `A0` appears on its wire is as the 0xA4-subtracted
form of a data byte `0x04`, and data reports always start `40 23`. On our head, `A0` is the
one header with write-cycle timing and the stall, and every `40`-headed report is inert.
The two are different protocols. The slice-3 model (a bridge exposing raw `A0 <addr> <data>`
EEPROM writes) stands, and this editor tells us what the *table inside* that EEPROM looks
like for the sibling, which is exactly what E2a/E2b already wrote to our head without result.

**Next experiment for the owner.** None with good odds. The one untested variant this
analysis raises is that the sibling's bridge may store the header's size-class and length
bytes ahead of the stream (EEPROM `[sz][len lo][len hi][00][00]` then the stream). It is a
single swap and a low-probability guess; it should wait for route 1b, where an EEPROM
clip turns the same question into a measurement.

### Task 5 — D5

Recommend revising D5's premise, not its contract. The evidence (font tables shipped with
the editor, columns stored in the project, columns emitted by the serializer) says this
family's hosts rasterise; the "firmware font" branch of the hedge is dead. Keep
`FanMessage` as the transport unit — slots, count and text are real device concepts in
this table — and make the future `MessageTableSerializing` conformance rasterise through
the app's own `MessageRasterizing`, injected. Two numbers for D1 as well: `LedScrW11=142`
is this editor's screen width for the 11-LED fan, and the sample project's messages run
102–157 columns, so 142 is a better preview `columnsPerRevolution` for an 11-LED head than
the placeholder 180.

---

## 2026-09-02 — Slice 6: the last batch (D15)

### A correction to the record before designing anything

Re-reading `Tools/HIDFan/write_stream.py` (E2a): it sent the 8-bit pass first and the
16-bit pass last, and the 16-bit pass's final packet `A0 00 00 s0..s4` lands, on an 8-bit
device, at address 0 as `00 s0 s1 s2 s3 s4`, one byte late. So under the 8-bit model E2a
left the count byte at 0x01 as `00` instead of `81`, and E2a was **not a valid test** of
the un-obfuscated stream at base 0 under 8-bit addressing. E2b's tool wrote the 8-bit pass
last and was valid. The 16-bit-model half of E2a was valid. Net: "un-obfuscated stream at
base 0, 8-bit addressing" is still untested. It is in this batch.

Also: the serializer's stream (Slice 5, Task 1) is byte-for-byte what E2a/E2b wrote apart
from the number of trailing zeros (8 in the exe, 10 in the reconstruction). The brief's
premise that E2a/E2b used a wrong format is not supported; their failures stand (E2b) or
were invalid for the reason above (E2a, 8-bit half).

### The batch

One 256-byte image for block 0, four candidates at non-overlapping bases, every byte from
the serializer's stream format: `00, 0x80|count, [cols+2] 00 03 00 00 00, columns, 00 00,
zeros`. Every lit column is `FF FF` (all rows, all colour bits) and every dark one `00 00`,
so the signatures survive any row rotation, byte order or colour convention, including
whatever the mode-1 permutation does.

| Base | Candidate | Why this base | Signature on the disc |
|---|---|---|---|
| `0x00`–`0x17` | P0: bare stream, 1 message, 6 columns | the E2a retest with a correct write order | one narrow, sharp-edged bright wedge |
| `0x18`–`0x3F` | P1: bare stream, 12 columns | count byte at `0x19`, length byte at `0x1A`: inside the `A0` stall range, where the firmware demonstrably does something | a comb of six hairlines (on/off alternating) |
| `0x40`–`0x6E` | P2: `01 <len> 00 00 00` then the stream, 16 columns | D15 candidate 1, the upload header's five bytes stored ahead of the stream (size class 1, real length; the mode-1 `0A 00` is not a length) | two thick bars (4 on, 4 off, 4 on, 4 off) |
| `0x80`–`0xC9` | P3: bare stream, 32 columns | round-base hedge | one wide, solid bright arc |

Image: `Tools/probe-output/2026-09-02-slice6-image.hex`. Packets, in send order:
`Tools/probe-output/2026-09-02-slice6-packets.hex` (233 reports), built by
`Tools/HIDFan/slice6_batch.py`:

1. 16-bit hedge, page 4 (`A0 04 lo …`) then page 0 (`A0 00 lo …`), descending so the
   `lo = 0` chunk lands last. On an 8-bit device these scribble on bytes 0–9, which step 2
   then repairs.
2. 8-bit block 0 (`A0 a …`, a = 0, 6, …, 0xFA), last: an 8-bit device ends exactly equal to
   the image. On a 16-bit device the `a = 0` packet splats five bytes at `0x0000`, which
   only touches P0, already tested there by E2a's valid 16-bit half.
3. The same image into 8-bit blocks `A2` and `A4`, in case the parser's block is not 0.

Not in the batch, by decision: the retired 1c length hypothesis (D15/brief), feature
reports (D7), any text-shaped payload (row layout unknown; a text hit could not be told
from a garbled one on a single look).

### What each outcome means

- **Dark:** none of the four bases, in either addressing model or in blocks A2/A4, holds a
  table this head will display. With E2b (obfuscated, base 0), E1 (zeros), and the three
  sweeps, that exhausts what the vendor's own serializer can tell us about placement. The
  hardware path closes.
- **One signature:** the base and layout that produced it are identified without a second
  swap. Stop and hand back (brief).
- **Two or more signatures:** the parser walks the block and honours several tables, which
  is itself decisive. Record exactly which.
- **Anything else** (a smear, a flicker, a partial arc): recorded verbatim; it means data is
  being displayed under a layout none of the four intended, which still identifies the
  addressing model.

### Sent — 2026-09-02
All 233 reports accepted in 4.0 s, no failures. One write took 11 ms (`A2 72 00…`, packet
166); none of the `A0` writes stalled or slowed. The packet file was byte-identical to the
committed one. Swap requested; observation pending.

### Observation — Willie at the fan, 2026-09-02
Verbatim: **"Still dark, motor spins fine."** No light of any kind, no signature, nothing
at spin-up. (Button attempts from the checklist: not reported; asked.)

Owner's proposal after the observation: the head has never been programmed **with the
power cable connected (button off) and the data cable in at the same time**. Every upload
so far was made with the head powered only through the data cable's USB 5 V. Recorded as
an owner-initiated variable, outside the slice-6 brief's single-swap scope.

### Re-send with both cables connected — 2026-09-02
Head on the fan's own power cable (button off, head still; the power cable itself was on
the Mac) **and** the data cable at the same time. The device enumerated normally in that
state. The identical 233-report batch was re-sent: all accepted in 3.9 s, no failures, no
slow writes at all this time. Button presses during the previous spin (long, double,
hold-while-powering) did nothing. Observation pending.

### Observation after the both-cables re-send — Willie at the fan, 2026-09-02
Verbatim: **"I saw two or three leds flashing very dim when the head start spinning, it's a
really dim flash that I'm associating with the head receiving power."** No sustained
light, no signature. Whether this spin-up flash existed before this batch is the question
that decides what it means; asked.

Follow-up, verbatim: **"It looks like the flash happen in the third led from the hub and
the third led from the tip. It don't last even a second and it's blue. It happens
instantly when the power arrives even before the blades starts spinning."**

Classification: **a power-on indicator, not a display of the written data.** It appears
before rotation, which a persistence-of-vision display cannot do for table content, and it
is two fixed LEDs (rows 2 and 8 of 11) while every lit column in the batch drove all
eleven rows. Whether the blink predates the batch was asked; the owner had not been
watching the power-on instant in earlier swaps, so it is recorded as "first noticed", not
"new". The head's blue LEDs and its arm geometry (11 LEDs, third-from-hub and
third-from-tip visible) are the only new facts.

**Result of the slice-6 batch: dark.** Both power configurations. Neither of the four
candidate tables, in either addressing model or in blocks A2/A4, is displayed.

---

## The hardware path is closed — 2026-09-02

Written for whoever arrives later with the same fan, `0c45:7701`, SONiX, 11 blue LEDs,
eight messages of 26 characters in its factory demo.

**What the head is.** A USB low-speed HID device on the rotating hub, vendor usage page
`0xFFFF`, 8-byte input, output and feature reports, one interrupt-IN endpoint. It
enumerates only through the data cable in the hub's port; the fan cannot spin while that
cable is in, so nothing can be observed while sending. From the host's side it is
write-only: the interrupt endpoint never produces a report and every GET_REPORT returns
the last SETUP packet. `IOHIDManagerOpen` must not be called on it.

**What was tried, all with the owner observing after a cable swap, eleven swaps in total.**
Every two-byte header with `FF` and with `55 AA` payloads (131,072 reports), every
first byte and every single bit, all-zero fills, the sibling `0c45:7160` fan's complete
message table in its wire form and its stored form, at base 0 in 8-bit and 16-bit
addressing, and finally four candidate tables at bases `0x00`, `0x18`, `0x40` and `0x80`
in the format taken from the vendor editor's own serializer, hedged across two addressing
models and three EEPROM blocks, sent under both power configurations. The only reaction
the head ever gave was timing: `A0`-headed reports occasionally take tens of milliseconds
and once per long run block for the host's 5 s timeout, with the second byte between
`0x18` and `0x23`. One header sweep erased the factory demo; nothing since has lit a
single LED during rotation. Button presses do nothing. Feature reports were never sent.

**What is known for certain about the family.** The vendor editor (`Vendor/`, analysed
statically in slice 5) drives the `0x7160` sibling with `40 40` / `40 23` reports, a
byte-sum checksum, a mandatory 3-byte acknowledgement, and a message table of rasterised
16-bit columns. Our head answers none of that framing and shares only the vendor, the DLL
family and the table's general shape.

**What would reopen this.** The software that shipped with a `0c45:7701` fan; a USB
capture of that software programming one; or a second unit. Nothing else that is free has
been left untried, and this head cannot be opened for a read path.

---

## 2026-09-02 (late) — Lead A closed: there is no handshake packet

The bundled Promier manual says that on connecting the fan "the LED lights flash one by
one, which proves that the connection is successful". That raised the possibility of a
**live oracle**: a command that produces a visible response during the data phase, with no
cable swap. The owner confirmed he has never seen his head do this.

The third `OpenUSBDevice` call site — file `0x1fdde`, VA `0x4209de`, the one slice 5 left
unaccounted for — has now been disassembled. **It is a UI polling timer, and it sends
nothing.**

```
4209a0 (01fda0)  cmp  [esp+4], 2                  ; OnTimer, event id 2
4209cf (01fdcf)  mov  eax, [0x5abd9c]             ; OpenUSBDevice
4209dd (01fddd)  push 0x7160 / push 0x0C45 / call eax
4209ed (01fded)  cmp  ebx, -1 / setne al
4209fc (01fdfc)  mov  [esi+0x4fd94], eax          ; "connected" flag
4209f7..420a39   push 0x173 / 0x172 -> call edi   ; enable/disable the send button
420a3d (01fe3d)  call [0x5abd98]                  ; CloseUSBDevice
```

Open, test the handle, update the button, close. No `WriteUSB`, no report, no payload.
All three `OpenUSBDevice` sites are now accounted for: this poll, the send routine
(`0x02019e`), and the upload routine (`0x02031d`). **None of them sends a handshake.**

**Therefore the LED flash is firmware behaviour on the `0x7160` head, triggered by being
opened or enumerated — not a command the host can issue.** There is no packet to send, so
there is no live oracle to build. Lead A is closed.

Note this does not mean our head is faulty: it drives LEDs fine (two blue LEDs blink at
power-on, slice 6). It simply lacks the `0x7160`'s connect indicator, which is one more
piece of evidence that `0x7701` is a different product with different firmware, not a
rebadge.

**Cost of establishing this: one disassembly, no cable swaps.** Worth recording as the
cheapest negative result in the project.

---

## 2026-09-03 — Lead C first attempt: a downloader stub, and a new distinction

The file obtained from the Chinese mirror is not the editor. It is a libcurl downloader
wrapper that fetches the real archive at runtime — no USB or HID code of any kind. The six
apparent `0x7701` immediates are `83 f9 01` / `77 xx` (`cmp ecx,1` / `ja short`), a byte
coincidence in branch code. Moved to `vendor/_not-the-software/` with the evidence.

**Method note.** The same false-positive check that cleared this file is the one that found
the real `push 0x7160 / push 0x0C45` pairs in the Promier exe. A 16-bit value appearing in a
binary means nothing until the surrounding instruction is read. Two of my own leads in this
project have died on exactly that check.

### New: there are two hardware generations
AppNee's catalogue describes its editor as being for **"USB Fan Version 2.0"** devices,
"distinguishing it from the Version 3.0 alternative", and lists LED counts of 7, 11, 16 and
32 with four spin speeds.

Everything analysed so far — the Promier/LitezAll `LedFan.exe`, `WxkUSB.dll`, the font
tables, the `0x7160` PID — is **generation 2**. Our head holds 26 characters where every
generation-2 variant found holds 18 or 20, has a PID (`0x7701`) that appears in no
generation-2 build, ignores generation-2 table formats entirely, and lacks the
generation-2 connect indicator.

**Working hypothesis: `0x7701` is a Version 3 device, and no Version 3 software has been
located.** That would explain every negative result in this project at once, and it
reframes the search: the target is not "the software for our fan" but "the USB Fan Version
3.0 editor".

Appnee's tag page returns 403 to automated fetching; a person can browse it.

---

## 2026-09-03 — The powered state: tested and eliminated

The last untested configuration. Power cable **and** data cable connected **and the fan
switched on** — a state nobody had entered, because the vendor manual says "Make sure your
fan is OFF" and every session inherited that instruction. It was written for a
generation-2 fan.

**Observations**
- The head enumerates normally in this state (`ioreg`: SONiX, `kUSBAddress = 4`, interface
  matched and active).
- The first LED at the blade tip lights bright blue and **steady** — not blinking, not
  pulsing, not multiplexing. The motor does not turn.
- The slice-6 batch was re-sent in this state: 233 packets, **fails=0, slow=0**, 4.0 s.
- **The LED did not change at any point** during or after the send.
- Power-cycled to display mode afterwards: **disc dark.**

**What it eliminates**
1. *The LED is not an activity indicator.* 233 writes passed under it without a flicker. It
   is a static "powered, not spinning" light.
2. *The switched-power hypothesis is unsupported.* The idea was that EEPROM writes might
   need the fan's own power rail, and that every previous write was accepted by the bridge
   but never committed. If so, page-write cycles should have appeared as tens-of-milliseconds
   writes. Timings were uniformly fast and identical to every unpowered session — no write
   cycles, in either state.
3. *All four candidate tables, at four bases, are eliminated in the powered state as well as
   the unpowered one.*

**Conclusion.** There is no configuration of cables and power in which this head accepts a
generation-2 message table. The hardware experimentation is complete: every reachable
combination of framing, table format, address base, addressing model and power state has
been tried.

**What remains is not experimental.** Only the "USB Fan Version 3.0" editor — or a USB
capture of one programming a `0x7701` fan — can move this now. That is a search, not a test.

---

## 2026-09-22 — THE PROTOCOL EXISTS IN PUBLIC. Our fan has two open-source drivers.

Found while looking for a replacement fan to buy. Every earlier search looked for `0c45:7701`
or the vendor software. The drivers never print the PID in their READMEs, so they never came up.

- **Ventto/pearlfan** — https://github.com/Ventto/pearlfan — C, libusb, GPLv3. "GNU/Linux kernel
  driver and libusb app for a Pearl's USB LED fan", article **PX5939**. The README says images
  are **11 x 156 pixels, at most 8 images**. 156 = 26 characters x 6 columns, so this is our
  fan's exact geometry.
- **pearlfan-rs** — https://github.com/mwja/pearlfan-rs — Rust port, **MIT / Apache-2.0**.
  docs.rs: `pub const VID: u16 = 0x0C45;` and `pub const PID: u16 = 0x7701;`.
  **That is our head.**

### Protocol, as described (source not copied; the C project is GPLv3)
- Transport: HID SET_REPORT over the control pipe. `bmRequestType 0x21`, `bRequest 9`,
  `wValue 0x0200` (output report, ID 0), `wIndex 0`, **8 bytes**. The same as our
  `IOHIDDeviceSetReport(kIOHIDReportTypeOutput, 0, …, 8)`.
- After **every** packet the driver reads 8 bytes from interrupt endpoint **0x81** with a
  1000 ms timeout, and treats a failed read as an error. We have never seen an input report,
  but we never sent a correctly framed stream either. This may be the live acknowledgement we
  concluded did not exist. Test it.
- Per image (up to 8): **one header packet, then 39 data packets.**
- Header: the 64-bit constant `0x00000055000010A0`, OR'd with a 16-bit effect field shifted
  left by 16 (close effect, open effect << 4, image id << 8, before-close effect << 12). Sent
  from a little-endian host, the header on the wire is roughly
  `A0 10 <close | open<<4> <id | beforeClose<<4> 55 00 00 00`.
  **The first byte is `A0`, the only header our head has ever reacted to.**
- Data: 39 packets x 4 columns = 156 columns, 16-bit per column, 11 pixels.
- Exact bit order, LED polarity, word endianness and effect codes: read them from
  `pearlfan-rs` (permissive licence) during implementation. **Do not copy code from the GPLv3
  C project.** Reimplement from the facts.

### Consistency with our own findings
- `A0` is the only processed header. **Explained**: it is the header opcode.
- The factory demo was erased by a sweep of every two-byte header with a `FF` payload. That
  sweep sent `A0 10 …` packets followed by garbage, which is enough to overwrite image slots.
  **Explained.**
- The generation-2 (0x7160) formats did nothing. **Explained**: different protocol.
- Issue #11 on pearlfan: a user with a `0c45:7160` "XY-SUN XY LED FAN" got "Device can not be
  opened or found". That confirms pearlfan targets 0x7701 and not the generation-2 PID.

### Why we missed it
"No prior art" (2026-09-01) was a conclusion drawn from searches for the numeric ID and the
vendor software. The drivers name the *retailer's product*, not the chip ID. The search that
worked started from the product (PEARL, 26 characters), which we had already found in lead B,
and never pointed at GitHub.

---

## 2026-09-22 (later) — The original head is destroyed; buying a replacement

The head was opened to try to read the chip and was damaged beyond use. The board photo
settles one thing permanently: **there is no external EEPROM.** A single unmarked ~24-pin
SSOP MCU (`U1`), a micro-USB socket, a Schottky (`D1`, "S4"), one 470R and five capacitors,
with an FPC ribbon to the blade. Message storage is internal to the MCU, so no clip-on
programmer could ever have read it. Route 1b was never viable — the "cannot open the head"
constraint cost us nothing.

### Protocols we can now target
| VID:PID | Source | Status |
|---|---|---|
| `0c45:7701` | Ventto/pearlfan (GPLv3), pearlfan-rs (MIT/Apache) | Best supported. Our original fan. |
| `0c45:7160` | Our own slice-5 analysis of the vendor editor, plus `GenerationTwoTableSerializer` | Complete byte-level map |
| `1a86:5537` | marcin-osowski/usb_fan (UF-211) | Public reimplementation |

Three of the common OEM designs are covered, so an arbitrary cheap programmable POV fan has
good odds of being one of them.

### Buying notes (2026-09-22)
- Jaycar **GH1031** (the fan `fergofrog/microwave_usb_fan` targets): **sold out** in AU at
  A$6.95. A US Jaycar listing exists but stock unconfirmed.
- **PowerTRC LED Programmable Message Fan** is in stock on Amazon US in several colours and
  in 2-packs. Same family description as the northridgefix listing: gooseneck, "8 messages,
  26 letters", ships with a 3" CD and a separate programmable USB cable. The 8x26 spec is the
  `0c45:7701` signature.
- No listing states a USB ID, so the PID is unconfirmed until it arrives. Buy returnable.

### On arrival — do this in order
1. **Do not connect the data cable yet.** Power the fan, run the factory demo, and record a
   video of it. That is both proof it works and known plaintext.
2. Then attach the data cable and run
   `ioreg -c IOUSBHostDevice -r -w0 | grep -iA4 -E "sonix|1a86"`.
3. Report the VID:PID. `0c45:7701` goes straight to slice 9 unchanged.

### Two replacement fans ordered (2026-09-22, arriving 2026-09-23)
PowerTRC LED Programmable Message Fan, green, **two units**.

**Fan policy — this is the structural change the project never had.**
- **Fan A: the working unit.** Everything is tried on A. It may be erased, bricked or opened.
- **Fan B: the sealed reference.** Never connect a data cable to B. Never send it a byte.
  B exists to answer "is this behaviour the device or is it something we did?" — the
  known-good control that was missing from day one, when the factory demo was erased
  before anyone thought to record it.
- Promote B to A only after A is unusable, and say so in the findings when you do.

**Before A's data cable is ever connected:** power it, run the factory demo, and **transcribe
all 8 messages as text, character for character**. Record a video too if it helps you read
them back, but the transcription is the artefact that matters — it is the known plaintext this
project lacked for three weeks, and it is what can be searched for in a memory dump or a
traffic capture. Do the same for B before it goes back in its box.

(Note for whoever asks for this next: the architect can read still images, not video. Ask for
the text, or for stills.)

### 2026-09-23 — Replacement fan confirmed as `0c45:7701`
Fan A (PowerTRC, green) enumerates as `idVendor 3141` (0x0C45, "SONiX"), `idProduct 30465`
(**0x7701**). Identical to the original head, and the PID that `pearlfan` / `pearlfan-rs`
target. Slice 9 applies unchanged — no new protocol work, no new transport.

The `8 messages x 26 characters` capability spec on the listing proved a reliable proxy for
this PID. Worth reusing if another unit is ever needed.

### 2026-09-25 — Fan A's factory demo, transcribed (KNOWN PLAINTEXT)
Recorded from the owner's observation before any write. This is the Rosetta stone the
project lacked from day one: if the fan's memory is ever dumped, or its traffic captured
from the vendor software, these strings are what to look for in the bytes.

Observed order:
1. `Hello World. I hold 8 Msg.`   <- exactly 26 characters, the full width
2. `26 letters in each Msg`
3. `I'm your *NOTE PAD*`
4. `*Mom Pick me up @4P*`         <- and further examples in the same style

**Character set evidence.** Uppercase, **lowercase**, digits, space, and `. ' * @`.
Message 1 being exactly 26 characters independently confirms the capability spec.

**Fidelity gap found.** The demo displays **mixed case** ("Hello World", "Mom Pick me up"),
so the device's font has lowercase glyphs. Our `GlyphFont` is a 5x7 table with no lowercase
— `columns(for:)` uppercases every character, so we would render "Mom" as "MOM". The table
does already carry `.`, `'`, `*` and `@`. See decision D18.

---

## 2026-09-25 — Slice 9: the PearlFan protocol, pinned down from pearlfan-rs

Source read: **pearlfan-rs**, commit `3d9b32c`, MIT OR Apache-2.0 (github.com/mwja/pearlfan-rs).
Nothing from Ventto/pearlfan (GPLv3) was read or used. Line numbers below are in that commit.
The reference bytes in `Tools/PearlFanGolden/` were produced by building the reference
library with a scratch harness and drawing our rasterizer's pixel grids through it.

### Device and transport
- VID `0x0C45`, PID `0x7701` (`src/lib.rs:55-57`). Display 156 x 11, 8 stored images
  (`src/lib.rs:62-66`).
- Opened through hidapi (`src/device.rs:67-70`). hidapi 2.6.7's macOS backend opens the
  `IOHIDDevice` with **`kIOHIDOptionsTypeSeizeDevice`** (`etc/hidapi/mac/hid.c:469`, `:1503`,
  `:1055`) and delivers input reports through `IOHIDDeviceRegisterInputReportCallback` on a
  run loop (`:1072`). Our transport now opens seized and listens the same way.
- `transfer_packet` (`src/device.rs:81-93`): a 9-byte buffer, report id `00` then the 8
  data bytes; hidapi strips the id and calls `IOHIDDeviceSetReport(kIOHIDReportTypeOutput,
  0, data, 8)` (`hid.c:1126`). Then **`read_timeout(8 bytes, 1000 ms)`** on the interrupt-IN
  endpoint. A timeout returns zero bytes and is **not** an error; only a HID error aborts.
  The received bytes are logged at trace level and otherwise ignored.
- No init sequence, no finish packet, no delays other than the acknowledgement read
  (`src/device.rs:100-126`).

### Per image: one header, then 39 data reports
`send_animation` (`src/device.rs:103-121`): for image `i` (0-based, in the order given,
**only the images passed; no padding to 8**), send `effect.to_bytes(i)`, then the 156
column words in 39 chunks of 4, each word **little-endian**, so 8 bytes per report.

**Header** (`src/effects.rs:54-108`): the 64-bit constant `0x0000_0055_0000_10A0` OR'd with
a 16-bit options word shifted left 16, written little-endian:

```
options = close | open << 4 | imageID << 8 | beforeClose << 12
wire    = A0 10 [close | open<<4] [imageID | beforeClose<<4] 55 00 00 00
```

Effect codes (`src/effects.rs:4-22`, `:28-36`): open/close `0` right-to-left, `1`
left-to-right, `2` symmetric, `3` red carpet, `4` top-to-bottom, `5` bottom-to-top, `6`
fast mode (opening only; refused for closing, `:91-93`). Before-close motion: `0` none
("remain"), `2` turn left-to-right ("clockwise"), `6` turn right-to-left ("anticlockwise").
Defaults are right-to-left both ways and no motion (`:47-52`). The reference has no code
for the vendor's "flash 3 times".

**Column words** (`src/draw/mod.rs:7-19`, `:24-25`, `:126`, `:143`): a blank column is
`0xFFFF`; a lit pixel **clears** a bit. Image row `y` (0 = top) clears
`[0x0008, 0x0004, 0x0002, 0x0001, 0x8000, 0x4000, 0x2000, 0x1000, 0x0800, 0x0400, 0x0200][y]`,
named LED10 down to LED0 in the source. Column `x` on the disc (0 = left) is stored at word
index `155 - x`, so **the leftmost column is the last word on the wire**. Which physical LED
is LED10 is not stated; the font puts glyph tops at `y = 0`, so `y = 0` should be the tip.
The first send settles it: upright text means the mapping holds.

**Text layout** (`src/draw/font/ascii.rs:76-105`): 5 columns per glyph plus 1 blank, pages
of `156 / 6 = 26` characters, character `i` at `x = 6i`. Identical to our rasterizer's
pitch, so a 26-character message fills the disc exactly. Text longer than 26 characters
becomes further images with the next ids. Empty text draws **no** image at all
(`:79-83`); our encoder sends a blank image instead, so a slot can be cleared.

**Unknown, to be established on the fan:** whether the image id selects a stored slot (our
encoder sends the slot number as the id; the reference always numbers from 0), and what
happens to slots that are not written. Fan A's demo occupies all 8, so the first send
answers both: after writing slot 1 only, do slots 2–8 still show the demo?

### Worked example: one message, "A", in slot 1
Our glyph for A is `7E 11 11 11 7E` with the top row at arm row 2, so disc columns 0–4 hold
the glyph and columns 5–155 are blank. Column 0 (rows 3–8 lit) becomes
`0xFFFF & ~(0x0001|0x8000|0x4000|0x2000|0x1000|0x0800) = 0x07FE`, sent as `FE 07` in the
**last** two bytes of the **last** report. All 40 reports, from the reference harness:

```
A0 10 00 00 55 00 00 00
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FF FF
FF FF FF FF FF FF FE 07
FD DF FD DF FD DF FE 07
```

Reports 2–37 are blank columns; report 39 holds columns 7–4 (`FD DF FD DF FD DF FE 07`
is report 40: columns 3, 2, 1, 0). The Swift encoder reproduces these bytes, and the four
other reference streams in `Tools/PearlFanGolden/golden/`, byte for byte
(`LedFanTests/PearlFanEncoderGoldenTests.swift`).

### Consistency with everything before
- `A0` is the first byte of every header. The sweeps that erased the original demo sent
  `A0 10 …` followed by `FF` payloads, which is a valid header for image 0 with garbage
  options, followed by data reports of all-blank columns: **an erase, exactly as observed.**
- The 5-second stall at `A0 18…A0 23`: in this protocol the second byte is always `0x10`,
  so those packets were malformed headers. The stall remains unexplained but is now moot.
- The head never acknowledged anything because it was never sent a well-formed image. The
  first correct send is the first real test of the interrupt-IN channel.

### 2026-09-25 — FIRST SEND WITH THE PEARLFAN PROTOCOL: IT WORKS
Fan A, `0c45:7701`, switched off, data cable in, power cable out. The app itself did the
send (USB fan, slot 1, `HELLO WILLIE`, Connect, Send): 40 reports, the stream
`Tools/PearlFanGolden/golden/golden-hello-willie.hex` that the golden test pins, with the
image id 0 and the default effects (open and close right-to-left, no motion). Receipt shown
in the app: "Wrote 40 reports …" (full line and the acknowledgement log to follow; the
app's sandbox container is unreadable from any shell on this Mac).

Then the swap: data cable out, power cable in, switched on. Owner's observation, verbatim:

> **"HELLO WILLIE is showing, upright and readable"**

So, established on hardware in one send:
- The protocol reimplemented from pearlfan-rs is correct for this head. Milestone 2 is
  reached.
- Row 0 of the image is the **tip** of the arm and column 0 the **left** of the text as
  read: the LED bit table and the reversed column order are the right way round.
- Our 5x7 font at a 6-column pitch, glyph top at arm row 2, renders legibly on the real
  disc.
- A well-formed image replaces the content of a slot without any init or finish sequence.

Pending from this send: whether the head acknowledged on the interrupt-IN endpoint (the
receipt line and the `.hex` log), and what became of slots 2–8, which held the factory
demo. Per the brief, no further packets go out in this slice.

Slots 2–8 after the single-image send, owner's observation, verbatim: **"slots 2 to 8
gone"**. The fan shows only `HELLO WILLIE`; none of the factory demo remains. So a send
defines the whole stored set: the head keeps exactly the images it was just given, and
anything not sent is cleared rather than preserved. That matches the reference driver,
which numbers images from 0 and never pads to 8. To keep several messages, send them all
in one session, in slot order. Fan A's demo is now gone for good; Fan B's is intact.

**Acknowledgements: the head answers.** Receipt line, verbatim: "Wrote 40 reports (320
bytes) in 0.6 s". The transport waits up to one second per report for an interrupt-IN
report and moves on only when one arrives or the second expires; 40 reports in 0.6 s means
every wait ended early, about 15 ms each. So the head acknowledged all 40 on the interrupt
endpoint, for the first time in this project's history. The first head never did, because it
was never sent a well-formed image. The acknowledgement bytes are in the send's `.hex` log
in the app container; to be added here when the owner copies it out.

**The acknowledgement bytes** (`Tools/probe-output/sends/2026-09-25T22-21-53-slot1.hex`, the
app's log of the send; wire bytes identical to `golden-hello-willie.hex`):

- The head answers every report with **an 8-byte echo of the report it just received**.
  All 39 data reports came back byte for byte.
- The header comes back with **its first byte changed from `A0` to `A1`**: the reply to
  `A0 10 00 00 55 00 00 00` was `A1 10 00 00 55 00 00 00`. The low bit of the opcode is the
  acknowledgement flag; the rest of the header is echoed unchanged.

So the interrupt-IN channel is a loopback with one flag bit, which is why the reference
driver reads it and discards it: there is nothing in it the host did not already know,
except that the head received the bytes. A future transport could check each echo against
what it sent and treat a mismatch as a transfer error; the reference does not, and ours
does not yet. The first head's `GET_REPORT` behaviour (returning the last SETUP packet) was
a different, control-pipe echo and never this one.
