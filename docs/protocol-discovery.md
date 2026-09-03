# Protocol discovery

**REOPENED 2026-09-02**, hours after being closed. The closure was premature: a
review found leads that had never been tried. Do not treat the hardware path as closed
while anything in "Reopened leads" below is outstanding.

The slice-6 result stands — the batch was sent, the disc stayed dark — and everything
recorded here about what was eliminated remains true. What changed is that the set of
things still worth trying was wrong.

## Reopened leads (2026-09-02)

**A. CLOSED (2026-09-02, same day) — there is no handshake packet.**
The routine behind the connect indicator is a UI polling timer that opens the device, sets
a flag, updates the send button and closes again. It sends nothing. All three
`OpenUSBDevice` sites are now accounted for and none issues a handshake, so the LED flash
is `0x7160` firmware behaviour on being opened, not a command a host can send. There is no
live oracle. See `protocol-findings.md`, "Lead A closed". Original text follows.

**A. The bundled manual describes a LIVE ORACLE we never used.**
`vendor/LedFan/fan-instructions.pdf` — a Promier single-page manual for "USB DATA DOWNLOAD
SYSTEM V2.0", present in the download since the start and never opened until now — says:

> "After connecting with the USB fan, the computer will find the software of the USB fan
> automatically. The send button will change from gray to black **while the LED lights
> flash one by one**, which proves that the connection is successful."

On a working fan of this family, a successful handshake makes the LEDs **flash one by one,
during the data phase, with the data cable connected**. This project's central premise —
"there is no live observation; the only oracle is a cable swap" — is therefore wrong for
the handshake at least. If a packet sequence can be found that makes this head flash its
LEDs, there is a feedback loop costing zero swaps, and the whole economics of probing
change.

Whether our head has ever done this is unknown and was never watched for. Ask the owner.

**B. PEARL PX-5939 is a 26-character variant — ours.**
`PEARL USB-Ventilator mit 8 programmierbaren Laufschriften, je 26 Zeichen`, model PX-5939 /
HPM-5939-919. Eight messages, 26 characters: our head's exact specification, where every
other variant found so far is 18 or 20. PEARL maintains a per-product support page with
**software** and a manual:
- Support/software: `https://www.pearl.de/support/product.jsp?pdid=PX5939`
- Manual: `https://www.pearl.de/pdocs/PX5939_11_153964.pdf`

**Direct file URLs** (found 2026-09-02 via `pearl-brands.com/mini-pc-fan-PX-5939-919.shtml`;
the `support/product.jsp` page does not respond):
- Software: `ftp://ftp.pearl.de/treiber/PX5939_12_148115.zip` — **FTP**, which is why
  browsers show nothing. Fetch with `curl -O`.
- Manual: `https://www.pearl.de/pdocs/PX5939_11_153964.pdf`
- Article PX-5939-919, EAN 4022107226189.

Also worth grabbing as lead-C material: the PX-1144 fan's driver (1.33 MB) at
`https://www.pearl.de/support/product.jsp?pdid=PX1144` — a 16-character variant, so a
different build again, and possibly one that opens more than one PID.

**STALLED ON REACHABILITY, not closed (2026-09-02).** `ftp.pearl.de` is gone: their own
firewall `fw1.pearl.de` answers but returns *Destination Host Unreachable* for
62.159.194.69, and FTP was retired industry-wide years ago — the DNS record is stale.
`www.pearl.de` also times out, from both the owner's machine in the US and from a cloud
fetcher, so the whole host may be EU-only or down. `pearl-brands.com` and `c-enter.at` are
reachable but 404 on `/pdocs/` paths, so the group domains do not mirror the files.

The file is not indexed on any mirror. Ways this could still be obtained: retry
`www.pearl.de` later or from a European network; ask someone in the EU to fetch
`PX5939_12_148115.zip`; or look for the retired FTP path in a web archive. None of these
are things a build session can do — this one needs a person.

**What would make this decisive.** If that zip contains an editor whose `OpenUSBDevice`
call names `0x7701`, the protocol question is answered by disassembly alone, with no cable
swaps. If it is the same Promier/`0x7160` build under a different wrapper, lead B is closed
and so, most likely, is the hardware chapter.

**C. STALLED (2026-09-03).** The Chinese mirror served a libcurl downloader stub, not the
editor (see `vendor/_not-the-software/`). AppNee gates its copy behind a shell script the
owner declined to run — correctly: an unverifiable script from a software-mirror site, run
on a development machine, is disproportionate risk for a fifteen-year-old utility. It is
also very likely the wrong generation: AppNee's build is for **USB Fan Version 2.0**, and
the working hypothesis is that `0x7701` is a **Version 3** device.

**The search target has changed.** Stop looking for "software for our fan" and look for the
**USB Fan Version 3.0 editor**. No Version 3 software has been located anywhere. Until it
is, the hardware chapter stays stalled.

**C (original). Other builds of the vendor tool, never downloaded.**
The Promier/LitezAll download is the same `LedFan.zip` already in `vendor/` (confirmed: same
Shopify CDN). But "USB DATA DOWNLOAD SYATEM v2.0", which supports 7/11/16-LED variants, is
mirrored at jb51.net, 3h3.com, xitongzhijia.net and CSDN, and appnee.com hosts a "USB LED
Fan Editor for USB Fan Version 2". These are different builds and may open more than one
PID.

**Why this matters.** Our exe hardcodes `0x7160`. A build for a 26-character fan would be
built for a different product, and its `OpenUSBDevice` call would name that product's PID —
possibly `0x7701`.

The one genuinely unsolved problem. The app is straightforward; this is not.

## What we know

8-byte frames. Report ID 0. Output and Feature reports both declared, both 8 bytes. An
interrupt IN endpoint is declared too.

**Neither return channel carries anything (established 2026-09-01).** The interrupt IN
endpoint has never produced a report, through two independent listeners. Every
GET_REPORT, input or feature, returns the last USB SETUP packet the firmware handled.
The head is write-only from the host's side. Do not design an experiment around an
acknowledgement or a read-back; there is none.

**There is no live observation either.** The data port is on the rotating head, so the fan
cannot spin while it is connected. Every experiment is: upload with the data cable in, swap
to the power cable, spin, look, swap back. One cable swap per observation, paid by the
owner. Anything below that says "watch the fan" means "after the swap".

No public documentation exists for `0c45:7701`.

## Routes, best first

### 1. The bundled Windows app — highest leverage by far

The fan shipped with a Windows utility. It has never been run (no Windows machine), but if
the installer can be found, `strings` and a disassembler give the VID/PID it opens and
usually the command framing directly. An afternoon of static analysis beats a week of
blind probing.

**Status: not yet located.** Worth real effort before falling back to route 3.

### 1b. CLOSED — physical access to the chip

**The head cannot be dismantled without breaking it** (owner, 2026-09-02). There is one fan
and no spare. Every route requiring a clip, a programmer, or sight of the PCB is off the
table. Do not propose it again.

### 1c. RETIRED — `A0 <byte>` as a LENGTH with continuation packets

**Retired 2026-09-02 by D15/slice 6.** Slice 5's static analysis of the vendor serializer
showed the family frames data as a 2-byte header plus five stream bytes plus a checksum,
with a mandatory 3-byte acknowledgement — nothing resembling length-then-continuation. The
hypothesis rested on the stall range bracketing 26, an arithmetic coincidence, and it
conflicts with the better-evidenced EEPROM-write model at the address level. Kept below for
the record.

#### Original text

**Untested, free, and derived from data already in the log.** Currently the best lead.

The stalls sit at `A0 18`, `A0 18`, `A0 23`, `A0 19`; the slow writes at `A0 1A` and
`A0 24`. In decimal: stalls at 24, 25, 35; slow writes at 26 and 36. **The message length
on this fan is 26 characters.** A second byte clustering around 24-26 is an odd thing for a
plain EEPROM address to do.

**Hypothesis.** `A0 <length>` opens a transfer and the firmware then waits for the
character data in following packets. The 5 s stall is the host timing out while the
firmware waits for continuation packets that never arrive, which would explain three
observations at once: only `A0` is ever processed, the stall depends on preceding packets,
and it is independent of payload.

Every sweep so far sent one packet per header and moved on. E2a/E2b did send streams, but
framed in the sibling format, not this shape. **The sequence has never been tried.**

**Experiment.** For a candidate length L (start at 26, then 24, 25, 35, 36):

```
A0 L  <6 chars>      then  <6 chars> <6 chars> ... as bare 8-byte packets
A0 L  <6 chars>      then  A0 <index> <6 chars> ...
A0 00 L <5 chars>    then  continuation
```

Send "AAAAAA…" — a single repeated character makes any partial success obvious on the
blades. Try three or four variants, then one cable swap. Vary framing, not payload.

Cost: one swap per batch. Odds: unknown, but the arithmetic is suggestive and nothing else
free remains.

### 1d. Search for the vendor software in Chinese

Route 1's searches were English-language. SONiX is Taiwanese and these fans were built in
Shenzhen; the editor, if it survives, is likely on a Chinese download site, a Taobao or 1688
listing, or a driver-CD archive. Search terms worth trying: USB风扇 编辑软件, LED风扇 编程,
闪光风扇 软件, plus the fan's moulded brand or model markings.

Free, genuinely untried, and route 1 remains the highest-value outcome if it lands.

### 1e. Ask people who might own one

Post the VID/PID, the 41-byte report descriptor, the exterior photographs and the findings
log somewhere with old-hardware expertise. For a product this age, someone owning the same
fan or the original CD is not far-fetched, and it costs a post.

### 1f. The button — mostly closed, one thing still worth knowing

The fan has **one power button**. Pressed while USB power is connected, the head spins.
There is no mode button and no obvious reset gesture, so restoring the factory demo this way
is unlikely. Confirm and close with three quick attempts, all in the power phase and costing
no cable swap: long press, double press, and hold-while-connecting-power.

**The part that still matters.** On fans of this class the button often doubles as a message
selector, advancing through the stored messages. If it does here, one cable swap can verify
*several slots* instead of one — which changes how the next probing batch should be
designed: write candidate data to multiple slots in a single programming phase, then step
through them on a single swap.

Not observable while the display is dark, but design the next batch on the assumption that
it might be, and it costs nothing if it is not.

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
thing at a time — slot, packet index, first byte — and, after the cable swap, look for the
text appearing at all, even garbled. Garbled text is a solved protocol; a blank fan is not.
Note that the sweeps of 2026-09-01 already covered every two-byte header with `FF` and
`55 AA` payloads; a text hypothesis now needs the `A0 <addr>` framing in front of it.

Only fall back to the sweep below if the text hypothesis produces nothing.

Method, in order:

1. **Listen first.** Done; nothing arrives, ever. Kept here as the record.
2. **Read the feature report** (`g`). Done; it is an endpoint-0 echo, not state.
3. **Sweep the first byte.** Done for all 65,536 two-byte headers. The only USB-side
   signal on this head is timing: `A0`-headed writes sometimes take tens of milliseconds
   and once per long run block for the host's 5 s timeout. Everything else is accepted
   silently. The blades can only be checked after a cable swap.
4. **Walk single bits.** If a column of LEDs lights in a pattern that tracks the bit
   position, the frame layout is direct-mapped and the problem is essentially solved.
5. **Look for framing.** Most devices of this vintage use a start marker, a length or index
   byte, payload, and sometimes a checksum. Try `0x00`-prefixed and `0xFF`-prefixed frames.

**Record every result in `protocol-findings.md`** — create it, append as you go, including
the negative results. Knowing that `0x00`–`0x3F` do nothing is worth as much as knowing
what `0x40` does, and it is exactly what gets forgotten between sessions.

## Guardrail

The failure that actually happened was not a bricked MCU. A blanket header sweep with an
all-ones payload **erased the EEPROM that holds the message table**, and with it the
factory demo. The head is alive, the motor spins, and nothing is displayed. That is the
realistic cost of blind output-report writes on this device: lost data, presumably
rewritable once the table format is known, but not recoverable by us today because there
is no read path.

Feature reports are a different class of risk. On a bridge chip they are where device
configuration lives; corrupting that is not recoverable and, with no read path, not even
diagnosable. Feature-report writes are declined (decisions.md D7) except for a specific,
argued hypothesis, and never as a sweep.

Nothing in the app target writes to the head at all (D9). Blind writes are a `Tools/`
activity, done deliberately, with the owner at the fan and asking for it.
