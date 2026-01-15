#!/bin/bash
# Extract CentOS 7 glibc-2.17 patches and create a single merged patch
# CentOS uses a custom glibc-2.17-c758a686.tar.gz (includes ports directory)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PATCHES_DIR="$PROJECT_DIR/patches/glibc-2.17"
TMP_DIR="/tmp/centos7-glibc-$$"

CENTOS_GLIBC_REPO="https://gitlab.com/CentOS/Archives/git.centos.org/rpms/glibc.git"
CENTOS_SRPM_URL="https://vault.centos.org/7.9.2009/updates/Source/SPackages/glibc-2.17-326.el7_9.src.rpm"
BRANCH="c7"
OUTPUT_FILE="$PATCHES_DIR/centos7-all.patch"

cleanup() {
    [ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "=== CentOS 7 glibc-2.17 Patch Generator ==="

mkdir -p "$TMP_DIR"

# Download SRPM to get CentOS's custom source tarball
echo "[1/5] Downloading CentOS SRPM..."
curl -sL "$CENTOS_SRPM_URL" -o "$TMP_DIR/glibc.src.rpm"

# Extract SRPM
echo "[2/5] Extracting SRPM..."
cd "$TMP_DIR"
rpm2cpio glibc.src.rpm | cpio -idm 2>/dev/null

# Clone CentOS repo for latest patches
echo "[3/5] Cloning CentOS glibc repository for patches..."
git clone --quiet --depth 1 -b "$BRANCH" "$CENTOS_GLIBC_REPO" "$TMP_DIR/centos"

# Copy latest patches from git (they may be newer than SRPM)
cp "$TMP_DIR/centos/SOURCES/"*.patch "$TMP_DIR/" 2>/dev/null || true
cp "$TMP_DIR/centos/SPECS/glibc.spec" "$TMP_DIR/" 2>/dev/null || true

# Extract patch list from spec - use %patch order, not Patch definition order
echo "[4/5] Extracting patch order from spec..."

# Create patch number -> filename mapping file
grep -E "^Patch[0-9]+:" "$TMP_DIR/glibc.spec" | \
    sed -E 's/^Patch0*([0-9]+):[[:space:]]*/\1 /' > "$TMP_DIR/patch-map.txt"

# Extract %patch order and convert to filenames using awk
grep -E "^%patch[0-9]+" "$TMP_DIR/glibc.spec" | \
    sed -E 's/^%patch0*([0-9]+).*/\1/' | \
    while read -r num; do
        awk -v n="$num" '$1 == n {print $2}' "$TMP_DIR/patch-map.txt"
    done > "$TMP_DIR/patch-list.txt"

PATCH_COUNT=$(wc -l < "$TMP_DIR/patch-list.txt" | tr -d ' ')
echo "Found $PATCH_COUNT patches (in application order)"

# Extract CentOS source (main + releng which includes rtkaio)
echo "[5/5] Applying patches..."
tar xzf "$TMP_DIR/glibc-2.17-c758a686.tar.gz"
tar xzf "$TMP_DIR/glibc-2.17-c758a686-releng.tar.gz"
cp -a glibc-2.17-c758a686 glibc-2.17-c758a686.orig

cd glibc-2.17-c758a686

# Initialize git repo to handle rename patches
git init -q
git add -A
git commit -q -m "initial"

APPLIED=0
FAILED=0
FAILED_LIST=""

while read -r patch_file; do
    patch_path="$TMP_DIR/$patch_file"
    if [ -f "$patch_path" ]; then
        # Try git apply first (handles renames), then fall back to patch
        if git apply --whitespace=nowarn "$patch_path" 2>/dev/null; then
            APPLIED=$((APPLIED + 1))
        elif LC_ALL=C patch -p1 --no-backup-if-mismatch -s -f < "$patch_path" 2>/dev/null; then
            APPLIED=$((APPLIED + 1))
        else
            FAILED=$((FAILED + 1))
            FAILED_LIST="$FAILED_LIST $patch_file"
        fi
    fi
done < "$TMP_DIR/patch-list.txt"

echo "Applied: $APPLIED, Failed: $FAILED"
if [ -n "$FAILED_LIST" ]; then
    echo "Failed patches:$FAILED_LIST"
fi

# Generate unified diff
echo ""
echo "Generating unified diff..."
cd "$TMP_DIR"

# Remove .git directory before diff
rm -rf glibc-2.17-c758a686/.git

# Generate diff with a/b prefix for standard patch -p1 usage
# Exclude CentOS-specific directories (releng, rtkaio, c_stubs, support) for compatibility
# Use temp file to avoid pipe truncation issues
TEMP_DIFF="$TMP_DIR/raw.patch"
diff -ruN \
    --exclude=releng \
    --exclude=rtkaio \
    --exclude=c_stubs \
    glibc-2.17-c758a686.orig glibc-2.17-c758a686 > "$TEMP_DIFF" || true

LC_ALL=C sed 's|^--- glibc-2.17-c758a686.orig/|--- a/|; s|^+++ glibc-2.17-c758a686/|+++ b/|' \
    "$TEMP_DIFF" > "$OUTPUT_FILE"

SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)

echo ""
echo "=== Done ==="
echo "Output: $OUTPUT_FILE ($SIZE)"
echo "Applied $APPLIED/$PATCH_COUNT patches"
