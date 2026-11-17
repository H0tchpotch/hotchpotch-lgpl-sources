#!/usr/bin/env bash
# ARCHITECTURE.md §8.1: FFmpeg 6.0 arm64-v8a as shared libraries (libavutil,
# libavcodec, libavformat, libswresample .so). WHY shared: §8.3.1 LGPL condition 1
# forbids statically merging FFmpeg into our own code; libhpffmpeg.so (our JNI)
# links these dynamically so a user can swap in a rebuilt FFmpeg (G19).
# Music audio (MUSIC_PLAYER.md §1 '지원 포맷'): containers Media3 cannot open (TAK,
# DSF/DFF, AIFF, APE, MPC, TTA, WavPack, WMA/ASF) for the synthetic WAV path, and
# decoders the platform may lack for tracks Media3 does extract (ALAC, MP1/MP2) for
# FfmpegAudioRenderer.
# Video (VIDEO_PLAYER.md §15.1 VLC급 범위, §15.4; 2026-11-17 사용자 "라이선스가 허용하는
# 한 최대한 많은 확장자, 레거시 포함"): every native LGPL decoder, demuxer, parser and
# bitstream filter FFmpeg has, minus the exclusions below; libavfilter with only the
# deinterlacers (bwdif/yadif/w3fdif, all LGPL) and libswscale for pixel formats the
# window cannot take as-is. No external library is linked (no --enable-libxxx); zlib
# is the NDK system libz (Matroska zlib tracks, PNG), size 0 in the APK.
# Excluded decoders:
#   - dca (DTS), truehd/mlp, eac3: patents, platform MediaCodec only (VIDEO_PLAYER.md
#     P2). HP_FFMPEG_VERIFY_DTS_TRUEHD=1 makes the G18 verification build with
#     dca/truehd/mlp — never ship it; the variant is written to lib/hp_ffmpeg_variant.txt.
#   - hevc, vp9, av1: the devices decode them in hardware (§5); AV1 software is dav1d
#     outside FFmpeg (§15.10); software HEVC also carries patent weight.
#   - aac, aac_fixed, aac_latm, amrnb, amrwb, atrac9 (VIDEO_PLAYER.md §15.47 / G19,
#     2026-11-18 사용자): pool or holder patents still live (AAC: no free tier), and every
#     Android device must decode AAC and AMR itself — the platform decoder covers them
#     under the device maker's licence. ATRAC9 has no use here.
# Encoders, muxers, devices, hwaccels, network protocols and programs are disabled.
# The JNI .so files are built by Gradle/CMake.
#
# The build installs into a staging prefix (third_party/ffmpeg/android-libs-staging) and
# replaces android-libs/arm64-v8a only after every check passed, so the libraries the
# CMake builds link against are never half-built (the music and video work share them).
# In-tree only: out-of-tree builds break on the NDK's Windows make (SETUP.md §3.6).
set -euo pipefail

VERIFY_DTS_TRUEHD="${HP_FFMPEG_VERIFY_DTS_TRUEHD:-0}"
PATENT_EXCLUDED="aac,aac_fixed,aac_latm,amrnb,amrwb,atrac9"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FFMPEG_SRC="${REPO_ROOT}/third_party/ffmpeg"
PREFIX="${FFMPEG_SRC}/android-libs/arm64-v8a"
if [[ "${VERIFY_DTS_TRUEHD}" == "1" ]]; then
    VARIANT="verify-dts-truehd"
else
    VARIANT="release"
fi
BUILD_DIR="${FFMPEG_SRC}"
STAGING="${FFMPEG_SRC}/android-libs-staging/arm64-v8a"

if [[ ! -f "${FFMPEG_SRC}/configure" ]]; then
    echo "Missing ${FFMPEG_SRC}/configure. Run ./scripts/vendor_c_libs.sh first." >&2
    exit 1
fi

if [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
    NDK_PATH="${ANDROID_NDK_HOME}"
elif [[ -n "${ANDROID_NDK_ROOT:-}" ]]; then
    NDK_PATH="${ANDROID_NDK_ROOT}"
else
    NDK_PATH="$(cygpath -u "${LOCALAPPDATA}")/Android/Sdk/ndk/30.0.16248370"
fi
TOOLCHAIN="${NDK_PATH}/toolchains/llvm/prebuilt/windows-x86_64"
if [[ ! -d "${TOOLCHAIN}" ]]; then
    TOOLCHAIN="${NDK_PATH}/toolchains/llvm/prebuilt/linux-x86_64"
fi
if [[ ! -d "${TOOLCHAIN}" ]]; then
    echo "NDK toolchain not found under ${NDK_PATH}" >&2
    exit 1
fi
PREFIX_BIN="${TOOLCHAIN}/bin"
API=24
CC="${PREFIX_BIN}/aarch64-linux-android${API}-clang"
CXX="${PREFIX_BIN}/aarch64-linux-android${API}-clang++"
if [[ ! -x "${CC}" ]]; then
    echo "Missing NDK clang: ${CC}" >&2
    exit 1
fi

# NDK ships GNU make on Windows; Git Bash alone has no make on this machine.
export PATH="${NDK_PATH}/prebuilt/windows-x86_64/bin:${PREFIX_BIN}:${PATH}"
JOBS="$(nproc 2>/dev/null || echo 4)"

if [[ "${1:-}" == "--clean" ]]; then
    if [[ -f "${FFMPEG_SRC}/ffbuild/config.mak" ]]; then
        (cd "${FFMPEG_SRC}" && make distclean) || true
    fi
fi
rm -rf "${STAGING}"
mkdir -p "${STAGING}"
cd "${BUILD_DIR}"

CONFIGURE_OPTIONS=(
    --prefix="${STAGING}"
    --target-os=android
    --arch=aarch64
    --cpu=armv8-a
    --enable-cross-compile
    --cc="${CC}"
    --cxx="${CXX}"
    --ar="${PREFIX_BIN}/llvm-ar"
    --nm="${PREFIX_BIN}/llvm-nm"
    --ranlib="${PREFIX_BIN}/llvm-ranlib"
    --strip="${PREFIX_BIN}/llvm-strip"
    --sysroot="${TOOLCHAIN}/sysroot"
    --disable-static
    --enable-shared
    --disable-stripping
    --enable-pic
    --disable-doc
    --disable-programs
    --disable-gpl
    --disable-nonfree
    --disable-version3
    --enable-avcodec
    --enable-avformat
    --enable-avutil
    --enable-swresample
    --enable-swscale
    --enable-avfilter
    --disable-avdevice
    --disable-postproc
    --disable-network
    --disable-encoders
    --disable-muxers
    --disable-devices
    --disable-hwaccels
    --disable-protocols
    --enable-protocol=file
    --disable-filters
    --enable-filter=buffer,buffersink,bwdif,yadif,w3fdif
    --disable-autodetect
    --disable-iconv
    --enable-zlib
    --disable-bzlib
    --disable-lzma
    --disable-symver
    --disable-v4l2-m2m
    --disable-vulkan
    --extra-cflags="-O3 -fPIC"
    --extra-ldflags="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"
)
if [[ "${VERIFY_DTS_TRUEHD}" == "1" ]]; then
    echo "[G18] verification build: DTS (dca) and TrueHD/MLP decoders included — do not ship"
    CONFIGURE_OPTIONS+=(--disable-decoder=eac3,hevc,vp9,av1,${PATENT_EXCLUDED})
else
    CONFIGURE_OPTIONS+=(--disable-decoder=dca,truehd,mlp,eac3,hevc,vp9,av1,${PATENT_EXCLUDED})
fi

"${FFMPEG_SRC}/configure" "${CONFIGURE_OPTIONS[@]}"

# WHY: with every decoder enabled, libavcodec's link line (one argument per object, ~1,500
# objects) exceeds the 32,767-character CreateProcess limit of Windows and clang sees a
# truncated object name ("libavcodec/h"). The shared-library link reads its objects from
# a response file instead (GNU make 4.3 $(file), clang @file). Idempotent; library.mak
# is vendored source and comes back unpatched when vendor_c_libs.sh re-extracts it.
LIBRARY_MAK="${FFMPEG_SRC}/ffbuild/library.mak"
if ! grep -qF '@$$@.objs' "${LIBRARY_MAK}"; then
    sed -i 's|^\t\$\$(LD) \$(SHFLAGS) \$(LDFLAGS) \$(LDSOFLAGS) \$\$(LD_O) \$\$(filter %\.o,\$\$^) \$(FFEXTRALIBS)$|\t$$(file >$$@.objs,$$(filter %.o,$$^))\n\t$$(LD) $(SHFLAGS) $(LDFLAGS) $(LDSOFLAGS) $$(LD_O) @$$@.objs $(FFEXTRALIBS)|' "${LIBRARY_MAK}"
    if ! grep -qF '@$$@.objs' "${LIBRARY_MAK}"; then
        echo "Could not patch ${LIBRARY_MAK} for a response-file link" >&2
        exit 1
    fi
fi
make -j"${JOBS}"
make install

LIB_DIR="${STAGING}/lib"
NM="${PREFIX_BIN}/llvm-nm"
READELF="${PREFIX_BIN}/llvm-readelf"
FFMPEG_SOS=(libavutil.so libswresample.so libswscale.so libavcodec.so libavformat.so libavfilter.so)

echo "[verify] Shared libraries, unversioned SONAME/NEEDED, 16KB LOAD alignment"
for so in "${FFMPEG_SOS[@]}"; do
    if [[ ! -f "${LIB_DIR}/${so}" ]]; then
        echo "Missing ${LIB_DIR}/${so}" >&2
        exit 1
    fi
    # WHY: the APK only carries lib*.so files; a versioned SONAME/NEEDED
    # (libavcodec.so.60) would not resolve at runtime on the device.
    if "${READELF}" -d "${LIB_DIR}/${so}" | grep -E "(SONAME|NEEDED).*\.so\.[0-9]" >/dev/null; then
        echo "Versioned SONAME/NEEDED in ${so}" >&2
        "${READELF}" -d "${LIB_DIR}/${so}" | grep -E "SONAME|NEEDED" >&2
        exit 1
    fi
    if "${READELF}" -l -W "${LIB_DIR}/${so}" | awk '$1 == "LOAD" { print $NF }' | grep -v -E "^0x(4000|8000|10000)$" >/dev/null; then
        echo "LOAD segment not 16KB aligned in ${so}" >&2
        exit 1
    fi
done

echo "[verify] Exported FFmpeg API symbols"
for symbol in avformat_open_input av_read_frame avformat_find_stream_info \
              avcodec_find_decoder avcodec_send_packet avcodec_receive_frame avcodec_open2; do
    if ! "${NM}" -D --defined-only "${LIB_DIR}/libavformat.so" "${LIB_DIR}/libavcodec.so" 2>/dev/null \
        | grep -E " T ${symbol}(@@?[A-Z0-9_]+)?$" >/dev/null; then
        echo "Missing exported FFmpeg symbol: ${symbol}" >&2
        exit 1
    fi
done

# Public API symbols carry the libav* version-script tag (avformat_open_input@@LIBAVFORMAT_60).
# Decoders/demuxers are internal (hidden) symbols; --disable-stripping keeps
# them in the symbol table so the enabled set can be checked.
check_internal() {
    local lib="$1" symbol="$2" label="$3"
    if ! "${NM}" "${LIB_DIR}/${lib}" | grep -E " [dDrR] ${symbol}$" >/dev/null; then
        echo "Missing ${label} (${symbol} in ${lib})" >&2
        exit 1
    fi
}
check_internal libavcodec.so ff_tak_decoder "TAK decoder"
check_internal libavformat.so ff_tak_demuxer "TAK demuxer"
check_internal libavformat.so ff_dsf_demuxer "DSF demuxer"
check_internal libavformat.so ff_iff_demuxer "IFF/DFF demuxer"
check_internal libavcodec.so ff_dsd_lsbf_decoder "DSD LSBF decoder"
check_internal libavcodec.so ff_dsd_msbf_decoder "DSD MSBF decoder"
check_internal libavcodec.so ff_dst_decoder "DST decoder"
for codec in pcm_s16be pcm_s24be ape mpc7 mpc8 tta wavpack wmav2 wmapro wmalossless alac mp1float mp2float; do
    check_internal libavcodec.so "ff_${codec}_decoder" "${codec} decoder"
done
for demuxer in aiff ape mpc mpc8 tta wv asf mov mp3 matroska; do
    check_internal libavformat.so "ff_${demuxer}_demuxer" "${demuxer} demuxer"
done
# VIDEO_PLAYER.md §15.4: representative video/audio decoders and the §15.5 container demuxers.
for codec in h264 mpeg1video mpeg2video mpeg4 msmpeg4v1 msmpeg4v2 msmpeg4v3 wmv1 wmv2 wmv3 vc1 h263 \
             mjpeg dvvideo cinepak indeo3 indeo5 huffyuv rv40 theora vp8 prores \
             ac3 mp3float vorbis opus cook wmapro png; do
    check_internal libavcodec.so "ff_${codec}_decoder" "${codec} decoder"
done
for demuxer in avi asf rm ogg mpegps mpegts mxf flv nut; do
    check_internal libavformat.so "ff_${demuxer}_demuxer" "${demuxer} demuxer"
done
# §15.1: decoders the hardware owns stay out of FFmpeg.
for codec in hevc vp9 av1 ${PATENT_EXCLUDED//,/ }; do
    if "${NM}" "${LIB_DIR}/libavcodec.so" | grep -E " [dDrR] ff_${codec}_decoder$" >/dev/null; then
        echo "ff_${codec}_decoder must not be built (VIDEO_PLAYER.md §15.1 / §15.47)" >&2
        exit 1
    fi
done
# §15.4: no encoder or muxer reaches the APK (wrapped_avframe is libavcodec's internal pass-through, always built).
if "${NM}" "${LIB_DIR}/libavcodec.so" | grep -E " [dDrR] ff_[a-z0-9_]+_encoder$" | grep -v ff_wrapped_avframe_encoder >/dev/null; then
    echo "an encoder was built" >&2
    exit 1
fi
if "${NM}" "${LIB_DIR}/libavformat.so" | grep -E " [dDrR] ff_[a-z0-9_]+_muxer$" >/dev/null; then
    echo "a muxer was built" >&2
    exit 1
fi
for filter in ff_vf_bwdif ff_vf_yadif ff_vf_w3fdif ff_vsrc_buffer ff_vsink_buffer; do
    check_internal libavfilter.so "${filter}" "${filter} filter"
done
if ! "${NM}" -D --defined-only "${LIB_DIR}/libswscale.so" | grep -E " T sws_scale(@@?[A-Z0-9_]+)?$" >/dev/null; then
    echo "Missing exported symbol sws_scale in libswscale.so" >&2
    exit 1
fi
# P2: the shipped build never carries these; the G18 verification build must.
for codec in dca truehd mlp; do
    if "${NM}" "${LIB_DIR}/libavcodec.so" | grep -E " [dDrR] ff_${codec}_decoder$" >/dev/null; then
        if [[ "${VERIFY_DTS_TRUEHD}" != "1" ]]; then
            echo "ff_${codec}_decoder must not be built (VIDEO_PLAYER.md P2)" >&2
            exit 1
        fi
    elif [[ "${VERIFY_DTS_TRUEHD}" == "1" ]]; then
        echo "ff_${codec}_decoder missing from the G18 verification build" >&2
        exit 1
    fi
done
if "${NM}" "${LIB_DIR}/libavcodec.so" | grep -E " [dDrR] ff_eac3_decoder$" >/dev/null; then
    echo "ff_eac3_decoder must not be built (VIDEO_PLAYER.md P2)" >&2
    exit 1
fi
echo "${VARIANT}" > "${LIB_DIR}/hp_ffmpeg_variant.txt"

if compgen -G "${LIB_DIR}/*.a" >/dev/null; then
    echo "Stale static libs in ${LIB_DIR}; rerun with --clean" >&2
    exit 1
fi

echo "[count] decoders=$("${NM}" "${LIB_DIR}/libavcodec.so" | grep -cE ' [dDrR] ff_[a-z0-9_]+_decoder$')" \
     "demuxers=$("${NM}" "${LIB_DIR}/libavformat.so" | grep -cE ' [dDrR] ff_[a-z0-9_]+_demuxer$')"

# Every check passed: replace the libraries the CMake builds link against in one step.
rm -rf "${PREFIX}.old"
if [[ -d "${PREFIX}" ]]; then
    mv "${PREFIX}" "${PREFIX}.old"
fi
mkdir -p "$(dirname "${PREFIX}")"
cp -r "${STAGING}" "${PREFIX}"
rm -rf "${PREFIX}.old"

echo "[done] FFmpeg arm64 shared libs (${VARIANT}): ${PREFIX}/lib"
ls -l "${PREFIX}/lib"/*.so
