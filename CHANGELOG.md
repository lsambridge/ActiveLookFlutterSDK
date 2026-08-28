## 1.0.0-beta.1

Initial pre-release. Full API parity with both native SDKs (`android-sdk` 4.5.9, `ios-sdk` 4.5.5):

- Scanning, connecting, connection-state and device-info queries.
- Vector drawing primitives (point/line/rect/circle/text/polyline), display state (color, shift,
  hold/flush), and general device commands (power, grey, led, luma, sensor toggles).
- Layouts, gauges, pages, and animations.
- Device event streams: battery level, flow control, sensor tap (double-tap only).
- Image/bitmap commands (save/display/delete/stream) and font management.
- Firmware configuration management (`cfgSet`/`cfgWrite`/`cfgRead`/`cfgList`/`cfgRename`/
  `cfgDelete`/`cfgDeleteLessUsed`/`cfgFreeSpace`/`cfgGetNb`/`shutdown`).
- Statistics queries (pixel count, charging counters).
- Legacy firmware-1.7-only configuration commands (`legacyWriteConfig`/`legacyReadConfig`/
  `legacySetConfig`/`tdbg`).
- The full iOS-only widget-gauge command family, with typed
  `ActiveLookUnsupportedOnPlatformException` on Android.

See [`docs/known-issues.md`](docs/known-issues.md) for confirmed upstream ActiveLook SDK bugs and
platform divergences discovered while building this, and
[`docs/known-issues.md#verification-depth-by-platform`](docs/known-issues.md#verification-depth-by-platform)
for the current verification state: Android is compiled and unit-tested against the real native
SDK; iOS has not yet been compiled (no macOS/Xcode toolchain was available while building this).
Neither platform has been exercised against real hardware yet.
