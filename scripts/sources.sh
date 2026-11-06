#!/bin/bash
#
# sources.sh - Download and manage source packages for cross-make
#
# Usage:
#   ./scripts/sources.sh list          - List all required sources
#   ./scripts/sources.sh cache-key     - Print cache key based on sources
#   ./scripts/sources.sh download      - Download all sources
#   ./scripts/sources.sh download -C   - Download using China mirrors
#   ./scripts/sources.sh download -S /path/to/sources - Download to specific directory
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGETS_YAML="${SCRIPT_DIR}/targets.yaml"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Get yaml default value
GetYamlDefault() {
  local key="$1"
  yq -r ".defaults.${key} // \"\"" "$TARGETS_YAML"
}

# Map target to FreeBSD arch
GetFreeBSDArch() {
  local target="$1"
  case "$target" in
  *x86_64* | *amd64*) echo "amd64" ;;
  *aarch64*) echo "aarch64" ;;
  *powerpc64le*) echo "powerpc64le" ;;
  *powerpc64*) echo "powerpc64" ;;
  *powerpc*) echo "powerpc" ;;
  *riscv64*) echo "riscv64" ;;
  esac
}

# Map target to NetBSD arch and extension
# Output: "arch|ext"
GetNetBSDArch() {
  local target="$1"
  case "$target" in
  *x86_64* | *amd64*) echo "amd64|tar.xz" ;;
  *aarch64*) echo "evbarm-aarch64|tar.xz" ;;
  *mipsel*) echo "evbmips-mipsel|tgz" ;;
  *powerpc*) echo "evbppc|tgz" ;;
  *i586* | *i686* | *i386*) echo "i386|tgz" ;;
  *sparc64*) echo "sparc64|tar.xz" ;;
  esac
}

# Get all unique source package names needed for all targets
GetAllSources() {
  # Get defaults (single yq call)
  local defaults
  defaults=$(yq -r '.defaults | to_entries | .[] | "\(.key)=\(.value)"' "$TARGETS_YAML")

  # Parse defaults into variables
  local def_gcc def_binutils def_gmp def_mpc def_mpfr def_isl def_zstd
  local def_linux def_musl def_glibc def_mingw def_freebsd def_netbsd
  while IFS='=' read -r key value; do
    case "$key" in
    GCC_VER) def_gcc="$value" ;;
    BINUTILS_VER) def_binutils="$value" ;;
    GMP_VER) def_gmp="$value" ;;
    MPC_VER) def_mpc="$value" ;;
    MPFR_VER) def_mpfr="$value" ;;
    ISL_VER) def_isl="$value" ;;
    ZSTD_VER) def_zstd="$value" ;;
    LINUX_VER) def_linux="$value" ;;
    MUSL_VER) def_musl="$value" ;;
    GLIBC_VER) def_glibc="$value" ;;
    MINGW_VER) def_mingw="$value" ;;
    FREEBSD_VER) def_freebsd="$value" ;;
    NETBSD_VER) def_netbsd="$value" ;;
    esac
  done <<<"$defaults"

  # Common sources for all targets (gcc toolchain)
  # Extensions must match hash files in hashes/ directory
  local sources=()
  sources+=("gcc-${def_gcc}.tar.xz")
  sources+=("binutils-${def_binutils}.tar.xz")
  sources+=("gmp-${def_gmp}.tar.bz2")
  sources+=("mpc-${def_mpc}.tar.gz")
  sources+=("mpfr-${def_mpfr}.tar.bz2")
  sources+=("isl-${def_isl}.tar.bz2")
  sources+=("zstd-${def_zstd}.tar.gz")
  sources+=("config.sub")
  sources+=("config.guess")

  # Get targets (single yq call, pipe-separated to handle empty fields)
  # Format: TARGET|MUSL_VER|GLIBC_VER|MINGW_VER|FREEBSD_VER|NETBSD_VER
  local targets_data
  targets_data=$(yq -r '.targets[] | [.TARGET // "", .MUSL_VER // "", .GLIBC_VER // "", .MINGW_VER // "", .FREEBSD_VER // "", .NETBSD_VER // "", .GCC_VER // ""] | join("|")' "$TARGETS_YAML")

  local musl_vers="" glibc_vers="" mingw_vers="" gcc_vers="" freebsd_files="" netbsd_files=""
  local need_linux="false"

  while IFS='|' read -r target musl_ver glibc_ver mingw_ver freebsd_ver netbsd_ver gcc_ver; do
    [ -z "$target" ] && continue

    # Musl targets
    if [ -n "$musl_ver" ]; then
      musl_vers="$musl_vers $musl_ver"
      need_linux="true"
    elif [[ "$target" == *musl* ]]; then
      musl_vers="$musl_vers $def_musl"
      need_linux="true"
    fi

    # Glibc targets
    if [ -n "$glibc_ver" ]; then
      glibc_vers="$glibc_vers $glibc_ver"
      need_linux="true"
    elif [[ "$target" == *gnu* ]] && [ -z "$musl_ver" ]; then
      glibc_vers="$glibc_vers $def_glibc"
      need_linux="true"
    fi

    # Mingw targets
    if [ -n "$mingw_ver" ]; then
      mingw_vers="$mingw_vers $mingw_ver"
    elif [[ "$target" == *mingw* ]]; then
      mingw_vers="$mingw_vers $def_mingw"
    fi

    # Per-target GCC versions
    if [ -n "$gcc_ver" ]; then
      gcc_vers="$gcc_vers $gcc_ver"
    fi

    # FreeBSD targets
    local freebsd_arch
    if [ -n "$freebsd_ver" ]; then
      freebsd_arch=$(GetFreeBSDArch "$target")
      [ -n "$freebsd_arch" ] && freebsd_files="$freebsd_files freebsd-${freebsd_ver}-${freebsd_arch}.tar.xz"
    elif [[ "$target" == *freebsd* ]]; then
      freebsd_arch=$(GetFreeBSDArch "$target")
      [ -n "$freebsd_arch" ] && freebsd_files="$freebsd_files freebsd-${def_freebsd}-${freebsd_arch}.tar.xz"
    fi

    # NetBSD targets
    local netbsd_info netbsd_arch netbsd_ext
    if [ -n "$netbsd_ver" ]; then
      netbsd_info=$(GetNetBSDArch "$target")
      if [ -n "$netbsd_info" ]; then
        netbsd_arch="${netbsd_info%%|*}"
        netbsd_ext="${netbsd_info##*|}"
        netbsd_files="$netbsd_files netbsd-${netbsd_ver}-${netbsd_arch}-base.${netbsd_ext}"
        netbsd_files="$netbsd_files netbsd-${netbsd_ver}-${netbsd_arch}-comp.${netbsd_ext}"
      fi
    elif [[ "$target" == *netbsd* ]]; then
      netbsd_info=$(GetNetBSDArch "$target")
      if [ -n "$netbsd_info" ]; then
        netbsd_arch="${netbsd_info%%|*}"
        netbsd_ext="${netbsd_info##*|}"
        netbsd_files="$netbsd_files netbsd-${def_netbsd}-${netbsd_arch}-base.${netbsd_ext}"
        netbsd_files="$netbsd_files netbsd-${def_netbsd}-${netbsd_arch}-comp.${netbsd_ext}"
      fi
    fi
  done <<<"$targets_data"

  # Add linux header if needed
  [ "$need_linux" = "true" ] && sources+=("linux-${def_linux}.tar.xz")

  # Add unique versions
  for ver in $(echo "$musl_vers" | tr ' ' '\n' | sort -u); do
    [ -n "$ver" ] && sources+=("musl-${ver}.tar.gz")
  done
  for ver in $(echo "$glibc_vers" | tr ' ' '\n' | sort -u); do
    [ -n "$ver" ] && sources+=("glibc-${ver}.tar.gz")
  done
  for ver in $(echo "$mingw_vers" | tr ' ' '\n' | sort -u); do
    [ -n "$ver" ] && sources+=("mingw-w64-${ver}.tar.bz2")
  done
  for ver in $(echo "$gcc_vers" | tr ' ' '\n' | sort -u); do
    [ -n "$ver" ] && sources+=("gcc-${ver}.tar.xz")
  done
  for file in $(echo "$freebsd_files" | tr ' ' '\n' | sort -u); do
    [ -n "$file" ] && sources+=("$file")
  done
  for file in $(echo "$netbsd_files" | tr ' ' '\n' | sort -u); do
    [ -n "$file" ] && sources+=("$file")
  done

  # Output unique sources sorted
  printf '%s\n' "${sources[@]}" | sort -u
}

# Generate a hash key based on all sources for caching
GetSourcesCacheKey() {
  GetAllSources | sha256sum | cut -d' ' -f1 | head -c 16
}

# List sources required by the clang (LLVM) toolchain build.
# Mirrors litecross/Makefile.clang: llvm + musl sysroots + linux headers +
# statically linked host deps (zlib/zstd/libxml2).
GetClangSources() {
  local defaults
  defaults=$(yq -r '.defaults | to_entries | .[] | "\(.key)=\(.value)"' "$TARGETS_YAML")
  local def_llvm def_musl def_linux def_zstd def_zlib def_libxml2 def_mingw
  while IFS='=' read -r key value; do
    case "$key" in
    LLVM_VER) def_llvm="$value" ;;
    MUSL_VER) def_musl="$value" ;;
    LINUX_VER) def_linux="$value" ;;
    MINGW_VER) def_mingw="$value" ;;
    ZSTD_VER) def_zstd="$value" ;;
    ZLIB_VER) def_zlib="$value" ;;
    LIBXML2_VER) def_libxml2="$value" ;;
    esac
  done <<<"$defaults"

  local sources=(
    "llvm-project-${def_llvm}.src.tar.xz"
    "musl-${def_musl}.tar.gz"
    "linux-${def_linux}.tar.xz"
    "zstd-${def_zstd}.tar.gz"
    "zlib-${def_zlib}.tar.gz"
    "libxml2-${def_libxml2}.tar.xz"
    "mingw-w64-${def_mingw}.tar.bz2"
    "config.sub"
    "config.guess"
  )
  printf '%s\n' "${sources[@]}" | sort -u
}

# Resolve a download scope to a source list: empty = all, "clang" = the LLVM
# toolchain set, anything else = a single gcc-mode target (ID or TARGET).
GetScopedSources() {
  local scope="${1:-}"
  if [ "$scope" = "clang" ]; then
    GetClangSources
  elif [ -n "$scope" ]; then
    GetTargetSources "$scope"
  else
    GetAllSources
  fi
}

# List sources required by a single target (by ID or TARGET).
# Mirrors the libc selection logic of scripts/build.sh WriteConfig.
GetTargetSources() {
  local id_or_target="$1"

  # Defaults (single yq call)
  local defaults
  defaults=$(yq -r '.defaults | to_entries | .[] | "\(.key)=\(.value)"' "$TARGETS_YAML")
  local def_gcc def_binutils def_gmp def_mpc def_mpfr def_isl def_zstd
  local def_linux def_musl def_glibc def_mingw def_freebsd def_netbsd
  while IFS='=' read -r key value; do
    case "$key" in
    GCC_VER) def_gcc="$value" ;;
    BINUTILS_VER) def_binutils="$value" ;;
    GMP_VER) def_gmp="$value" ;;
    MPC_VER) def_mpc="$value" ;;
    MPFR_VER) def_mpfr="$value" ;;
    ISL_VER) def_isl="$value" ;;
    ZSTD_VER) def_zstd="$value" ;;
    LINUX_VER) def_linux="$value" ;;
    MUSL_VER) def_musl="$value" ;;
    GLIBC_VER) def_glibc="$value" ;;
    MINGW_VER) def_mingw="$value" ;;
    FREEBSD_VER) def_freebsd="$value" ;;
    NETBSD_VER) def_netbsd="$value" ;;
    esac
  done <<<"$defaults"

  # Per-target versions: MUSL|GLIBC|MINGW|FREEBSD|NETBSD|GCC (first matching row)
  local tcfg
  tcfg=$(yq -r "[.targets[] | select(.ID == \"${id_or_target}\" or .TARGET == \"${id_or_target}\")] | .[0] | [.MUSL_VER // \"\", .GLIBC_VER // \"\", .MINGW_VER // \"\", .FREEBSD_VER // \"\", .NETBSD_VER // \"\", .GCC_VER // \"\"] | join(\"|\")" "$TARGETS_YAML")
  local t_musl t_glibc t_mingw t_freebsd t_netbsd t_gcc
  IFS='|' read -r t_musl t_glibc t_mingw t_freebsd t_netbsd t_gcc <<<"$tcfg"

  local target
  target=$(yq -r ".targets[] | select(.ID == \"${id_or_target}\") | .TARGET // \"\"" "$TARGETS_YAML")
  [ -z "$target" ] && target="$id_or_target"

  local sources=()
  sources+=("gcc-${t_gcc:-$def_gcc}.tar.xz")
  sources+=("binutils-${def_binutils}.tar.xz")
  sources+=("gmp-${def_gmp}.tar.bz2")
  sources+=("mpc-${def_mpc}.tar.gz")
  sources+=("mpfr-${def_mpfr}.tar.bz2")
  sources+=("isl-${def_isl}.tar.bz2")
  sources+=("zstd-${def_zstd}.tar.gz")
  sources+=("config.sub")
  sources+=("config.guess")

  if [ -n "$t_mingw" ] || [[ "$target" == *mingw* ]]; then
    sources+=("mingw-w64-${t_mingw:-$def_mingw}.tar.bz2")
  elif [ -n "$t_freebsd" ] || [[ "$target" == *freebsd* ]]; then
    local fa
    fa=$(GetFreeBSDArch "$target")
    [ -n "$fa" ] && sources+=("freebsd-${t_freebsd:-$def_freebsd}-${fa}.tar.xz")
  elif [ -n "$t_netbsd" ] || [[ "$target" == *netbsd* ]]; then
    local na nx
    local ni
    ni=$(GetNetBSDArch "$target")
    if [ -n "$ni" ]; then
      na="${ni%%|*}"
      nx="${ni##*|}"
      sources+=("netbsd-${t_netbsd:-$def_netbsd}-${na}-base.${nx}")
      sources+=("netbsd-${t_netbsd:-$def_netbsd}-${na}-comp.${nx}")
    fi
  elif [ -n "$t_glibc" ] || { [[ "$target" == *gnu* || "$target" == *glibc* ]] && [ -z "$t_musl" ]; }; then
    sources+=("glibc-${t_glibc:-$def_glibc}.tar.gz")
    sources+=("linux-${def_linux}.tar.xz")
  else
    sources+=("musl-${t_musl:-$def_musl}.tar.gz")
    sources+=("linux-${def_linux}.tar.xz")
  fi

  printf '%s\n' "${sources[@]}" | sort -u
}

# Download all sources
DownloadSources() {
  local sources_dir="${SOURCES_DIR:-sources}"
  local china_flag=""

  if [ -n "$USE_CHINA_MIRROR" ]; then
    china_flag="CHINA=1"
  fi

  # Ensure sources directory exists
  mkdir -p "$sources_dir"

  # Make sources_dir absolute
  sources_dir="$(cd "$sources_dir" && pwd)"

  echo "Downloading all sources to: $sources_dir"
  echo ""
  echo "Sources to download:"
  local all_sources
  if [ -n "$FILTER_TARGET" ]; then
    echo "(filtered for target: $FILTER_TARGET)"
    all_sources=$(GetScopedSources "$FILTER_TARGET")
  else
    all_sources=$(GetAllSources)
  fi
  echo "$all_sources" | while read -r src; do
    if [ -f "${sources_dir}/${src}" ]; then
      echo "  [cached] $src"
    else
      echo "  [new]    $src"
    fi
  done
  echo ""

  # Build make targets for downloading
  local download_targets=""
  for src in $all_sources; do
    download_targets="$download_targets ${sources_dir}/${src}"
  done

  echo "Starting download..."
  cd "$PROJECT_DIR"

  # Detect make command
  local MAKE="make"
  if [ "$(uname)" == "Darwin" ]; then
    MAKE="gmake"
  fi

  # Use parallel downloads (default: 4 jobs)
  local jobs="${JOBS:-4}"
  $MAKE -j"$jobs" SOURCES="$sources_dir" $china_flag $download_targets

  echo ""
  echo "Download complete!"
  echo "Total sources: $(echo "$all_sources" | wc -l | tr -d ' ')"
  echo "Cache key: $(GetSourcesCacheKey)"
}

# Print usage
Usage() {
  echo "Usage: $0 <command> [options]"
  echo ""
  echo "Commands:"
  echo "  list        List all required source packages"
  echo "  cache-key   Print cache key for GitHub Actions caching"
  echo "  download    Download all sources"
  echo ""
  echo "Options for download:"
  echo "  -C          Use China mirrors"
  echo "  -S <dir>    Download to specified directory (default: sources)"
  echo "  -T <target> Only download sources needed by this target (ID or TARGET)"
  echo "  -T clang    Only download sources needed by the LLVM toolchain build"
  echo ""
  echo "Examples:"
  echo "  $0 list"
  echo "  $0 cache-key"
  echo "  $0 download"
  echo "  $0 download -C -S /path/to/sources"
  echo "  $0 download -T aarch64-w64-mingw32 -S sources"
  echo "  $0 download -T clang -S sources"
}

# Main
case "${1:-}" in
list)
  shift
  while getopts "T:" arg; do
    case $arg in
    T) FILTER_TARGET="$OPTARG" ;;
    *)
      Usage
      exit 1
      ;;
    esac
  done
  if [ -n "$FILTER_TARGET" ]; then
    GetScopedSources "$FILTER_TARGET"
  else
    GetAllSources
  fi
  ;;
cache-key)
  shift
  while getopts "T:" arg; do
    case $arg in
    T) FILTER_TARGET="$OPTARG" ;;
    *)
      Usage
      exit 1
      ;;
    esac
  done
  if [ "$FILTER_TARGET" = "clang" ]; then
    # Hash only the clang toolchain source set; the gcc world stays on the
    # shared full-list key so orchestrator cache sharing is unaffected
    GetClangSources | sha256sum | cut -d' ' -f1 | head -c 16
  else
    GetSourcesCacheKey
  fi
  ;;
download)
  shift
  while getopts "CT:S:" arg; do
    case $arg in
    C) USE_CHINA_MIRROR="true" ;;
    S) SOURCES_DIR="$OPTARG" ;;
    T) FILTER_TARGET="$OPTARG" ;;
    *)
      Usage
      exit 1
      ;;
    esac
  done
  DownloadSources
  ;;
-h | --help | help)
  Usage
  ;;
*)
  Usage
  exit 1
  ;;
esac
