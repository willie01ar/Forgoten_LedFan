#!/bin/bash
# Interface + HID report descriptor detail for the SONiX 0x0C45:0x7701 fan.
cd "$(dirname "$0")/.."
{
  echo "=== full USB device node ==="
  ioreg -p IOUSB -w0 -l -r -c IOUSBHostDevice

  echo
  echo "=== interfaces (class 3 = HID, 10 = CDC data, 255 = vendor-specific) ==="
  ioreg -c IOUSBHostInterface -r -w0 -l | grep -E '\+-o|bInterfaceClass|bInterfaceSubClass|bInterfaceProtocol|bNumEndpoints|bAlternateSetting'

  echo
  echo "=== endpoints ==="
  ioreg -c IOUSBHostInterface -r -w0 -l | grep -E 'bEndpointAddress|bmAttributes|wMaxPacketSize|bInterval'

  echo
  echo "=== did it bind as HID? ==="
  ioreg -c IOHIDDevice -r -w0 -l | grep -E '\+-o|"VendorID"|"ProductID"|"Transport"|"MaxInputReportSize"|"MaxOutputReportSize"|"MaxFeatureReportSize"|"PrimaryUsagePage"|"PrimaryUsage"'

  echo
  echo "=== HID report descriptor (raw bytes) ==="
  ioreg -c IOHIDDevice -r -w0 -a 2>/dev/null | plutil -p - 2>/dev/null | grep -A40 -i "ReportDescriptor"

  echo
  echo "=== serial device nodes ==="
  ls -l /dev/cu.* 2>/dev/null

  echo
  echo "=== which driver claimed it ==="
  ioreg -p IOService -w0 -l -r -c IOUSBHostDevice | grep -E '\+-o|"IOClass"|"CFBundleIdentifier"'
} > hidprobe.txt 2>&1
echo "wrote hidprobe.txt ($(wc -l < hidprobe.txt) lines)"
