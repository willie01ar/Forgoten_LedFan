# Hardware

Everything here was established empirically on 2026-09-01 against the actual device.

## The device

| Property | Value |
|---|---|
| Vendor | SONiX Technology, `idVendor 0x0C45` (VID shared with Microdia) |
| Product | `idProduct 0x7701`, product string "USB Device" |
| Speed | Low speed USB 1.1 — `UsbLinkSpeed 1500000`, `bMaxPacketSize0 8` |
| Device class | `bDeviceClass 0` — class declared at interface level |
| Interface | `bInterfaceClass 3` (HID), `bInterfaceSubClass 1`, `BootProtocol 2` |
| Endpoints | `bNumEndpoints 1` — a single interrupt **IN**. There is no interrupt OUT. |
| Usage | Vendor-defined usage page `0xFFFF`, usage `1` |
| Reports | Input 8 bytes, Output 8 bytes, Feature 8 bytes, all report ID 0 |
| Driver | `AppleUserUSBHostHIDDevice` (`com.apple.AppleUserHIDDrivers`), `HIDDefaultBehavior` empty |

Report descriptor, 41 bytes:
`06 FF FF 09 01 A1 01 09 01 15 00 26 FF 00 75 08 ... 7F 75 08 95 08 B1 02 C0`

### What follows from this

- **Use `IOHIDManager` for matching only.** No kext, no DriverKit, no serial driver.
  Nothing holds the device exclusively. **Do not call `IOHIDManagerOpen`:** on this device
  it leaves subsequent `GET_REPORT`/`SET_REPORT` calls failing with `kIOReturnNotOpen`.
  Set matching, copy the devices, open the `IOHIDDevice` directly. Verified 2026-09-01,
  inside and outside a sandbox.
- **The feature report is an echo of endpoint 0**, not device state. It returns the last
  eight bytes the firmware handled on the control pipe (the descriptor tail after
  enumeration, the SET_REPORT setup packet after a write). Details in
  `protocol-findings.md`.
- **Output reports go over the control pipe** via SET_REPORT, because there is no
  interrupt OUT endpoint. `IOHIDDeviceSetReport` does this transparently — but it means
  writes are slower than a bulk endpoint and should not be issued in a tight loop.
- **No TCC prompt.** Input Monitoring consent applies to keyboards and pointers. The
  vendor-defined usage page keeps this device out of that category, despite the firmware
  lazily declaring boot-protocol mouse.
- **Sandbox entitlement required:** `com.apple.security.device.usb`. Add it through
  Signing & Capabilities → App Sandbox → Hardware → USB. The app is sandboxed
  (`ENABLE_APP_SANDBOX = YES`) and will fail to open the device without it.

## The physical trap

**The fan has two ports.** The USB-A power cable has D+/D− unwired — it is a power supply,
nothing more. A **second mini/micro-USB port on the fan is the data port.** Nothing
enumerates unless a cable is in that second port.

**The data port is on the rotating assembly** (established 2026-09-01). With the data
cable plugged in the head cannot spin, and the motor is not powered. So there are two
mutually exclusive phases:

1. **Program:** data cable in, head stationary, powered by the Mac over USB. The board
   enumerates as `0c45:7701` and whatever is sent is stored on the head.
2. **Display:** data cable out, power cable in, head spins and paints the stored program.

Consequences: nothing sent over USB can be observed live; every protocol experiment is
"upload, swap cables, look". `FanDisplayTransport.store(_:)` on the hardware means
"write this into the head's table", not "show this now". The factory default message
that shipped on the head **was erased on 2026-09-01** by a blanket header sweep; the
display has been dark since. That, not a dead MCU, is what blind writes cost on this
device — see the guardrail in `protocol-discovery.md` and decisions D7 and D9.

If the device is missing, check that first. Also verify the cable carries data; charge-only
micro-USB cables are common and produce an identical symptom.

## Instrument reliability

This cost two false conclusions. Both were retracted.

- **`system_profiler SPUSBDataType` is broken on this Mac.** It returns empty output with
  exit code 0 while a known-good USB drive is attached and mounted. Never use it here.
- **`log stream --predicate 'subsystem == "com.apple.iokit.IOUSBHostFamily"'` reports
  nothing**, even on a real hotplug. Apple made those messages private.
- **`ioreg` is trustworthy.** Use `ioreg -p IOUSB -w0`, `ioreg -c IOUSBHostDevice -r -w0`,
  and `ioreg -c IOHIDDevice -r -w0 -a | plutil -p -`.

**Rule: never believe a negative hardware result without a known-good control device in the
same run.** `Tools/usbdiff.sh` implements this — snapshot, hotplug, snapshot, diff.

## Device capability (from the fan's own documentation, 2026-09-01)

**The fan stores up to 8 messages of 26 characters each.**

This is the strongest protocol evidence we have, and it changes the model:

- A device that counts *messages* and *characters* almost certainly carries its own font in
  firmware. It likely accepts **text**, not column bitmaps.
- 26 characters fits exactly 4 reports of 7 payload bytes (one header byte + 7 chars = 8),
  with 28 slots of capacity for 26 usable characters. Try this framing first.
- There are 8 addressable slots, so expect a slot index somewhere in the command.

None of this is confirmed. It is a hypothesis with unusually good odds, and it should be
the first thing probed rather than the byte sweep.

## The wire protocol: unknown, and the hardware path is closed (2026-09-02)

After eleven cable swaps the head has never displayed anything the app or the probes
wrote. Header sweeps, bit walks, zero fills, the sibling fan's complete table in both
encodings and both addressing models, and four serializer-derived candidate tables at four
bases under both power configurations all left the disc dark; the only response the head
ever gave was write timing on `A0`-headed reports. The factory demo was erased on the
first day of probing and has not been restorable. See the closing summary at the end of
`protocol-findings.md`. Milestone 2 stays paused; the app connects, reports the device,
and writes the generation-2 table it knows, saying plainly that nothing is expected to
appear (D16).

The head's LEDs are **blue**. At power-on, before the blades move, the third LED from the
hub and the third from the tip blink dimly for under a second: a power-on indicator, not
a display.


There is no public documentation for `0c45:7701`. The Raspberry Pi forum thread on a
"programmable USB LED fan" concerns a different device (`1D57:AC01`, programmed over I2C
through a special cable) and is not relevant.

There **is** prior art for a sibling: the Jaycar GH1031 fan is SONiX `0c45:7160`, has 11
LEDs per arm, and its protocol is public (`github.com/fergofrog/microwave_usb_fan`). It is
the first hypothesis to test. See `protocol-findings.md` for the format.

The search space is small: 8-byte frames, almost certainly a command byte plus seven bytes
of payload.
