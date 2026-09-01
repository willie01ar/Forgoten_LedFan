#!/bin/bash
set -e
cd "$(dirname "$0")"
swiftc -O hidfan.swift -o hidfan -framework IOKit -framework CoreFoundation
echo "built ./hidfan"
