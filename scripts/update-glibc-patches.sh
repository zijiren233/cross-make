#!/bin/bash
# Automatic glibc patch extraction script
# Extracts all fixes from upstream release branches and Debian

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PATCHES_DIR="$PROJECT_DIR/patches"
TMP_DIR="/tmp/glibc-patches-$$"

UPSTREAM_REPO="https://sourceware.org/git/glibc.git"
DEBIAN_REPO="https://salsa.debian.org/glibc-team/glibc.git"

GLIBC_VERSIONS="2.27 2.28 2.29 2.30 2.31 2.32 2.33 2.34 2.35 2.36 2.37 2.38 2.39 2.40 2.41 2.42"

cleanup() {
    if [ -d "$TMP_DIR" ]; then
        echo "[INFO] Cleaning up temporary files..."
        rm -rf "$TMP_DIR"
    fi
}

trap cleanup EXIT

usage() {
    cat <<EOF
Usage: $0 [versions...]

Examples:
  $0              # Update all versions
  $0 2.31 2.34    # Update only 2.31 and 2.34

EOF
}

clone_repos() {
    mkdir -p "$TMP_DIR"

    echo "[INFO] Cloning upstream glibc repository..."
    git clone --quiet "$UPSTREAM_REPO" "$TMP_DIR/glibc-upstream" || {
        echo "[ERROR] Failed to clone upstream repository"
        return 1
    }

    echo "[INFO] Cloning Debian glibc repository..."
    git clone --quiet "$DEBIAN_REPO" "$TMP_DIR/debian-glibc" || {
        echo "[ERROR] Failed to clone Debian repository"
        return 1
    }

    echo "[SUCCESS] Repository cloning completed"
}

extract_upstream_patches() {
    local version="$1"
    local target_dir="$PATCHES_DIR/glibc-$version"

    echo "[INFO] Extracting upstream patches for glibc-$version..."

    cd "$TMP_DIR/glibc-upstream"
    git checkout -q "release/$version/master" 2>/dev/null || {
        echo "[WARNING] Branch release/$version/master not found"
        return 1
    }

    # Generate merged patch from glibc-X.Y tag to HEAD on release branch
    local commit_count=$(git rev-list --count "glibc-$version..HEAD" 2>/dev/null)

    if [ "$commit_count" -gt 0 ]; then
        git diff "glibc-$version..HEAD" > "$target_dir/git-updates.patch"
        echo "[SUCCESS] glibc-$version: Generated merged patch with $commit_count commits"
    else
        echo "[INFO] glibc-$version: No updates found"
    fi

    return 0
}

extract_debian_patches() {
    local version="$1"
    local target_dir="$PATCHES_DIR/glibc-$version"

    echo "[INFO] Extracting Debian patches for glibc-$version..."

    cd "$TMP_DIR/debian-glibc"
    git checkout -q "glibc-$version" 2>/dev/null || {
        echo "[WARNING] Branch glibc-$version not found"
        return 1
    }

    local count=0

    # Copy essential Debian patches with original names
    if [ -d "debian/patches/any" ]; then
        for patch in debian/patches/any/submitted-*.patch debian/patches/any/git-*.patch; do
            if [ -f "$patch" ]; then
                local filename=$(basename "$patch")
                # Skip submitted-stt-gnu-ifunc-detection.patch
                if [[ "$filename" == "submitted-stt-gnu-ifunc-detection.patch" ]]; then
                    continue
                fi
                cp "$patch" "$target_dir/debian-$filename"
                count=$((count + 1))
            fi
        done
    fi

    echo "[SUCCESS] glibc-$version: Extracted $count Debian patches"
    return 0
}

process_version() {
    local version="$1"
    local target_dir="$PATCHES_DIR/glibc-$version"

    echo "========================================"
    echo "Processing glibc-$version"
    echo "========================================"

    mkdir -p "$target_dir"

    extract_upstream_patches "$version" || true
    extract_debian_patches "$version" || true

    local patch_count=$(find "$target_dir" -name "*.patch" 2>/dev/null | wc -l | tr -d ' ')

    # Show file sizes for git-updates.patch
    if [ -f "$target_dir/git-updates.patch" ]; then
        local size=$(du -h "$target_dir/git-updates.patch" | awk '{print $1}')
        echo "[INFO] git-updates.patch size: $size"
    fi

    echo "[INFO] glibc-$version: Total $patch_count patch files"
    echo ""
}

main() {
    VERSIONS=""

    while [ $# -gt 0 ]; do
        case "$1" in
        -h | --help)
            usage
            exit 0
            ;;
        -*)
            echo "[ERROR] Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            VERSIONS="$VERSIONS $1"
            shift
            ;;
        esac
    done

    [ -z "$VERSIONS" ] && VERSIONS="$GLIBC_VERSIONS"

    echo "========================================"
    echo "glibc Patch Update Script"
    echo "========================================"
    echo ""
    echo "[INFO] Project directory: $PROJECT_DIR"
    echo "[INFO] Patches directory: $PATCHES_DIR"
    echo "[INFO] Target versions: $VERSIONS"
    echo ""

    clone_repos || exit 1

    for version in $VERSIONS; do
        process_version "$version"
    done

    echo "========================================"
    echo "Patch Update Complete"
    echo "========================================"
    echo ""

    local total_patches=0

    echo "Version Statistics:"
    echo "----------------------------------------"
    for version in $VERSIONS; do
        local dir="$PATCHES_DIR/glibc-$version"
        if [ -d "$dir" ]; then
            local count=$(find "$dir" -name "*.patch" 2>/dev/null | wc -l | tr -d ' ')
            local size=""
            if [ -f "$dir/git-updates.patch" ]; then
                size=$(du -h "$dir/git-updates.patch" | awk '{print $1}')
            fi
            printf "glibc-%-5s  Files: %-4s  Size: %-8s\n" "$version" "$count" "$size"
            total_patches=$((total_patches + count))
        fi
    done
    echo "----------------------------------------"
    echo "Total patch files: $total_patches"
    echo ""

    echo "[SUCCESS] All patches updated!"
    echo "[INFO] Patches location: $PATCHES_DIR/glibc-*/"
}

main "$@"
