"""Neighbourhood of the one reacting header. Times each write, logs timeouts and any input.
Usage: python probe_a018.py  (sends the listed packets once each, 300 ms apart)"""
import sys, time, hid
tests = [
    ("A0 18 + FF*6 (the reacting packet)",  [0xA0, 0x18] + [0xFF]*6),
    ("A0 18 + 00*6",                         [0xA0, 0x18] + [0x00]*6),
    ("A0 18 + 01..06",                       [0xA0, 0x18, 1, 2, 3, 4, 5, 6]),
    ("A0 17 + FF*6",                         [0xA0, 0x17] + [0xFF]*6),
    ("A0 19 + FF*6",                         [0xA0, 0x19] + [0xFF]*6),
    ("A0 00 + FF*6",                         [0xA0, 0x00] + [0xFF]*6),
    ("A0 FF + FF*6",                         [0xA0, 0xFF] + [0xFF]*6),
    ("9F 18 + FF*6",                         [0x9F, 0x18] + [0xFF]*6),
    ("A1 18 + FF*6",                         [0xA1, 0x18] + [0xFF]*6),
    ("18 A0 + FF*6 (swapped)",               [0x18, 0xA0] + [0xFF]*6),
]
if len(sys.argv) > 1 and sys.argv[1] == "--only":
    tests = [t for t in tests if t[0].startswith(sys.argv[2])]
d = hid.device(); d.open(0x0C45, 0x7701); d.set_nonblocking(True)
for name, body in tests:
    pkt = bytes([0x00] + body)
    t = time.time(); n = d.write(pkt); dt = (time.time() - t) * 1000
    status = "ok" if n >= 0 else f"FAILED ({d.error()})"
    time.sleep(0.3)
    r = d.read(64)
    print(f"{name:38s} -> {status:45s} {dt:7.1f} ms   input: {bytes(r).hex(' ') if r else '-'}", flush=True)
