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

- **Use `IOHIDManager`.** No kext, no DriverKit, no serial driver. Nothing holds the
  device exclusively.
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

## The wire protocol: unknown

There is no public documentation and no prior art for `0c45:7701`. The one on-point forum
thread was never answered. The command format must be derived. See
`protocol-discovery.md`.

The search space is small: 8-byte frames, almost certainly a command byte plus seven bytes
of payload.
