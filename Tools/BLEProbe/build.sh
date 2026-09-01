#!/bin/bash
# Builds the probe with an embedded Info.plist so CoreBluetooth will grant permission.
set -e
cd "$(dirname "$0")"
swiftc -O BLEProbe.swift -o bleprobe \
  -framework CoreBluetooth \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist
codesign -s - -f ./bleprobe >/dev/null 2>&1 || true
echo "built ./bleprobe"
