"""Write a byte stream to EEPROM address 0 via the A0 bridge, hedged for both address models.
  8-bit model:  A0 addr d0..d5          (addr step 6, ascending)
  16-bit model: A0 00 lo d0..d4         (lo step 5, DESCENDING so the lo=0 chunk lands last; on an
                                          8-bit device that final packet rewrites bytes 0..5 correctly
                                          because the stream starts with 0x00)
Usage: python write_stream.py <hexbytes...>   or   python write_stream.py --file stream.hex"""
import sys, time, hid
if sys.argv[1] == "--file":
    stream = bytes.fromhex(open(sys.argv[2]).read())
else:
    stream = bytes.fromhex("".join(sys.argv[1:]))
assert stream[0] == 0x00, "stream must start with 0x00 for the hedge to hold"
d = hid.device(); d.open(0x0C45, 0x7701)
def send(body):
    n = d.write(bytes([0x00] + body)); time.sleep(0.012)
    if n < 0: print("FAIL", bytes(body).hex(" "), d.error(), flush=True)
pad6 = stream + bytes(-len(stream) % 6)
for a in range(0, len(pad6), 6):
    send([0xA0, a] + list(pad6[a:a+6]))
pad5 = stream + bytes(-len(stream) % 5)
for lo in range(len(pad5) - 5, -1, -5):
    send([0xA0, 0x00, lo] + list(pad5[lo:lo+5]))
print(f"wrote {len(stream)} bytes ({len(pad6)//6} + {len(pad5)//5} packets)")
