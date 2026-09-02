"""Shotgun sweep: every 2-byte header 0x0000..0xFFFF followed by six 0xFF bytes.
Uses hidapi directly (no report-id byte on macOS write for id 0 -> we prepend 0x00).
Logs write failures and any input report that arrives (100 ms non-blocking read every 256 packets).
Usage: python shotgun.py [start_hi] [end_hi]  (first-byte range, default 0..255)
"""
import sys, time, hid
start = int(sys.argv[1], 16) if len(sys.argv) > 1 else 0
end = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0xFF
d = hid.device(); d.open(0x0C45, 0x7701); d.set_nonblocking(True)
failures = 0; inputs = []
t0 = time.time()
for hi in range(start, end + 1):
    for lo in range(256):
        pkt = bytes([0x00, hi, lo, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        try:
            n = d.write(pkt)
            if n < 0:
                failures += 1; print(f"write returned {n} at header {hi:02X} {lo:02X} (error: {d.error()})", flush=True)
                r = d.read(64)
                if r: print(f"  input after failure: {bytes(r).hex(' ')}", flush=True)
        except Exception as e:
            failures += 1; print(f"write raised at header {hi:02X} {lo:02X}: {e}", flush=True)
    r = d.read(64)
    if r: inputs.append((hi, bytes(r).hex(" "))); print(f"IN after first byte {hi:02X}: {bytes(r).hex(' ')}")
    if hi % 16 == 15: print(f"done through {hi:02X}, {time.time()-t0:.0f}s, failures={failures}", flush=True)
print(f"finished {start:02X}..{end:02X}: failures={failures}, input reports={len(inputs)}, {time.time()-t0:.0f}s")
