"""Fill EEPROM blocks under the 8-bit address model: [block][addr][6 data bytes], addr stepping by 6.
Usage: python fill.py <payload hex byte> <block hex>...   e.g. fill.py 00 A0 A2 A4 A6"""
import sys, time, hid
payload = int(sys.argv[1], 16); blocks = [int(b, 16) for b in sys.argv[2:]]
d = hid.device(); d.open(0x0C45, 0x7701)
slow = 0; fails = 0; t0 = time.time()
for blk in blocks:
    for addr in range(0, 256, 6):
        pkt = bytes([0x00, blk, addr] + [payload]*6)
        t = time.time(); n = d.write(pkt); dt = (time.time()-t)*1000
        if n < 0: fails += 1; print(f"FAIL {blk:02X} {addr:02X} after {dt:.0f} ms ({d.error()})", flush=True)
        elif dt > 10: slow += 1
        time.sleep(0.01)   # give a page write time to finish before the next one
print(f"filled blocks {[f'{b:02X}' for b in blocks]} with {payload:02X}: fails={fails}, slow={slow}, {time.time()-t0:.1f}s")
