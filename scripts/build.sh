#!/bin/bash

set -e

function ChToScriptFileDir() {
    cd "$(dirname "$0")"
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGETS_YAML="${SCRIPT_DIR}/targets.yaml"

# Parse YAML defaults section to get a default value
# Usage: GetYamlDefault KEY
function GetYamlDefault() {
    local key="$1"
    yq -r ".defaults.${key} // \"\"" "$TARGETS_YAML"
}

# Get target-specific config from YAML by ID or TARGET
# Usage: GetTargetConfig ID_OR_TARGET KEY
function GetTargetConfig() {
    local id_or_target="$1"
    local key="$2"
    # First try to find by ID, then by TARGET (use first match only)
    local result
    result=$(yq -r "[.targets[] | select(.ID == \"${id_or_target}\")] | .[0] | .${key} // \"\"" "$TARGETS_YAML")
    if [ -z "$result" ]; then
        result=$(yq -r "[.targets[] | select(.TARGET == \"${id_or_target}\")] | .[0] | .${key} // \"\"" "$TARGETS_YAML")
    fi
    echo "$result"
}

# Get TARGET from ID (returns the input if it's already a TARGET or if ID not found)
# Usage: GetTargetFromId ID_OR_TARGET
function GetTargetFromId() {
    local id_or_target="$1"
    local target
    # First try to find TARGET by ID
    target=$(yq -r ".targets[] | select(.ID == \"${id_or_target}\") | .TARGET // \"\"" "$TARGETS_YAML")
    if [ -n "$target" ]; then
        echo "$target"
    else
        # Assume it's already a TARGET
        echo "$id_or_target"
    fi
}

# Get all targets from YAML (returns ID if present, otherwise TARGET)
function GetAllTargets() {
    yq -r '.targets[] | .ID // .TARGET' "$TARGETS_YAML"
}

function Init() {
    cd ..
    DIST="dist"
    mkdir -p "$DIST"
    OIFS="$IFS"
    IFS=$'\n\t, '

    if [ "$(uname)" == "Darwin" ]; then
        MAKE="gmake"
        TMP_BIN_DIR="$(mktemp -d)"
        PATH="$TMP_BIN_DIR:$PATH"

        # Create symlink for gmake/gnumake to ensure glibc configure finds the right version
        if [ -x "$(command -v gmake)" ]; then
            GMAKE_PATH="$(command -v gmake)"
            ln -s "$GMAKE_PATH" "$TMP_BIN_DIR/gnumake"
            ln -s "$GMAKE_PATH" "$TMP_BIN_DIR/make"
        fi

        if [ -x "$(command -v gsed)" ]; then
            SED_PATH="$(command -v gsed)"
            ln -s "$SED_PATH" "$TMP_BIN_DIR/sed"
        else
            echo "Warn: gsed not found"
            echo "Warn: when sed is not gnu version, it may cause build error"
            echo "Warn: you can install gsed with brew"
            echo "Warn: brew install gnu-sed"
            sleep 3
        fi

        if [ -x "$(command -v glibtool)" ]; then
            LIBTOOL_PATH="$(command -v glibtool)"
            ln -s "$LIBTOOL_PATH" "$TMP_BIN_DIR/libtool"
        else
            echo "Warn: glibtool not found"
            echo "Warn: when libtool is not gnu version, it may cause build error"
            echo "Warn: you can install libtool with brew"
            echo "Warn: brew install libtool"
            sleep 3
        fi

        if [ -x "$(command -v greadlink)" ]; then
            READLINK_PATH="$(command -v greadlink)"
            ln -s "$READLINK_PATH" "$TMP_BIN_DIR/readlink"
        else
            echo "Warn: greadlink not found"
            echo "Warn: when readlink is not gnu version, it may cause build error"
            echo "Warn: you can install coreutils with brew"
            echo "Warn: brew install coreutils"
            sleep 3
        fi

        if [ -x "$(command -v gfind)" ]; then
            FIND_PATH="$(command -v gfind)"
            ln -s "$FIND_PATH" "$TMP_BIN_DIR/find"
        else
            echo "Warn: gfind not found"
            echo "Warn: when find is not gnu version, it may cause build error"
            echo "Warn: you can install findutils with brew"
            echo "Warn: brew install findutils"
            sleep 3
        fi

        if [ -x "$(command -v gawk)" ]; then
            AWK_PATH="$(command -v gawk)"
            ln -s "$AWK_PATH" "$TMP_BIN_DIR/awk"
        else
            echo "Warn: gawk not found"
            echo "Warn: when awk is not gnu version, it may cause build error"
            echo "Warn: you can install gawk with brew"
            echo "Warn: brew install gawk"
            sleep 3
        fi

        if [ -x "$(command -v gpatch)" ]; then
            PATCH_PATH="$(command -v gpatch)"
            ln -s "$PATCH_PATH" "$TMP_BIN_DIR/patch"
        else
            echo "Warn: gpatch not found"
            echo "Warn: when patch is not gnu version, it may cause build error"
            echo "Warn: you can install gpatch with brew"
            echo "Warn: brew install gpatch"
            sleep 3
        fi

        # Check for bison version - glibc 2.40 requires bison >= 2.7
        BISON_PATH=""
        BISON_VERSION=""

        # First check Homebrew bison (usually newer)
        brew --prefix bison
        if [ -x "$(brew --prefix bison)/bin/bison" ]; then
            BISON_PATH="$(brew --prefix bison)/bin/bison"
            BISON_VERSION=$("$BISON_PATH" --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
        elif [ -x "$(command -v bison)" ]; then
            BISON_PATH="$(command -v bison)"
            BISON_VERSION=$("$BISON_PATH" --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
        fi

        if [ -n "$BISON_PATH" ] && [ -n "$BISON_VERSION" ]; then
            # Extract major and minor version
            BISON_MAJOR=$(echo "$BISON_VERSION" | cut -d. -f1)
            BISON_MINOR=$(echo "$BISON_VERSION" | cut -d. -f2)

            # Check if version is >= 2.7
            if [ "$BISON_MAJOR" -gt 2 ] || ([ "$BISON_MAJOR" -eq 2 ] && [ "$BISON_MINOR" -ge 7 ]); then
                ln -s "$BISON_PATH" "$TMP_BIN_DIR/bison"
                echo "Info: Using bison $BISON_VERSION from $BISON_PATH"
            else
                echo "Warn: bison version $BISON_VERSION is too old (need >= 2.7)"
                echo "Warn: glibc build requires bison >= 2.7"
                echo "Warn: Please manually install: brew install bison"
                echo "Warn: Then add to PATH: export PATH=\"/opt/homebrew/opt/bison/bin:\$PATH\""
                sleep 3
            fi
        else
            echo "Warn: bison not found"
            echo "Warn: glibc build requires bison >= 2.7"
            echo "Warn: Please manually install: brew install bison"
            echo "Warn: Then add to PATH: export PATH=\"/opt/homebrew/opt/bison/bin:\$PATH\""
            sleep 3
        fi

    else
        MAKE="make"
    fi

    # Read default values from targets.yaml
    {
        DEFAULT_CONFIG_SUB_REV="a2287c3041a3"
        DEFAULT_GCC_VER="$(GetYamlDefault GCC_VER)"
        DEFAULT_MUSL_VER="$(GetYamlDefault MUSL_VER)"
        DEFAULT_GLIBC_VER="$(GetYamlDefault GLIBC_VER)"
        DEFAULT_BINUTILS_VER="$(GetYamlDefault BINUTILS_VER)"
        DEFAULT_GMP_VER="$(GetYamlDefault GMP_VER)"
        DEFAULT_MPC_VER="$(GetYamlDefault MPC_VER)"
        DEFAULT_MPFR_VER="$(GetYamlDefault MPFR_VER)"
        DEFAULT_ISL_VER="$(GetYamlDefault ISL_VER)"
        DEFAULT_ZSTD_VER="$(GetYamlDefault ZSTD_VER)"
        DEFAULT_LINUX_VER="$(GetYamlDefault LINUX_VER)"
        DEFAULT_MINGW_VER="$(GetYamlDefault MINGW_VER)"
        DEFAULT_FREEBSD_VER="$(GetYamlDefault FREEBSD_VER)"
        DEFAULT_NETBSD_VER="$(GetYamlDefault NETBSD_VER)"

        if [ ! "$CONFIG_SUB_REV" ]; then
            CONFIG_SUB_REV="$DEFAULT_CONFIG_SUB_REV"
        fi
        if [ ! "$GCC_VER" ]; then
            GCC_VER="$DEFAULT_GCC_VER"
        fi
        if [ -z "${MUSL_VER+x}" ]; then
            MUSL_VER="$DEFAULT_MUSL_VER"
        fi
        if [ -z "${GLIBC_VER+x}" ]; then
            GLIBC_VER="$DEFAULT_GLIBC_VER"
        fi
        if [ ! "$BINUTILS_VER" ]; then
            BINUTILS_VER="$DEFAULT_BINUTILS_VER"
        fi
        if [ ! "$GMP_VER" ]; then
            GMP_VER="$DEFAULT_GMP_VER"
        fi
        if [ ! "$MPC_VER" ]; then
            MPC_VER="$DEFAULT_MPC_VER"
        fi
        if [ ! "$MPFR_VER" ]; then
            MPFR_VER="$DEFAULT_MPFR_VER"
        fi
        if [ -z "${ISL_VER+x}" ]; then
            ISL_VER="$DEFAULT_ISL_VER"
        fi
        if [ -z "${ZSTD_VER+x}" ]; then
            ZSTD_VER="$DEFAULT_ZSTD_VER"
        fi
        if [ -z "${LINUX_VER+x}" ]; then
            LINUX_VER="$DEFAULT_LINUX_VER"
        fi
        if [ -z "${MINGW_VER+x}" ]; then
            MINGW_VER="$DEFAULT_MINGW_VER"
        fi
        if [ -z "${FREEBSD_VER+x}" ]; then
            FREEBSD_VER="$DEFAULT_FREEBSD_VER"
        fi
        if [ -z "${NETBSD_VER+x}" ]; then
            NETBSD_VER="$DEFAULT_NETBSD_VER"
        fi
    }
}

function Help() {
    echo "-h: help"
    echo "-a: enable archive"
    echo "-T: targets file path or targets string"
    echo "-S: sources directory path"
    echo "-C: use china mirror"
    echo "-c: set CC"
    echo "-x: set CXX"
    echo "-n: with native build"
    echo "-N: only native build"
    echo "-L: log to std"
    echo "-l: disable log to file"
    echo "-O: set optimize level"
    echo "-j: set job number"
    echo "-i: simpler build"
    echo "-d: download sources only"
    echo "-D: disable log print date prefix"
    echo "-P: disable log print target prefix"
    echo "-b: enable ccache"
}

function ParseArgs() {
    while getopts "haT:S:Cc:x:nLlO:j:NdDPb" arg; do
        case $arg in
        h)
            Help
            exit 0
            ;;
        a)
            ENABLE_ARCHIVE="true"
            ;;
        T)
            TARGETS_FILE="$OPTARG"
            ;;
        S)
            SOURCES_DIR="$OPTARG"
            ;;
        C)
            USE_CHINA_MIRROR="true"
            ;;
        c)
            CC="$OPTARG"
            ;;
        x)
            CXX="$OPTARG"
            ;;
        n)
            NATIVE_BUILD="true"
            ;;
        N)
            NATIVE_BUILD="true"
            ONLY_NATIVE_BUILD="true"
            ;;
        L)
            LOG_TO_STD="true"
            ;;
        l)
            DISABLE_LOG_TO_FILE="true"
            ;;
        O)
            OPTIMIZE_LEVEL="$OPTARG"
            ;;
        j)
            if [ "$OPTARG" -eq "$OPTARG" ] 2>/dev/null; then
                CPU_NUM="$OPTARG"
            else
                echo "cpu number must be number"
                exit 1
            fi
            ;;
        d)
            SOURCES_ONLY="true"
            ;;
        D)
            DISABLE_LOG_PRINT_DATE_PREFIX="true"
            ;;
        P)
            DISABLE_LOG_PRINT_TARGET_PREFIX="true"
            ;;
        b)
            CCACHE="ccache"
            ;;
        ?)
            echo "unkonw argument"
            exit 1
            ;;
        esac
    done
    shift $((OPTIND - 1))
    MORE_ARGS="$@"
}

function FixArgs() {
    mkdir -p "${DIST}"
    DIST="$(cd "$DIST" && pwd)"

    if [ ! "$CPU_NUM" ]; then
        CPU_NUM=$(nproc)
        if [ $? -ne 0 ]; then
            CPU_NUM=2
        fi
    fi

    echo "job nums: $CPU_NUM"

    if [ "$SOURCES_ONLY" ]; then
        WriteConfig
        $MAKE -j${CPU_NUM} SOURCES_ONLY="true" extract_all
        exit $?
    fi

    # only support O2 and Os Oz
    case "$OPTIMIZE_LEVEL" in
    "s" | "z") ;;
    *)
        OPTIMIZE_LEVEL="2"
        ;;
    esac
}

function Date() {
    if [ "$DISABLE_LOG_PRINT_DATE_PREFIX" ]; then
        return
    fi
    echo "[$(date '+%H:%M:%S')] "
}

function WriteConfig() {
    # Read target-specific configuration from targets.yaml
    local USE_MUSL=""
    local USE_GLIBC=""
    local USE_FREEBSD=""
    local USE_NETBSD=""
    local USE_MINGW=""

    # Try to get target-specific values from YAML using BUILD_ID
    local YAML_MUSL_VER="$(GetTargetConfig "$BUILD_ID" MUSL_VER)"
    local YAML_GLIBC_VER="$(GetTargetConfig "$BUILD_ID" GLIBC_VER)"
    local YAML_FREEBSD_VER="$(GetTargetConfig "$BUILD_ID" FREEBSD_VER)"
    local YAML_NETBSD_VER="$(GetTargetConfig "$BUILD_ID" NETBSD_VER)"
    local YAML_MINGW_VER="$(GetTargetConfig "$BUILD_ID" MINGW_VER)"

    # Use YAML values if available, otherwise use defaults based on target type
    if [ -n "$YAML_MUSL_VER" ]; then
        USE_MUSL="$YAML_MUSL_VER"
    elif [ -n "$YAML_GLIBC_VER" ]; then
        USE_GLIBC="$YAML_GLIBC_VER"
    elif [ -n "$YAML_FREEBSD_VER" ]; then
        USE_FREEBSD="$YAML_FREEBSD_VER"
    elif [ -n "$YAML_NETBSD_VER" ]; then
        USE_NETBSD="$YAML_NETBSD_VER"
    elif [ -n "$YAML_MINGW_VER" ]; then
        USE_MINGW="$YAML_MINGW_VER"
    else
        # Fallback: determine libc type from target name
        if [[ "$TARGET" == *"mingw"* ]]; then
            USE_MINGW="${MINGW_VER}"
        elif [[ "$TARGET" == *"freebsd"* ]]; then
            USE_FREEBSD="${FREEBSD_VER}"
        elif [[ "$TARGET" == *"netbsd"* ]]; then
            USE_NETBSD="${NETBSD_VER}"
        elif [[ "$TARGET" == *"gnu"* ]] || [[ "$TARGET" == *"glibc"* ]]; then
            USE_GLIBC="${GLIBC_VER}"
        else
            USE_MUSL="${MUSL_VER}"
        fi
    fi

    cat >config.mak <<EOF
CONFIG_SUB_REV = ${CONFIG_SUB_REV}
TARGET = ${TARGET}
NATIVE = ${NATIVE}
OUTPUT = ${OUTPUT}
$(if [ -n "$SOURCES_DIR" ]; then echo "SOURCES = ${SOURCES_DIR}"; fi)
GCC_VER = ${GCC_VER}
MUSL_VER = ${USE_MUSL}
GLIBC_VER = ${USE_GLIBC}
FREEBSD_VER = ${USE_FREEBSD}
NETBSD_VER = ${USE_NETBSD}
BINUTILS_VER = ${BINUTILS_VER}

GMP_VER = ${GMP_VER}
MPC_VER = ${MPC_VER}
MPFR_VER = ${MPFR_VER}
ISL_VER = ${ISL_VER}
ZSTD_VER = ${ZSTD_VER}

LINUX_VER = ${LINUX_VER}
MINGW_VER = ${MINGW_VER}

# only work in cross build
# native build will find ${TARGET}-gcc ${TARGET}-g++ in env to build
ifneq (${CC}${CXX},)
CC = ${CC}
CXX = ${CXX}
endif

CHINA = ${USE_CHINA_MIRROR}

COMMON_FLAGS += -O${OPTIMIZE_LEVEL}

CCACHE = ${CCACHE}

EOF
    for arg in "$@"; do
        echo "$arg" >>config.mak
    done
}

function TestCrossCC() {
    COMPILER="$@"
    if [ -z "$COMPILER" ]; then
        echo "no compiler"
        return 1
    fi
    echo "test cross compiler: $COMPILER"
    if ! echo '#include <stdio.h>
int main()
{
    printf("hello world\\n");
    return 0;
}
' | $COMPILER -x c - -o buildtest; then
        echo "test cross compiler error"
        return 1
    else
        rm buildtest*
        echo "test cross compiler success"
        return
    fi
}

function TestCrossCXX() {
    COMPILER="$@"
    if [ -z "$COMPILER" ]; then
        echo "no compiler"
        return 1
    fi
    echo "test cross compiler: $COMPILER"
    if ! echo '#include <iostream>
int main()
{
    std::cout << "hello world" << std::endl;
    return 0;
}
' | $COMPILER -x c++ - -o buildtest; then
        echo "test cross compiler error"
        return 1
    else
        rm buildtest*
        echo "test cross compiler success"
        return
    fi
}

function Build() {
    BUILD_ID="$1"
    # Resolve actual TARGET from BUILD_ID (BUILD_ID can be an ID or a TARGET)
    local TARGET="$(GetTargetFromId "$BUILD_ID")"

    # Use BUILD_ID for artifact naming to ensure uniqueness
    DIST_NAME="${DIST}/${DIST_NAME_PREFIX}${BUILD_ID}"
    CROSS_DIST_NAME="${DIST_NAME}-cross${CROSS_DIST_NAME_SUFFIX}"
    NATIVE_DIST_NAME="${DIST_NAME}-native${NATIVE_DIST_NAME_SUFFIX}"
    CROSS_LOG_FILE="${CROSS_DIST_NAME}.log"
    NATIVE_LOG_FILE="${NATIVE_DIST_NAME}.log"

    if [ ! "$ONLY_NATIVE_BUILD" ]; then
        echo "build cross ${DIST_NAME_PREFIX}${BUILD_ID} (TARGET=${TARGET}) to ${CROSS_DIST_NAME}"
        {
            OUTPUT="${CROSS_DIST_NAME}"
            NATIVE=""
            WriteConfig "export PATH=$PATH"
        }
        $MAKE -j${CPU_NUM} clean
        rm -rf "${CROSS_DIST_NAME}" "${CROSS_LOG_FILE}"
        while IFS= read -r line; do
            CURRENT_DATE=$(Date)
            if [ "$LOG_TO_STD" ]; then
                if [ "$DISABLE_LOG_PRINT_TARGET_PREFIX" ]; then
                    echo "${CURRENT_DATE}$line"
                else
                    echo "${CURRENT_DATE}${DIST_NAME_PREFIX}${TARGET}-cross: $line"
                fi
            fi
            if [ ! "$DISABLE_LOG_TO_FILE" ]; then
                echo "${CURRENT_DATE}$line" >>"${CROSS_LOG_FILE}"
            fi
        done < <(
            set +e
            $MAKE -j${CPU_NUM} $MORE_ARGS 2>&1 && $MAKE $MORE_ARGS -j1 install 2>&1
            echo $? >"${CROSS_DIST_NAME}.exit"
            set -e
        )
        read EXIT_CODE <"${CROSS_DIST_NAME}.exit"
        rm "${CROSS_DIST_NAME}.exit"
        if [ $EXIT_CODE -ne 0 ]; then
            if [ ! "$LOG_TO_STD" ]; then
                tail -n 3000 "${CROSS_LOG_FILE}"
                echo "full build log: ${CROSS_LOG_FILE}"
            fi
            echo "build cross ${DIST_NAME_PREFIX}${TARGET} error"
            exit $EXIT_CODE
        else
            echo "build cross ${DIST_NAME_PREFIX}${TARGET} success"
            TestCrossCC "${CROSS_DIST_NAME}/bin/${TARGET}-gcc"
            TestCrossCXX "${CROSS_DIST_NAME}/bin/${TARGET}-g++"
            TestCrossCC "${CROSS_DIST_NAME}/bin/${TARGET}-gcc -static --static"
            TestCrossCXX "${CROSS_DIST_NAME}/bin/${TARGET}-g++ -static --static"
        fi
        if [ "$ENABLE_ARCHIVE" ]; then
            tar -zcf "${CROSS_DIST_NAME}.tgz" -C "${CROSS_DIST_NAME}" .
            echo "package ${CROSS_DIST_NAME} to ${CROSS_DIST_NAME}.tgz success"
        fi
    fi

    if [ "$NATIVE_BUILD" ]; then
        echo "build native ${DIST_NAME_PREFIX}${TARGET} to ${NATIVE_DIST_NAME}"
        {
            OUTPUT="${NATIVE_DIST_NAME}"
            NATIVE="true"
            WriteConfig "export PATH=${CROSS_DIST_NAME}/bin:$PATH"
        }
        $MAKE -j${CPU_NUM} clean
        rm -rf "${NATIVE_DIST_NAME}" "${NATIVE_LOG_FILE}"
        while IFS= read -r line; do
            CURRENT_DATE=$(Date)
            if [ "$LOG_TO_STD" ]; then
                if [ "$DISABLE_LOG_PRINT_TARGET_PREFIX" ]; then
                    echo "${CURRENT_DATE}$line"
                else
                    echo "${CURRENT_DATE}${DIST_NAME_PREFIX}${TARGET}-native: $line"
                fi
            fi
            if [ ! "$DISABLE_LOG_TO_FILE" ]; then
                echo "${CURRENT_DATE}$line" >>"${NATIVE_LOG_FILE}"
            fi
        done < <(
            set +e
            $MAKE -j${CPU_NUM} $MORE_ARGS 2>&1 && $MAKE $MORE_ARGS -j1 install 2>&1
            echo $? >"${NATIVE_DIST_NAME}.exit"
            set -e
        )
        read EXIT_CODE <"${NATIVE_DIST_NAME}.exit"
        rm "${NATIVE_DIST_NAME}.exit"
        if [ $EXIT_CODE -ne 0 ]; then
            if [ ! "$LOG_TO_STD" ]; then
                tail -n 3000 "${NATIVE_LOG_FILE}"
                echo "full build log: ${NATIVE_LOG_FILE}"
            fi
            echo "build native ${DIST_NAME_PREFIX}${TARGET} error"
            exit $EXIT_CODE
        else
            echo "build native ${DIST_NAME_PREFIX}${TARGET} success"
        fi
        if [ "$ENABLE_ARCHIVE" ]; then
            tar -zcf "${NATIVE_DIST_NAME}.tgz" -C "${NATIVE_DIST_NAME}" .
            echo "package ${NATIVE_DIST_NAME} to ${NATIVE_DIST_NAME}.tgz success"
            if [[ $TARGET =~ mingw ]]; then
                find "${NATIVE_DIST_NAME}" -type l -delete
                zip -rq "${NATIVE_DIST_NAME}.zip" "${NATIVE_DIST_NAME}"
                echo "package ${NATIVE_DIST_NAME} to ${NATIVE_DIST_NAME}.zip success"
            fi
        fi
    fi
}

# ALL_TARGETS is now read from targets.yaml via GetAllTargets function

function BuildAll() {
    if [ -n "$TARGETS_FILE" ]; then
        if [ -f "$TARGETS_FILE" ]; then
            # Read from file (legacy txt format support)
            while read line; do
                if [ -z "$line" ] || [ "${line:0:1}" == "#" ]; then
                    continue
                fi
                Build "$line"
            done <"$TARGETS_FILE"
            return
        else
            # TARGETS_FILE is a comma/space separated list of targets
            TARGETS="$TARGETS_FILE"
        fi
    else
        # Use TARGET env var if set, otherwise get all targets from YAML
        if [ -n "$TARGET" ]; then
            TARGETS="$TARGET"
        else
            TARGETS="$(GetAllTargets)"
        fi
    fi

    for line in $TARGETS; do
        if [ -z "$line" ] || [ "${line:0:1}" == "#" ]; then
            continue
        fi
        Build "$line"
    done
}

ChToScriptFileDir
Init
ParseArgs "$@"
FixArgs
BuildAll
