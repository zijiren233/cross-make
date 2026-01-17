#!/bin/sh
#
# cowpatch.sh, by Rich Felker
#
# Permission to use, copy, modify, and/or distribute this software for
# any purpose with or without fee is hereby granted.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
# WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
# AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL
# DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA
# OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
# TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
# PERFORMANCE OF THIS SOFTWARE.
#
# Take the above disclaimer seriously! This is an experimental tool
# still and does not yet take precautions against malformed/malicious
# patch files like patch(1) does. It may act out-of-tree and clobber
# stuff you didn't intend for it to clobber.
#

set -e

echo() { printf "%s\n" "$*"; }

cow() {
    test -h "$1" || return 0
    if test -d "$1"; then
        case "$1" in
        */*) set -- "${1%/*}/" "${1##*/}" ;;
        *) set -- "" "$1" ;;
        esac
        mkdir "$1$2.tmp.$$"
        mv "$1$2" "$1.$2.orig"
        mv "$1$2.tmp.$$" "$1$2"
        (cd "$1$2" && ln -s ../".$2.orig"/* .)
    else
        # Check if symlink target exists (-e follows symlinks)
        if test -e "$1"; then
            # Use cat to fully dereference symlink chain and copy actual content
            cat "$1" >"$1.tmp.$$"
            rm -f "$1"
            mv "$1.tmp.$$" "$1"
        else
            # Broken symlink - just remove it (patch will create new file)
            rm -f "$1"
        fi
    fi
}

cowp() {
    while test "$1"; do
        case "$1" in
        */*) set -- "${1#*/}" "$2${2:+/}${1%%/*}" ;;
        *) set -- "" "$2${2:+/}$1" ;;
        esac
        cow "$2"
    done
}

# Check if current directory contains any symlinks
# This detects if the directory was created with -I (symlink mode)
# Returns 0 (true) if symlinks found, 1 (false) otherwise
has_symlinks() {
    # Check if any files in current directory are symlinks
    # Use find to check top-level files only (not recursive)
    find . -maxdepth 1 -type l -print -quit | grep -q .
}

cowpatch() {

    plev=0
    OPTIND=1
    while getopts ":p:i:RNE" opt; do
        test "$opt" = p && plev="$OPTARG"
    done

    while IFS= read -r l; do
        case "$l" in
        ---* | +++*)
            IFS=" 	" read -r junk pfile junk <<EOF
$l
EOF
            # Skip /dev/null (file deletion/creation)
            case "$pfile" in /dev/null | */dev/null) ;; *)
                i=0
                while test "$i" -lt "$plev"; do
                    pfile=${pfile#*/}
                    i=$((i + 1))
                done
                cowp "$pfile"
                ;;
            esac
            echo "$l"
            ;;
        @@*)
            echo "$l"
            IFS=" " read -r junk i j junk <<EOF
$l
EOF
            case "$i" in *,*) i=${i#*,} ;; *) i=1 ;; esac
            case "$j" in *,*) j=${j#*,} ;; *) j=1 ;; esac
            while test $i -gt 0 || test $j -gt 0; do
                IFS= read -r l
                echo "$l"
                case "$l" in
                +*) j=$((j - 1)) ;;
                -*) i=$((i - 1)) ;;
                *)
                    i=$((i - 1))
                    j=$((j - 1))
                    ;;
                esac
            done
            ;;
        *) echo "$l" ;;
        esac
    done

}

gotcmd=0
while getopts ":p:i:RNEI:C:S:l:" opt; do
    case "$opt" in
    I)
        find "$OPTARG" -path "$OPTARG/*" -prune -exec sh -c 'ln -sf "$@" .' sh {} +
        gotcmd=1
        ;;
    C)
        cp -a "$OPTARG"/* .
        gotcmd=1
        ;;
    S)
        cowp "$OPTARG"
        gotcmd=1
        ;;
    l)
        # Link mode: replace current directory with symlink to source directory
        # This is useful for freebsd/netbsd where no patching is needed
        src_abs="$(cd "$OPTARG" && pwd)"
        curdir="$(pwd)"
        parent="$(dirname "$curdir")"
        name="$(basename "$curdir")"
        cd "$parent"
        rmdir "$name"
        ln -sf "$src_abs" "$name"
        gotcmd=1
        ;;
    esac
done
test "$gotcmd" -eq 0 || exit 0

# Auto-detect if current directory contains symlinks
# If no symlinks, use fast path (plain patch without any overhead)
if ! has_symlinks; then
    # Fast path: no symlinks, pass stdin directly to patch
    # No temp file, no parsing - zero overhead!
    exec patch "$@"
fi

# COW mode: directory contains symlinks (created by -I mode)
# Save patch to temp file for two-pass processing
tmpfile="/tmp/cowpatch.$$.tmp"
cat >"$tmpfile"

# First pass: COW all files mentioned in patch
# Handle multiple formats:
#   - Standard: --- a/path and +++ b/path
#   - Git: diff --git a/path b/path
#   - Git rename: rename from path / rename to path
plev=0
OPTIND=1
while getopts ":p:i:RNE" opt; do
    test "$opt" = p && plev="$OPTARG"
done

while IFS= read -r l; do
    case "$l" in
    "diff --git "*)
        # Extract both paths from: diff --git a/path1 b/path2
        rest="${l#diff --git }"
        # Split on " b/" to get the two paths
        pfile1="${rest%% b/*}"
        pfile2="${rest#* b/}"
        # Remove leading "a/" from first path
        pfile1="${pfile1#a/}"
        # COW both paths (they might be different in renames)
        test -n "$pfile1" && cowp "$pfile1"
        test -n "$pfile2" && test "$pfile2" != "$pfile1" && cowp "$pfile2"
        ;;
    "rename from "*)
        pfile="${l#rename from }"
        cowp "$pfile"
        ;;
    "rename to "*)
        pfile="${l#rename to }"
        cowp "$pfile"
        ;;
    ---* | +++*)
        IFS=" 	" read -r junk pfile junk <<EOF
$l
EOF
        case "$pfile" in /dev/null | */dev/null) continue ;; esac
        i=0
        while test "$i" -lt "$plev"; do
            pfile=${pfile#*/}
            i=$((i + 1))
        done
        cowp "$pfile"
        ;;
    esac
done <"$tmpfile"

# Second pass: run patch with the saved input
patch "$@" <"$tmpfile"
ret=$?
rm -f "$tmpfile"
exit $ret
