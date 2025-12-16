#!/bin/bash
# Generate SHA1 hash files for FreeBSD/NetBSD base.txz downloads
# Usage: ./generate-bsd-hashes.sh <os> <version> [arch1 arch2 ...]
#
# Examples:
#   ./generate-bsd-hashes.sh freebsd 15.0 amd64 aarch64 powerpc64 powerpc64le riscv64
#   ./generate-bsd-hashes.sh netbsd 10.1 amd64 evbarm-aarch64 i386 sparc64

set -e

OS="${1:-freebsd}"
VERSION="${2:-15.0}"
shift 2 || true

# Default architectures based on OS
if [ "$OS" = "freebsd" ]; then
    ARCHS="${@:-amd64 aarch64 powerpc64 powerpc64le riscv64}"
    BASE_URL="https://download.freebsd.org/ftp/releases"
elif [ "$OS" = "netbsd" ]; then
    ARCHS="${@:-amd64 evbarm-aarch64 i386 sparc64}"
    BASE_URL="https://cdn.netbsd.org/pub/NetBSD/NetBSD-${VERSION}"
else
    echo "Unknown OS: $OS"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HASHES_DIR="$(dirname "$SCRIPT_DIR")/hashes"
TMPDIR="${TMPDIR:-/tmp}"

echo "Generating hashes for $OS $VERSION"
echo "Architectures: $ARCHS"
echo "Hashes directory: $HASHES_DIR"
echo ""

# Architecture to URL path mapping for FreeBSD
freebsd_url_path() {
    local arch=$1
    case "$arch" in
        amd64)       echo "amd64/amd64" ;;
        aarch64)     echo "arm64/aarch64" ;;
        powerpc)     echo "powerpc/powerpc" ;;
        powerpc64)   echo "powerpc/powerpc64" ;;
        powerpc64le) echo "powerpc/powerpc64le" ;;
        riscv64)     echo "riscv/riscv64" ;;
        i386)        echo "i386/i386" ;;
        *)           echo "$arch/$arch" ;;
    esac
}

for arch in $ARCHS; do
    if [ "$OS" = "freebsd" ]; then
        URL_PATH=$(freebsd_url_path "$arch")
        FILE_URL="${BASE_URL}/${URL_PATH}/${VERSION}-RELEASE/base.txz"
        LOCAL_NAME="${OS}-${VERSION}-${arch}.tar.xz"
        HASH_FILE="${HASHES_DIR}/${LOCAL_NAME}.sha1"

        echo "Fetching hash for $arch..."
        echo "URL: $FILE_URL"

        # Download to temp file
        TMPFILE="${TMPDIR}/${LOCAL_NAME}"
        if curl --retry 3 --retry-delay 3 -fSL -o "$TMPFILE" "$FILE_URL"; then
            # Calculate SHA1 and create hash file
            SHA1=$(shasum -a 1 "$TMPFILE" | cut -d' ' -f1)
            echo "${SHA1}  ${LOCAL_NAME}" > "$HASH_FILE"
            echo "Created: $HASH_FILE"
            echo "SHA1: $SHA1"
            rm -f "$TMPFILE"
        else
            echo "Failed to download $FILE_URL"
        fi
        echo ""
    elif [ "$OS" = "netbsd" ]; then
        # NetBSD has both base and comp tarballs
        FILE_URL="${BASE_URL}/${arch}/binary/sets/base.tar.xz"
        COMP_URL="${BASE_URL}/${arch}/binary/sets/comp.tar.xz"

        for type in base comp; do
            if [ "$type" = "base" ]; then
                URL="$FILE_URL"
            else
                URL="$COMP_URL"
            fi

            LOCAL_NAME="${OS}-${VERSION}-${arch}-${type}.tar.xz"
            HASH_FILE="${HASHES_DIR}/${LOCAL_NAME}.sha1"

            echo "Fetching hash for $arch ($type)..."
            echo "URL: $URL"

            TMPFILE="${TMPDIR}/${LOCAL_NAME}"
            if curl --retry 3 --retry-delay 3 -fSL -o "$TMPFILE" "$URL"; then
                SHA1=$(shasum -a 1 "$TMPFILE" | cut -d' ' -f1)
                echo "${SHA1}  ${LOCAL_NAME}" > "$HASH_FILE"
                echo "Created: $HASH_FILE"
                echo "SHA1: $SHA1"
                rm -f "$TMPFILE"
            else
                echo "Failed to download $URL"
            fi
        done
        echo ""
    fi
done

echo "Done!"
