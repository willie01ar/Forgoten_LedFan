# Not the software

`USB DATA DOWNLOAD SYATEMled编程软件 v20 绿色免费版_1177_632ae.exe` (1,038,472 bytes,
downloaded 2026-09-03 from a Chinese mirror) is **a libcurl-based downloader stub**, not the
LED fan editor.

Evidence (static analysis only, never executed):
- Strings are libcurl/schannel internals: "Content-Length", "cookie", "nameserver",
  "schannel: an unrecoverable error occurred in a prior call".
- No `OpenUSBDevice`, `WriteUSB`, `HidD_*`, `SetupDi*` or `hid.dll` strings anywhere.
- The six "immediate-looking" `0x7701` byte pairs are all `83 f9 01` / `77 xx` — a
  `cmp ecx, 1` followed by a short `ja`. Coincidence in ordinary branch code, not a PID.

It is the download site's wrapper, which fetches the real archive at runtime on Windows.
Kept only so nobody re-downloads it thinking it is the editor. Do not run it.
