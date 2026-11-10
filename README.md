# ImageOptim

[ImageOptim](https://imageoptim.com) is a GUI for lossless image optimization tools: Zopfli, PNGOUT, [OxiPNG](https://lib.rs/crates/oxipng), AdvPNG, PNGCrush, [JPEGOptim](https://github.com/tjko/jpegoptim), Jpegtran, [Guetzli](https://github.com/google/guetzli), [Gifsicle](https://kornel.ski/lossygif), [SVGO](https://github.com/svg/svgo), [svgcleaner](https://github.com/RazrFalcon/svgcleaner) and [MozJPEG](https://github.com/mozilla/mozjpeg).

## Building

Requires:

* An Apple Silicon Mac with Xcode 27 or later and the macOS SDK. Builds target `arm64` only; the deployment minimum is macOS 12.
* [Rust](https://rust-lang.org/) 1.88 or later, installed via [rustup](https://www.rustup.rs/) (not Homebrew).
* Node.js 16 or later and npm for building the bundled SVGO script.
* `rsvg-convert` from librsvg for the SVG rendering tests (`brew install librsvg`).

```sh
git clone --recursive https://github.com/psynix/ImageOptim.git
cd ImageOptim
make build
```

The local Release app is `imageoptim/build/Build/Products/Release/ImageOptim.app`.
`make build` prepares downloaded sources before Xcode scans them and overrides the
deployment target and architecture for every dependency, including Sparkle's separate
configuration. PNGOUT is thinned to Apple Silicon and uses the build's signing
identity when available, otherwise an ad-hoc signature. Rust packaging copies the
ARM executables directly, with explicit build dependencies.
This local build uses ad-hoc signing with hardened runtime disabled, so it does
not require the upstream developer's certificate. The distribution configuration
in `release.xcconfig` retains hardened runtime.

Run the app-hosted tests on the current Mac:

```sh
make test
```

`make test` runs the native app tests and SVG rendering comparisons. Set
`RSVG_CONVERT` to the renderer's executable path if it is not on `PATH`.
The shared `ImageOptim` scheme includes the backend and file-import tests. For IDE
debugging, open `imageoptim/ImageOptim.xcodeproj`; use the same global deployment
overrides (`MACOSX_DEPLOYMENT_TARGET=12.0 ARCHS=arm64`) when building the vendored Sparkle project.
Apple's [Xcode support table](https://developer.apple.com/support/xcode/) describes SDK deployment limits.

## Optimisation findings

The pipeline runs format-specific tools and keeps a result only when it is smaller.
Lossy conversion remains controlled by the existing Preferences settings.

| Finding | Change or next action |
| --- | --- |
| Static PNG tools can discard animated PNG frames. | Animated PNGs now use OxiPNG exclusively. Tests compare decoded frame pixels, frame count, delays, and loop settings. Disabling OxiPNG leaves the original untouched with an explanatory error. |
| Worker caches used byte size as content identity and could record a different worker's output. Cancelled jobs could also enter the persistent cache. | New optimisation requests discard the per-worker size cache. Concurrent replacement prevents recording an unprocessed input. The persistent content cache now includes worker class identity in its settings hash and excludes interrupted runs. |
| Cancelling just after an optimiser accepted output could delete that output. | Accepted temporary files remain owned by the job after cancellation. |
| Several OxiPNG processes can each use every CPU core. | A quiet OxiPNG 10.2.1 comparison found that forcing one thread slowed both single-image and six-way batch work. Keep its default threading. |
| Old engines and SVG transformations needed validation. | Updated OxiPNG, JPEGOptim, Gifsicle, and SVGO after format-specific regression comparisons. The results and trade-offs are below. |

### Engine upgrades and measured results

| Component | Change | Evidence and trade-off |
| --- | --- | --- |
| MozJPEG 4.1.5 | Enabled the upstream ARM NEON SIMD (vector acceleration) sources. | Six JPEGs totalling 2,314,903 bytes, three alternating quiet trials: jpegtran median 0.829s scalar / 0.488s NEON (1.70×); lossy JPEGOptim quality 80 median 0.960s / 0.699s (1.37×). Scalar and NEON lossless outputs were byte-identical. |
| [JPEGOptim 1.5.6](https://github.com/tjko/jpegoptim/releases/tag/v1.5.6) | Replaced 1.4.4 and integrated its new source files. | All six upstream tests passed. The six-file comparison retained lossless pixels and COM/Exif/ICC metadata when requested. Lossy quality-80 output was 949 bytes smaller overall, with the same decoded pixels as 1.4.4. |
| [OxiPNG 10.2.1](https://github.com/oxipng/oxipng/releases/tag/v10.2.1) | Replaced 9.0.0 and updated the interlace argument. | All 296 upstream tests passed. Across 24 PNG fixtures, six outputs were smaller, fifteen equal, and three larger than version 9, with either metadata setting. The new version fixes RGB-profile/grayscale conversion in the regression corpus; smaller output from the old rendering error is not a useful compression gain. |
| [Gifsicle 1.98](https://www.lcdf.org/gifsicle/changes.html) | Replaced the 1.88 giflossy fork, removed the obsolete patch, and reject malformed reads with `--no-ignore-errors`. | 84 appearance/timing/loop comparisons passed. Across 76 matched cases, applying the app's smaller-output rule produced 481,033 bytes versus 480,951 previously (+0.017%). Lossy quality 80 had equal or lower decoded error on nine fixtures, often with larger output. No speed improvement is claimed. |
| [SVGO 4.1.0](https://github.com/svg/svgo/releases/tag/v4.1.0) and svgcleaner | Replaced SVGO 1.x, pinned npm dependencies, and made lossless transformations conservative. | Eight SVG fixtures cover precision, CSS selectors, text, raster content, IDs, accessibility, references, whitespace, and animation. Sensitive documents pass through unchanged. Svgcleaner accepts lossless output only when canonical XML still matches, including whitespace. |

The JPEG timings compare the same accelerated binary with normal dispatch and
`JSIMD_FORCENONE=1`, including process startup and file I/O. They measure these
fixtures on this Apple Silicon Mac, not expected speedups for every image or
whole application batches. The OxiPNG thread check used six PNGs totalling
1,223,733 bytes and two alternating trials. Default threading took 0.357–0.358s
for the single-image case and 0.429–0.449s for the batch; one thread took
0.461–0.464s and 0.496s respectively, with identical output sizes.

SVGO's lossless mode preserves geometry and colour tokens. Optional lossy mode
rounds paths and transforms; its fixture gate allows only a small measured raster
difference. SVGs containing CSS, scripts, foreign objects, stylesheet instructions,
or SMIL animation retain their original content in both modes, because those
features can observe parser whitespace or geometry rewrites. The old SVGO 1
lossless configuration changed rendering in the CSS-selector and text/raster
fixtures; the new configuration preserves them.

SVGO still needs an external Node executable. It now searches absolute directories
on `PATH`, then the Homebrew locations. The default SVG tool remains svgcleaner,
which works without Node; its stricter acceptance may leave more files unchanged.
pngquant remains 3.0.2: the 3.0.3 tag changes packaging/version metadata and an
upstream Xcode project, with no changes to the optimiser C/Rust sources or library
gitlink, so that version bump offers no optimisation benefit here.

PNG defaults also allow changing invisible RGB values under full transparency;
lossless here does not promise preservation of those hidden values or all metadata.

For the larger GIF regression corpus after building, run:

```sh
python3 scripts/check-gif.py imageoptim/build/Build/Products/Release/gifsicle
```

## macOS 27 compatibility

File import now uses `NSURL` pasteboard items for drag-and-drop, Copy/Paste, and
Finder Services. The Open panel uses `UTType` filters and explicitly enables folder
selection after setting those filters, as required by the macOS 27 AppKit behaviour
described in [Apple's release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes).

Distribution still uses the upstream bundle identifiers, app-group entitlements,
Sparkle 1.x, and the official ImageOptim update feed. A separately distributed fork
needs its own signing/notarisation and updater configuration before release.

## Validation

Checked on macOS 27.2.1 with Xcode 27.2 and the macOS 27.2 SDK on 2026-11-10:

* A clean `make build` passed. All 19 bundled Mach-O files are thin `arm64` binaries, including frameworks, extensions, updater executables, and optimiser tools; recursive code-signature verification passed. The app's file contents total 9,785,425 bytes, down from 16,564,309 for the universal build (40.9% smaller).
* `make test` passed all 30 native tests plus eight SVG fixtures: 30 exact raster comparisons and two bounded lossy comparisons. The SVG corpus shrank from 3,302 to 3,163 bytes lossless or 3,108 bytes lossy; maximum lossy channel difference was 5/255.
* Native Release-backend smoke checks passed for PNG, JPEG, GIF, and SVG. The three raster formats retained identical decoded pixels; SVG output parsed successfully.
* Gifsicle's extended corpus passed 84 appearance/timing/loop checks and rejected ten malformed or unsupported cases. OxiPNG passed 296 upstream tests; JPEGOptim passed six. The two-frame animated PNG app test also preserves frame pixels, timing, and loop count.

These are fixture results, not expected savings for arbitrary images. Intel Macs
are not supported by this fork. Developer ID signing, notarisation, and a
fork-specific updater were not tested.
