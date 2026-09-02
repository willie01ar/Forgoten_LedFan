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
