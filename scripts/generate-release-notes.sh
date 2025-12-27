#!/bin/bash
# Generate release notes from targets.yaml
# Usage: ./generate-release-notes.sh [version]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGETS_FILE="${SCRIPT_DIR}/targets.yaml"
VERSION="${1:-}"

if [ ! -f "$TARGETS_FILE" ]; then
    echo "Error: targets.yaml not found at $TARGETS_FILE" >&2
    exit 1
fi

# Check for yq
if ! command -v yq &>/dev/null; then
    echo "Error: yq is required but not installed" >&2
    exit 1
fi

# Get default versions
GCC_VER=$(yq '.defaults.GCC_VER' "$TARGETS_FILE")
BINUTILS_VER=$(yq '.defaults.BINUTILS_VER' "$TARGETS_FILE")
GMP_VER=$(yq '.defaults.GMP_VER' "$TARGETS_FILE")
MPC_VER=$(yq '.defaults.MPC_VER' "$TARGETS_FILE")
MPFR_VER=$(yq '.defaults.MPFR_VER' "$TARGETS_FILE")
ISL_VER=$(yq '.defaults.ISL_VER' "$TARGETS_FILE")
ZSTD_VER=$(yq '.defaults.ZSTD_VER' "$TARGETS_FILE")
LINUX_VER=$(yq '.defaults.LINUX_VER' "$TARGETS_FILE")
DEFAULT_MUSL_VER=$(yq '.defaults.MUSL_VER' "$TARGETS_FILE")
DEFAULT_GLIBC_VER=$(yq '.defaults.GLIBC_VER' "$TARGETS_FILE")
DEFAULT_MINGW_VER=$(yq '.defaults.MINGW_VER' "$TARGETS_FILE")
DEFAULT_FREEBSD_VER=$(yq '.defaults.FREEBSD_VER' "$TARGETS_FILE")

# Output header
if [ -n "$VERSION" ]; then
    echo "# Release $VERSION"
    echo ""
fi

# Linux musl targets
echo "## Linux musl Targets"
echo ""
echo "| Target | GCC | Binutils | GMP | MPC | MPFR | ISL | zstd | musl | Linux Headers |"
echo "|--------|-----|----------|-----|-----|------|-----|------|------|---------------|"
yq -r ".targets[] | select(.TARGET | test(\"linux-musl\")) | [.TARGET, .MUSL_VER] | @tsv" "$TARGETS_FILE" | \
while IFS=$'\t' read -r target musl_ver; do
    musl_ver="${musl_ver:-$DEFAULT_MUSL_VER}"
    [ "$musl_ver" = "null" ] && musl_ver="$DEFAULT_MUSL_VER"
    echo "| \`$target\` | $GCC_VER | $BINUTILS_VER | $GMP_VER | $MPC_VER | $MPFR_VER | $ISL_VER | $ZSTD_VER | $musl_ver | $LINUX_VER |"
done
echo ""

# Linux glibc targets
echo "## Linux glibc Targets"
echo ""
echo "| Target | GCC | Binutils | GMP | MPC | MPFR | ISL | zstd | glibc | Linux Headers |"
echo "|--------|-----|----------|-----|-----|------|-----|------|-------|---------------|"
yq -r ".targets[] | select(.TARGET | test(\"linux-gnu\")) | [(.ID // .TARGET), .GLIBC_VER] | @tsv" "$TARGETS_FILE" | \
while IFS=$'\t' read -r id glibc_ver; do
    glibc_ver="${glibc_ver:-$DEFAULT_GLIBC_VER}"
    [ "$glibc_ver" = "null" ] && glibc_ver="$DEFAULT_GLIBC_VER"
    echo "| \`$id\` | $GCC_VER | $BINUTILS_VER | $GMP_VER | $MPC_VER | $MPFR_VER | $ISL_VER | $ZSTD_VER | $glibc_ver | $LINUX_VER |"
done
echo ""

# Windows mingw targets
echo "## Windows MinGW Targets"
echo ""
echo "| Target | GCC | Binutils | GMP | MPC | MPFR | ISL | zstd | MinGW |"
echo "|--------|-----|----------|-----|-----|------|-----|------|-------|"
yq -r ".targets[] | select(.TARGET | test(\"mingw\")) | [.TARGET, .MINGW_VER] | @tsv" "$TARGETS_FILE" | \
while IFS=$'\t' read -r target mingw_ver; do
    mingw_ver="${mingw_ver:-$DEFAULT_MINGW_VER}"
    [ "$mingw_ver" = "null" ] && mingw_ver="$DEFAULT_MINGW_VER"
    echo "| \`$target\` | $GCC_VER | $BINUTILS_VER | $GMP_VER | $MPC_VER | $MPFR_VER | $ISL_VER | $ZSTD_VER | $mingw_ver |"
done
echo ""

# FreeBSD targets
echo "## FreeBSD Targets"
echo ""
echo "| Target | GCC | Binutils | GMP | MPC | MPFR | ISL | zstd | FreeBSD |"
echo "|--------|-----|----------|-----|-----|------|-----|------|---------|"
yq -r ".targets[] | select(.TARGET | test(\"freebsd\")) | [.TARGET, .FREEBSD_VER] | @tsv" "$TARGETS_FILE" | \
while IFS=$'\t' read -r target freebsd_ver; do
    freebsd_ver="${freebsd_ver:-$DEFAULT_FREEBSD_VER}"
    [ "$freebsd_ver" = "null" ] && freebsd_ver="$DEFAULT_FREEBSD_VER"
    echo "| \`$target\` | $GCC_VER | $BINUTILS_VER | $GMP_VER | $MPC_VER | $MPFR_VER | $ISL_VER | $ZSTD_VER | $freebsd_ver |"
done
echo ""

# Host platforms
echo "## Host Platforms"
echo ""
echo "| Platform | Architecture |"
echo "|----------|--------------|"
echo "| Linux | x86_64, aarch64, armv7, loongarch64, s390x, powerpc64, powerpc64le, mips64, mips64el, riscv64 |"
echo "| macOS | x86_64, aarch64 |"
echo "| Windows | x86_64 |"
echo ""
