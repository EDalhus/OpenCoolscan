# Nikon Scan Re:make

A modern macOS SwiftUI remake of Nikon Scan 4 for Coolscan film scanners.

## Requirements

- macOS 13+
- [SANE](http://www.sane-project.org/) with the `coolscan3` backend  
  ```bash
  brew install sane-backends
  ```
- A supported Nikon film scanner (or use the built-in Simulated Scanner)

## Build

```bash
./build.sh
open NikonScan.app
```

Or with SwiftPM directly:

```bash
swift build -c release
.build/release/NikonScan
```

## Features

- USB detection for Coolscan models (LS-30 through LS-9000)
- Preview / multi-frame scan via `scanimage`
- Crop (WYSIWYG preview + hardware geometry on final scan)
- Digital ICE (infrared) when the holder/mode supports it
- Tone, curves, color balance, film presets
- Batch save, cancel in-flight scans, scratch disk / auto-save
