#!/usr/bin/env bash
# ARCHITECTURE.md §8.4 / VIDEO_PLAYER.md §8.1 (G21, 2026-11-18): libass and the libraries it needs, for
# arm64-v8a, linked into core:playback's libhpass.so.
#   static: libass (ISC), FreeType (FTL), HarfBuzz (MIT), fontconfig (MIT-style), Expat (MIT)
#   shared: FriBidi (LGPL-2.1) - WHY shared: like FFmpeg (§8.1 'LGPL 현황'), so a user can relink it.
# One Meson cross build of libass with the others as local subprojects (libass's own dependency() calls fall
# back to them). Needs meson (pip install --user meson) + ninja, the NDK, and gperf on the host for fontconfig's perfect
# hash - built once from GNU gperf 3.1 into third_party/.tools (a build tool only; nothing of it ships).
# Run ./scripts/vendor_c_libs.sh --only-libass first.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TP="${REPO_ROOT}/third_party"
WORK="${TP}/libass-build"
PREFIX="${TP}/libass/android-libs/arm64-v8a"
BUILD_DIR="${WORK}/build-android-arm64"

for lib in libass freetype fribidi harfbuzz fontconfig expat; do
    [[ -d "${TP}/${lib}" ]] || { echo "Missing ${TP}/${lib}. Run ./scripts/vendor_c_libs.sh --only-libass first." >&2; exit 1; }
done

if [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
    NDK_PATH="${ANDROID_NDK_HOME}"
elif [[ -n "${ANDROID_NDK_ROOT:-}" ]]; then
    NDK_PATH="${ANDROID_NDK_ROOT}"
else
    NDK_PATH="$(cygpath -u "${LOCALAPPDATA}")/Android/Sdk/ndk/30.0.16248370"
fi
TOOLCHAIN="${NDK_PATH}/toolchains/llvm/prebuilt/windows-x86_64"
[[ -d "${TOOLCHAIN}" ]] || TOOLCHAIN="${NDK_PATH}/toolchains/llvm/prebuilt/linux-x86_64"
BIN="${TOOLCHAIN}/bin"
API=24

MESON="${MESON:-meson}"
if ! command -v "${MESON}" >/dev/null 2>&1; then
    MESON="python -m mesonbuild.mesonmain"
fi

# gperf (host tool) for fontconfig's fcobjshash.h.
GPERF_DIR="${TP}/.tools/gperf-3.1"
if ! command -v gperf >/dev/null 2>&1; then
    if [[ ! -x "${GPERF_DIR}/gperf.exe" && ! -x "${GPERF_DIR}/gperf" ]]; then
        [[ -f "${TP}/.dist/gperf-3.1.tar.gz" ]] || { echo "Missing third_party/.dist/gperf-3.1.tar.gz (vendor_c_libs.sh --only-libass)." >&2; exit 1; }
        mkdir -p "${TP}/.tools"
        tar -xzf "${TP}/.dist/gperf-3.1.tar.gz" -C "${TP}/.tools"
        printf '#define HAVE_DYNAMIC_ARRAY 1\n#define PACKAGE_BUGREPORT ""\n#define PACKAGE_NAME "gperf"\n#define PACKAGE_STRING "gperf 3.1"\n#define PACKAGE_TARNAME "gperf"\n#define PACKAGE_URL ""\n#define PACKAGE_VERSION "3.1"\n' > "${GPERF_DIR}/src/config.h"
        (cd "${GPERF_DIR}" && g++ -O2 -std=gnu++98 -Isrc -Ilib src/*.cc lib/getline.cc lib/hash.cc -x c lib/getopt.c lib/getopt1.c -o gperf)
    fi
    export PATH="${GPERF_DIR}:${PATH}"
fi

to_native() { cygpath -m "$1" 2>/dev/null || echo "$1"; }

# Workspace: libass with the other five as subprojects (copies - the extracted trees stay pristine).
rm -rf "${WORK}" "${PREFIX}"
mkdir -p "${WORK}" "${PREFIX}"
cp -r "${TP}/libass" "${WORK}/libass"
rm -rf "${WORK}/libass/android-libs"
SUB="${WORK}/libass/subprojects"
mkdir -p "${SUB}"
cp -r "${TP}/freetype" "${SUB}/freetype2"
cp -r "${TP}/fribidi" "${SUB}/fribidi"
cp -r "${TP}/harfbuzz" "${SUB}/harfbuzz"
cp -r "${TP}/fontconfig" "${SUB}/fontconfig"
rm -rf "${SUB}/fontconfig/subprojects"
cp -r "${TP}/expat" "${SUB}/expat"

# A directory that already exists is used as is; [provide] lets libass's (and fontconfig's) dependency()
# calls fall back to it.
wrap() { printf '[wrap-file]\ndirectory = %s\n\n[provide]\n%s\n' "$1" "$2" > "${SUB}/$1.wrap"; }
wrap freetype2 "dependency_names = freetype2"
wrap fribidi "dependency_names = fribidi"
wrap harfbuzz "dependency_names = harfbuzz"
wrap fontconfig "fontconfig = fontconfig_dep"
wrap expat "expat = expat_dep"

# Expat ships CMake only; its library is a handful of C files (2.10: xcs.c and the entropy source, here
# arc4random_buf, beside the parser) and one config header.
cat > "${SUB}/expat/expat_config.h" <<'EOF'
#pragma once
/* Written by scripts/build_libass_android.sh for Android (bionic, little endian). */
#define BYTEORDER 1234
#define HAVE_ARC4RANDOM 1
#define HAVE_ARC4RANDOM_BUF 1
#define HAVE_DLFCN_H 1
#define HAVE_FCNTL_H 1
#define HAVE_GETPAGESIZE 1
#define HAVE_INTTYPES_H 1
#define HAVE_MMAP 1
#define HAVE_STDINT_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1
#define STDC_HEADERS 1
#define XML_CONTEXT_BYTES 1024
#define XML_DTD 1
#define XML_GE 1
#define XML_NS 1
EOF
cat > "${SUB}/expat/meson.build" <<'EOF'
project('expat', 'c', version: '2.10.0')
expat_lib = static_library('expat',
  'lib/xmlparse.c', 'lib/xmltok.c', 'lib/xmlrole.c', 'lib/xcs.c', 'lib/random_arc4random_buf.c',
  c_args: ['-DHAVE_EXPAT_CONFIG_H', '-DXML_ENABLE_VISIBILITY=1'],
  include_directories: include_directories('.', 'lib'),
  pic: true,
  install: true)
install_headers('lib/expat.h', 'lib/expat_external.h')
expat_dep = declare_dependency(link_with: expat_lib, include_directories: include_directories('lib'))
meson.override_dependency('expat', expat_dep)
EOF

CROSS_FILE="${WORK}/android-arm64.meson"
cat > "${CROSS_FILE}" <<EOF
[binaries]
c = '$(to_native "${BIN}/aarch64-linux-android${API}-clang.cmd")'
cpp = '$(to_native "${BIN}/aarch64-linux-android${API}-clang++.cmd")'
ar = '$(to_native "${BIN}/llvm-ar.exe")'
strip = '$(to_native "${BIN}/llvm-strip.exe")'

[built-in options]
c_args = ['-fPIC', '-g']
cpp_args = ['-fPIC', '-g']
c_link_args = ['-Wl,-z,max-page-size=16384']
cpp_link_args = ['-Wl,-z,max-page-size=16384']

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF
if [[ ! -f "${BIN}/aarch64-linux-android${API}-clang.cmd" ]]; then
    sed -i -e 's/\.cmd//' -e 's/\.exe//' "${CROSS_FILE}"
fi

cd "${WORK}/libass"
# --wrap-mode=nodownload: every subproject is the vendored copy above; nothing is fetched here.
MSYS_NO_PATHCONV=1 ${MESON} setup "$(to_native "${BUILD_DIR}")" \
    --cross-file="$(to_native "${CROSS_FILE}")" \
    --wrap-mode=nodownload \
    --default-library=static \
    --buildtype=release \
    --prefix=/ \
    --libdir=lib \
    --includedir=include \
    -Dfontconfig=enabled \
    -Drequire-system-font-provider=true \
    -Dlibunibreak=disabled \
    -Dtest=disabled -Dcompare=disabled -Dprofile=disabled -Dfuzz=disabled -Dcheckasm=disabled \
    -Dasm=enabled \
    -Dfribidi:default_library=shared \
    -Dfribidi:docs=false -Dfribidi:tests=false -Dfribidi:bin=false \
    -Dfreetype2:harfbuzz=disabled -Dfreetype2:png=disabled -Dfreetype2:zlib=disabled \
    -Dfreetype2:brotli=disabled -Dfreetype2:tests=disabled \
    -Dharfbuzz:tests=disabled -Dharfbuzz:cairo=disabled -Dharfbuzz:gobject=disabled -Dharfbuzz:glib=disabled \
    -Dharfbuzz:freetype=disabled -Dharfbuzz:icu=disabled -Dharfbuzz:chafa=disabled -Dharfbuzz:utilities=disabled \
    -Dharfbuzz:docs=disabled -Dharfbuzz:introspection=disabled -Dharfbuzz:subset=disabled \
    -Dharfbuzz:raster=disabled -Dharfbuzz:vector=disabled -Dharfbuzz:gpu=disabled \
    -Dfontconfig:doc=disabled -Dfontconfig:nls=disabled -Dfontconfig:tests=disabled -Dfontconfig:tools=disabled \
    -Dfontconfig:cache-build=disabled -Dfontconfig:xml-backend=expat -Dfontconfig:fontations=disabled \
    -Dfontconfig:iconv=disabled
MSYS_NO_PATHCONV=1 ${MESON} compile -C "$(to_native "${BUILD_DIR}")"
MSYS_NO_PATHCONV=1 DESTDIR="$(to_native "${PREFIX}")" ${MESON} install -C "$(to_native "${BUILD_DIR}")" --skip-subprojects= 2>/dev/null \
    || MSYS_NO_PATHCONV=1 DESTDIR="$(to_native "${PREFIX}")" ${MESON} install -C "$(to_native "${BUILD_DIR}")"

# The archives and the one shared library libhpass.so links (core/playback/src/main/cpp/CMakeLists.txt).
ls -la "${PREFIX}/lib"
"${BIN}/llvm-readelf$( [[ -f "${BIN}/llvm-readelf.exe" ]] && echo .exe)" -d "${PREFIX}/lib/libfribidi.so" | grep -E 'SONAME|NEEDED'
echo "[done] ${PREFIX}"
