"""Slice 6: the last cable swap. Builds a 256-byte block-0 image holding four non-overlapping
candidate tables, each in the vendor serializer's stream format (docs/protocol-findings.md,
Slice 5, Task 1), each with a layout-invariant visual signature. Writes the image and the exact
packet list to Tools/probe-output/ before anything is sent. `--send` sends it.

Stream (mode 1, un-obfuscated, from the serializer at file 0x01f7f0):
  00, (0x80 | count), per message: [cols+2] 00 [style=03 remain] [open<<4|close=00] 00 00,
  columns as 16-bit words, 00 00, then zeros.
Signatures use only 0xFFFF (every bit set: all rows, all colour bits) and 0x0000 columns, so
they survive any row rotation, byte order or colour-bit convention.
"""
import sys, time

def stream(columns, trailing_zeros):
    body = [0x00, 0x81, len(columns) + 2, 0x00, 0x03, 0x00, 0x00, 0x00]
    for c in columns: body += [c & 0xFF, c >> 8]
    body += [0x00, 0x00] + [0x00] * trailing_zeros
    return body

ON, OFF = 0xFFFF, 0x0000
candidates = [
    # base, name, signature description, stream bytes
    (0x00, "P0 bare stream at 0x00 (E2a retest, correct write order)",
           "6 solid columns: one narrow, sharp-edged bright wedge",
           stream([ON] * 6, 2)),                                   # 0x00..0x17
    (0x18, "P1 bare stream at 0x18 (count byte 0x19, length byte 0x1A: the stall range)",
           "12 columns alternating on/off: a comb of six hairlines",
           stream([ON, OFF] * 6, 6)),                              # 0x18..0x3F
    (0x40, "P2 upload-header bytes ahead of the stream at 0x40 (D15 candidate 1)",
           "16 columns as 4 on / 4 off / 4 on / 4 off: two thick bars",
           [0x01, 0x00, 0x00, 0x00, 0x00] + stream([ON]*4 + [OFF]*4 + [ON]*4 + [OFF]*4, 0)),  # 0x40..0x6E
    (0x80, "P3 bare stream at 0x80 (round-base hedge)",
           "32 solid columns: one wide, bright, solid arc",
           stream([ON] * 32, 0)),                                  # 0x80..0xC9
]
# P2's header: size class 1 (stream < 256 bytes), then the real length of the stream that follows
p2 = candidates[2]; body = p2[3]; body[1] = len(body) - 5; body[2] = 0

image = [0x00] * 256
for base, name, sig, body in candidates:
    assert base + len(body) <= 256
    for i, b in enumerate(body):
        assert image[base + i] == 0, "overlap at 0x%02x" % (base + i)
        image[base + i] = b
ends = [(base, base + len(body) - 1) for base, _, _, body in candidates]
for (b1, e1), (b2, e2) in zip(ends, ends[1:]):
    assert e1 < b2, "candidates overlap"

packets = []
def pkt(header, data):
    p = header + list(data); p += [0] * (8 - len(p)); packets.append(p)
# 1. 16-bit hedge, page 4 then page 0, descending so the lo=0 chunk lands last
for hi in (0x04, 0x00):
    for lo in range(255, -1, -5):
        chunk = image[lo:lo + 5]
        if len(chunk) < 5: chunk = chunk + [0] * (5 - len(chunk))
        pkt([0xA0, hi, lo], chunk)
# 2. 8-bit block 0, ascending, last: an 8-bit device ends exactly equal to `image`
for a in range(0, 256, 6):
    pkt([0xA0, a], image[a:a + 6])
# 3. the same image in the next two 8-bit blocks of a 24C04/24C08, in case the parser's block differs
for blk in (0xA2, 0xA4):
    for a in range(0, 256, 6):
        pkt([blk, a], image[a:a + 6])

with open("Tools/probe-output/2026-09-02-slice6-image.hex", "w") as f:
    for row in range(0, 256, 16):
        f.write("%02x: %s\n" % (row, " ".join("%02x" % b for b in image[row:row+16])))
with open("Tools/probe-output/2026-09-02-slice6-packets.hex", "w") as f:
    for p in packets: f.write(" ".join("%02X" % b for b in p) + "\n")
print("image and %d packets written" % len(packets))
for (base, name, sig, body) in candidates:
    print("  0x%02x-0x%02x  %-78s  signature: %s" % (base, base + len(body) - 1, name, sig))

if "--send" in sys.argv:
    import hid
    d = hid.device(); d.open(0x0C45, 0x7701)
    fails = 0; slow = 0; t0 = time.time()
    for i, p in enumerate(packets):
        t = time.time(); n = d.write(bytes([0x00] + p)); dt = (time.time() - t) * 1000
        if n < 0: fails += 1; print("FAIL packet %d %s (%s)" % (i, " ".join("%02X" % b for b in p), d.error()), flush=True)
        elif dt > 10: slow += 1; print("slow  packet %d %s %.0f ms" % (i, " ".join("%02X" % b for b in p), dt), flush=True)
        time.sleep(0.012)
    print("sent %d packets in %.1f s: fails=%d slow=%d" % (len(packets), time.time() - t0, fails, slow))
