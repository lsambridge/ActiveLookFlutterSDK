# Images & fonts

[← Back to docs index](README.md)

## Images {#images}

```dart
Future<List<ActiveLookImageInfo>> imgList()
Future<void> imgSave(int id, List<int> pngBytes, ActiveLookImageFormat format)
Future<void> imgDisplay(int id, int x, int y)
Future<void> imgDelete(int id)
Future<void> imgDeleteAll()
Future<void> imgStream(List<int> pngBytes, ActiveLookImageStreamFormat format, int x, int y)
```

**Image bytes are always PNG-encoded** at this API boundary, regardless of platform — pass the raw
bytes of a `.png` file (from `rootBundle.load(...).buffer.asUint8List()`, an `Image.toByteData` +
PNG encode, a downloaded file, etc.). Each native platform decodes that PNG into its own bitmap
type (`android.graphics.Bitmap` / `UIImage`) before calling the underlying SDK — you never touch
platform bitmap types from Dart.

```dart
final bytes = (await rootBundle.load('assets/icons/heart.png')).buffer.asUint8List();
await sdk.imgSave(1, bytes, ActiveLookImageFormat.mono4bpp);
await sdk.imgDisplay(1, 20, 20);
```

`imgSave` **persists** the image to the glasses' flash storage under `id`, for repeated
`imgDisplay` calls later without re-sending the data. `imgStream` **draws directly without
saving** — cheaper for a genuinely one-off image, more expensive if you'll show the same image
again (you pay the full transfer cost every time).

### Format enums

```dart
enum ActiveLookImageFormat { mono4bpp, mono1bpp, mono4bppHeatshrink, mono4bppHeatshrinkSaveComp }
enum ActiveLookImageStreamFormat { mono1bpp, mono4bppHeatshrink }  // streaming supports fewer formats
```

- `mono4bpp` — 16 grey levels, uncompressed.
- `mono1bpp` — black/white only, smallest payload.
- `mono4bppHeatshrink` — 16 grey levels, Heatshrink-compressed on the wire, decompressed to 4bpp by
  the firmware before saving.
- `mono4bppHeatshrinkSaveComp` — as above, but stored compressed on-device and decompressed only at
  display time (smaller flash footprint, marginally slower display).

`imgStream` only supports `mono1bpp`/`mono4bppHeatshrink` on either native SDK — there is no
streaming equivalent of the other two `imgSave`-only formats. This isn't a bridge limitation; it's
how both native SDKs are built.

⚠️ **Known upstream bug**: iOS's `imgStream` dispatcher has a confirmed coordinate-passing bug for
the 1bpp format (see [Known issues](known-issues.md)) — test 1bpp streaming specifically on iOS
before relying on it.

## Fonts {#fonts}

```dart
Future<List<ActiveLookFontInfo>> fontList()
Future<void> fontSave(int id, List<int> fontBytes)
Future<void> fontSelect(int id)
Future<void> fontDelete(int id)
Future<void> fontDeleteAll()
```

`fontSave`'s `fontBytes` is the raw encoded font data in whatever binary format ActiveLook's own
font-conversion tooling produces (see `ActiveLook_API.md`'s font section, or the pre-baked fonts in
`Activelook-Visual-Assets`) — this package passes it through unmodified, it does not parse or
validate font data.

`fontSelect(id)` sets which font subsequent [`text()`](drawing.md) calls use — call it once before
a batch of text draws rather than specifying font ID per-call, since `text()`'s own `fontSize`
parameter is a font *ID* reference, not a point size (see [Drawing](drawing.md)).

⚠️ **Known upstream bug**: iOS's `fontList()` (named `fontlist()` in the native SDK — note the
casing) has a callback ActiveLook's own source code comments describe as "NOT WORKING as of
3.7.4b." Do not rely on this returning real data on iOS until ActiveLook fixes it upstream — see
[Known issues](known-issues.md).

## When to use images/fonts vs. text/layouts

Prefer [`text()`](drawing.md)/[layouts](layouts-gauges-pages-animations.md) for anything that
changes at runtime (a live pace number, a heart-rate reading) — they're a handful of bytes per
update. Reserve images for genuinely static graphical content (a logo, a custom icon set, a
splash screen) that doesn't change during a session, since `imgSave`'s payload is meaningfully
larger than a text/layout update even with compression.
