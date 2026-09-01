#!/bin/bash
# Differential USB snapshot. ioreg only — system_profiler SPUSBDataType is broken on this Mac.
cd "$(dirname "$0")/.."

snapshot() {
  ioreg -p IOUSB -w0
  echo "--- device detail ---"
  ioreg -c IOUSBHostDevice -r -w0 | grep -E '"USB Product Name"|"USB Vendor Name"|"idVendor"|"idProduct"|"bDeviceClass"|"bcdDevice"'
}

echo "1. UNPLUG the fan completely. Then press return."
read -r
snapshot > usb_before.txt
echo "   baseline: $(grep -c 'IOUSBHostDevice' usb_before.txt) device node(s)"

echo
echo "2. Plug the fan DIRECTLY into a Mac port with a plain USB-A→USB-C adapter."
echo "   Not through the Multiport Adapter. Switch it on. Wait 5 seconds. Press return."
read -r
sleep 2
snapshot > usb_after.txt
echo "   now:      $(grep -c 'IOUSBHostDevice' usb_after.txt) device node(s)"

echo
echo "=== what changed ==="
if diff -q usb_before.txt usb_after.txt >/dev/null; then
  echo "NOTHING. The fan does not enumerate on that port."
else
  diff usb_before.txt usb_after.txt | tee usb_diff.txt
fi
