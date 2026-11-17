# Hotchpotch — LGPL corresponding source

This repository holds the complete corresponding source for the LGPL-licensed libraries shipped inside the
Hotchpotch Android app (arm64-v8a), as required by the GNU Lesser General Public License v2.1 (§6). The app's own
code is not part of these libraries and is not published here.

Each library is shipped as its **own shared library** (`.so`) and loaded dynamically, so you can rebuild it from this
source, modify it, and replace it in the app.

| Library in the APK | Component | Version | Licence | Upstream | Source archive (release asset) | SHA-256 |
|---|---|---|---|---|---|---|
| `libavutil.so`, `libavcodec.so`, `libavformat.so`, `libswresample.so`, `libswscale.so`, `libavfilter.so` | FFmpeg | 6.0 (commit `3949db4d261748a9f34358a388ee255ad1a7f0c0`) | LGPL-2.1-or-later | https://github.com/FFmpeg/FFmpeg/tree/3949db4d261748a9f34358a388ee255ad1a7f0c0 | `ffmpeg-6.0-3949db4d.tar.gz` | `78b2b6ade6364f8cf2795d89be96173566dc5caeaf54a05a5c64646cb9ad0b34` |
| `libfribidi.so` | GNU FriBidi | 1.0.18 | LGPL-2.1-or-later | https://github.com/fribidi/fribidi/tree/v1.0.18 | `fribidi-1.0.18.tar.xz` | `1de5e8073d035388b71d0b2d452b1da1f8caeea8a7702997b401fe1b6250727f` |
| `libsmb2.so` | libsmb2 | 6.3 | LGPL-2.1-or-later | https://github.com/sahlberg/libsmb2/tree/libsmb2-6.3 | `libsmb2-6.3.tar.gz` | `5011003fd091513f897e1ebbb8e1a40af634386df7199716348b7f77569a2790` |

The source archives are attached to each release of this repository (tag = app version). They are the unmodified
upstream archives; every change made at build time is in the scripts below.

## How each library is built

All three are built with the Android NDK r30 (`30.0.16248370`), target `aarch64-linux-android`, API level 24, 16 KB
ELF page alignment (`-Wl,-z,max-page-size=16384`).

- **FFmpeg** — [`ffmpeg/build_ffmpeg_android.sh`](ffmpeg/build_ffmpeg_android.sh): the exact `configure` options
  (`--disable-gpl --disable-nonfree --disable-version3`, shared libraries only, no external libraries, zlib from the
  Android system; the `dca`, `truehd`, `mlp`, `eac3`, `hevc`, `vp9` and `av1` decoders are not built; libavfilter
  holds only `buffer`, `buffersink`, `bwdif`, `yadif`, `w3fdif`). The only source change is a build-system tweak the
  script applies with `sed` to `ffbuild/library.mak` (link through a response file, to stay under the Windows command
  line limit); the produced code is unchanged by it.
- **FriBidi** — [`fribidi/build_libass_android.sh`](fribidi/build_libass_android.sh): built with Meson as a shared
  library (`-Dfribidi:default_library=shared`, docs, tests and binaries off) as a subproject of the libass build. No
  source change.
- **libsmb2** — built with its own CMake as a shared library (`BUILD_SHARED_LIBS=ON`, examples off); see
  [`libsmb2/CMakeLists-excerpt.txt`](libsmb2/CMakeLists-excerpt.txt). One file is added to that library:
  [`libsmb2/smb2_stub.c`](libsmb2/smb2_stub.c) (creates a context with SMB signing enabled), and the exported symbols
  are `smb2_*` ([`libsmb2/smb2_exports.map`](libsmb2/smb2_exports.map)). These two files are offered under the same
  licence as libsmb2 (LGPL-2.1-or-later).

The scripts refer to the app repository's folder layout (`third_party/<name>` for the extracted archive); unpack the
archive there, or change the paths at the top of the script.

## Replacing a library in the app

1. Build the library as above (same ABI, same `SONAME` — the names carry no version number).
2. Unpack the APK, replace `lib/arm64-v8a/<name>.so`, and repack it.
3. Align with `zipalign -P 16 -f 4` and sign it with your own key (`apksigner sign`).
4. Uninstall the store version (signatures differ) and install yours.

The app does not check its own integrity, so a replaced library is loaded as is.

Checked for v0.1.0 (2026-11-18): FriBidi rebuilt from this release's archive on its own (Meson, the cross file in
`fribidi/build_libass_android.sh`, `default_library=shared`) with one change to `lib/fribidi.c` (a marker in
`fribidi_version_info`), put into the APK as above, aligned, re-signed and installed over the app on a test tablet
(Android 15). The running app maps the new `libfribidi.so` from the APK and ASS subtitles draw as before.

## 한국어 요약

Hotchpotch 안드로이드 앱에 들어간 LGPL 라이브러리(FFmpeg, FriBidi, libsmb2)의 대응 소스입니다. 앱 코드는 여기에
없습니다. 각 라이브러리는 별도 공유 라이브러리(`.so`)라서, 이 소스로 다시 빌드해 APK 안의 파일을 바꾼 뒤 직접
서명해 설치할 수 있습니다. 원본 소스 묶음은 릴리스(태그 = 앱 버전)에 붙어 있고, 빌드 때의 변경은 모두 스크립트에
있습니다.

The full licence text is in [`COPYING.LGPLv2.1`](COPYING.LGPLv2.1).
