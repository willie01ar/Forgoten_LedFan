"""Timed header sweep. Sends [hi lo] + payload for hi in [a..b], lo in 0..255 (or a single lo range),
times every write, prints failures and outliers (> threshold ms), and any input report.
Usage: python timed_sweep.py hi_start hi_end [lo_start lo_end] [--payload FF] [--threshold 15]"""
import sys, time, hid, statistics
args = [a for a in sys.argv[1:] if not a.startswith("--")]
opts = sys.argv[1:]
payload = int(opts[opts.index("--payload")+1], 16) if "--payload" in opts else 0xFF
threshold = float(opts[opts.index("--threshold")+1]) if "--threshold" in opts else 15.0
hs, he = int(args[0], 16), int(args[1], 16)
ls, le = (int(args[2], 16), int(args[3], 16)) if len(args) >= 4 else (0, 255)
d = hid.device(); d.open(0x0C45, 0x7701); d.set_nonblocking(True)
times = []; t0 = time.time()
for hi in range(hs, he + 1):
    for lo in range(ls, le + 1):
        pkt = bytes([0x00, hi, lo] + [payload]*6)
        t = time.time(); n = d.write(pkt); dt = (time.time() - t) * 1000
        times.append(dt)
        if n < 0:
            print(f"FAIL   {hi:02X} {lo:02X}  after {dt:8.1f} ms  ({d.error()})", flush=True)
        elif dt > threshold:
            print(f"SLOW   {hi:02X} {lo:02X}  {dt:8.1f} ms", flush=True)
        r = d.read(64)
        if r: print(f"INPUT after {hi:02X} {lo:02X}: {bytes(r).hex(' ')}", flush=True)
print(f"done {hs:02X}{ls:02X}..{he:02X}{le:02X}: {len(times)} writes, median {statistics.median(times):.1f} ms, max {max(times):.1f} ms, {time.time()-t0:.1f}s")
