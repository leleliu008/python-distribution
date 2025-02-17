#!/bin/sh

# Copyright (c) 2024-2024 刘富频
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


set -e

# If IFS is not set, the default value will be <space><tab><newline>
# https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_05_03
unset IFS


COLOR_RED='\033[0;31m'          # Red
COLOR_GREEN='\033[0;32m'        # Green
COLOR_YELLOW='\033[0;33m'       # Yellow
COLOR_BLUE='\033[0;94m'         # Blue
COLOR_PURPLE='\033[0;35m'       # Purple
COLOR_OFF='\033[0m'             # Reset

print() {
    printf '%b' "$*"
}

echo() {
    printf '%b\n' "$*"
}

note() {
    printf '%b\n' "${COLOR_YELLOW}🔔  $*${COLOR_OFF}" >&2
}

warn() {
    printf '%b\n' "${COLOR_YELLOW}🔥  $*${COLOR_OFF}" >&2
}

success() {
    printf '%b\n' "${COLOR_GREEN}[✔] $*${COLOR_OFF}" >&2
}

error() {
    printf '%b\n' "${COLOR_RED}💔  $ARG0: $*${COLOR_OFF}" >&2
}

abort() {
    EXIT_STATUS_CODE="$1"
    shift
    printf '%b\n' "${COLOR_RED}💔  $ARG0: $*${COLOR_OFF}" >&2
    exit "$EXIT_STATUS_CODE"
}

run() {
    echo "${COLOR_PURPLE}==>${COLOR_OFF} ${COLOR_GREEN}$@${COLOR_OFF}"
    eval "$@"
}

isInteger() {
    case "${1#[+-]}" in
        (*[!0123456789]*) return 1 ;;
        ('')              return 1 ;;
        (*)               return 0 ;;
    esac
}

# wfetch <URL> [--uri=<URL-MIRROR>] [--sha256=<SHA256>] [-o <OUTPUT-PATH>] [--no-buffer]
#
# If -o <OUTPUT-PATH> option is unspecified, the result will be written to <PWD>/$(basename <URL>).
#
# If <OUTPUT-PATH> is . .. ./ ../ or ends with slash(/), then it will be treated as a directory, otherwise, it will be treated as a filepath.
#
# If <OUTPUT-PATH> is -, then it will be treated as /dev/stdout.
#
# If <OUTPUT-PATH> is treated as a directory, then it will be expanded to <OUTPUT-PATH>/$(basename <URL>)
#
wfetch() {
    unset FETCH_UTS
    unset FETCH_SHA

    unset FETCH_URL
    unset FETCH_URI

    unset FETCH_PATH

    unset FETCH_OUTPUT_DIR
    unset FETCH_OUTPUT_FILEPATH
    unset FETCH_OUTPUT_FILENAME

    unset FETCH_BUFFER_FILEPATH

    unset FETCH_SHA256_EXPECTED

    unset NOT_BUFFER

    [ -z "$1" ] && abort 1 "wfetch <URL> [OPTION]... , <URL> must be non-empty."

    if [ -z "$URL_TRANSFORM" ] ; then
        FETCH_URL="$1"
    else
        FETCH_URL="$("$URL_TRANSFORM" "$1")" || return 1
    fi

    shift

    while [ -n "$1" ]
    do
        case $1 in
            --uri=*)
                FETCH_URI="${1#*=}"
                ;;
            --sha256=*)
                FETCH_SHA256_EXPECTED="${1#*=}"
                ;;
            -o) shift
                if [ -z "$1" ] ; then
                    abort 1 "wfetch <URL> -o <PATH> , <PATH> must be non-empty."
                else
                    FETCH_PATH="$1"
                fi
                ;;
            --no-buffer)
                NOT_BUFFER=1
                ;;
            *)  abort 1 "wfetch <URL> [--uri=<URL-MIRROR>] [--sha256=<SHA256>] [-o <PATH>] [-q] , unrecognized option: $1"
        esac
        shift
    done

    if [ -z "$FETCH_URI" ] ; then
        # remove query params
        FETCH_URI="${FETCH_URL%%'?'*}"
        FETCH_URI="https://fossies.org/linux/misc/${FETCH_URI##*/}"
    else
        if [ -n "$URL_TRANSFORM" ] ; then
            FETCH_URI="$("$URL_TRANSFORM" "$FETCH_URI")" || return 1
        fi
    fi

    case $FETCH_PATH in
        -)  FETCH_BUFFER_FILEPATH='-' ;;
        .|'')
            FETCH_OUTPUT_DIR='.'
            FETCH_OUTPUT_FILEPATH="$FETCH_OUTPUT_DIR/${FETCH_URL##*/}"
            ;;
        ..)
            FETCH_OUTPUT_DIR='..'
            FETCH_OUTPUT_FILEPATH="$FETCH_OUTPUT_DIR/${FETCH_URL##*/}"
            ;;
        */)
            FETCH_OUTPUT_DIR="${FETCH_PATH%/}"
            FETCH_OUTPUT_FILEPATH="$FETCH_OUTPUT_DIR/${FETCH_URL##*/}"
            ;;
        *)
            FETCH_OUTPUT_DIR="$(dirname "$FETCH_PATH")"
            FETCH_OUTPUT_FILEPATH="$FETCH_PATH"
    esac

    if [ -n "$FETCH_OUTPUT_FILEPATH" ] ; then
        if [ -f "$FETCH_OUTPUT_FILEPATH" ] ; then
            if [ -n "$FETCH_SHA256_EXPECTED" ] ; then
                if [ "$(sha256sum "$FETCH_OUTPUT_FILEPATH" | cut -d ' ' -f1)" = "$FETCH_SHA256_EXPECTED" ] ; then
                    success "$FETCH_OUTPUT_FILEPATH already have been fetched."
                    return 0
                fi
            fi
        fi

        if [ "$NOT_BUFFER" = 1 ] ; then
            FETCH_BUFFER_FILEPATH="$FETCH_OUTPUT_FILEPATH"
        else
            FETCH_UTS="$(date +%s)"

            FETCH_SHA="$(printf '%s\n' "$FETCH_URL:$$:$FETCH_UTS" | sha256sum | cut -d ' ' -f1)"

            FETCH_BUFFER_FILEPATH="$FETCH_OUTPUT_DIR/$FETCH_SHA.tmp"
        fi
    fi

    for FETCH_TOOL in curl wget http lynx aria2c axel
    do
        if command -v "$FETCH_TOOL" > /dev/null ; then
            break
        else
            unset FETCH_TOOL
        fi
    done

    if [ -z "$FETCH_TOOL" ] ; then
        abort 1 "no fetch tool found, please install one of curl wget http lynx aria2c axel, then try again."
    fi

    if [                -n "$FETCH_OUTPUT_DIR" ] ; then
        if [ !          -d "$FETCH_OUTPUT_DIR" ] ; then
            run install -d "$FETCH_OUTPUT_DIR" || return 1
        fi
    fi

    case $FETCH_TOOL in
        curl)
            CURL_OPTIONS="--fail --retry 20 --retry-delay 30 --location"

            if [ "$DUMP_HTTP" = 1 ] ; then
                CURL_OPTIONS="$CURL_OPTIONS --verbose"
            fi

            if [ -n "$SSL_CERT_FILE" ] ; then
                CURL_OPTIONS="$CURL_OPTIONS --cacert $SSL_CERT_FILE"
            fi

            run "curl $CURL_OPTIONS -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URL'" ||
            run "curl $CURL_OPTIONS -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URI'"
            ;;
        wget)
            run "wget --timeout=60 -O '$FETCH_BUFFER_FILEPATH' '$FETCH_URL'" ||
            run "wget --timeout=60 -O '$FETCH_BUFFER_FILEPATH' '$FETCH_URI'"
            ;;
        http)
            run "http --timeout=60 -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URL'" ||
            run "http --timeout=60 -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URI'"
            ;;
        lynx)
            run "lynx -source '$FETCH_URL' > '$FETCH_BUFFER_FILEPATH'" ||
            run "lynx -source '$FETCH_URI' > '$FETCH_BUFFER_FILEPATH'"
            ;;
        aria2c)
            run "aria2c -d '$FETCH_OUTPUT_DIR' -o '$FETCH_OUTPUT_FILENAME' '$FETCH_URL'" ||
            run "aria2c -d '$FETCH_OUTPUT_DIR' -o '$FETCH_OUTPUT_FILENAME' '$FETCH_URI'"
            ;;
        axel)
            run "axel -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URL'" ||
            run "axel -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URI'"
            ;;
        *)  abort 1 "wfetch() unimplementation: $FETCH_TOOL"
            ;;
    esac

    [ $? -eq 0 ] || return 1

    if [ -n "$FETCH_OUTPUT_FILEPATH" ] ; then
        if [ -n "$FETCH_SHA256_EXPECTED" ] ; then
            FETCH_SHA256_ACTUAL="$(sha256sum "$FETCH_BUFFER_FILEPATH" | cut -d ' ' -f1)"

            if [ "$FETCH_SHA256_ACTUAL" != "$FETCH_SHA256_EXPECTED" ] ; then
                abort 1 "sha256sum mismatch.\n    expect : $FETCH_SHA256_EXPECTED\n    actual : $FETCH_SHA256_ACTUAL\n"
            fi
        fi

        if [ "$NOT_BUFFER" != 1 ] ; then
            run mv "$FETCH_BUFFER_FILEPATH" "$FETCH_OUTPUT_FILEPATH"
        fi
    fi
}

filetype_from_url() {
    # remove query params
    URL="${1%%'?'*}"

    FNAME="${URL##*/}"

    case $FNAME in
        *.tar.gz|*.tgz)
            printf '%s\n' '.tgz'
            ;;
        *.tar.lz|*.tlz)
            printf '%s\n' '.tlz'
            ;;
        *.tar.xz|*.txz)
            printf '%s\n' '.txz'
            ;;
        *.tar.bz2|*.tbz2)
            printf '%s\n' '.tbz2'
            ;;
        *.*)printf '%s\n' ".${FNAME##*.}"
    esac
}

inspect_install_arguments() {
    unset PROFILE

    unset LOG_LEVEL

    unset BUILD_NJOBS

    unset ENABLE_LTO

    unset REQUEST_TO_KEEP_SESSION_DIR

    unset REQUEST_TO_EXPORT_COMPILE_COMMANDS_JSON

    unset REQUEST_TO_CREATE_FULLY_STATICALLY_LINKED_EXECUTABLE

    unset SPECIFIED_PACKAGE_LIST

    unset SESSION_DIR
    unset DOWNLOAD_DIR
    unset PACKAGE_INSTALL_DIR

    unset DUMP_ENV
    unset DUMP_HTTP

    unset VERBOSE_GMAKE

    unset DEBUG_CC
    unset DEBUG_LD

    PYTHON_EDITION="$1"

    case $PYTHON_EDITION in
        3.1[0-3])
            ;;
        3.9);;
        *)  abort 1 "unsupported python edition: $PYTHON_EDITION"
    esac

    shift

    while [ -n "$1" ]
    do
        case $1 in
            -x) set -x ;;
            -q) LOG_LEVEL=0 ;;
            -v) LOG_LEVEL=2

                DUMP_ENV=1
                DUMP_HTTP=1

                VERBOSE_GMAKE=1
                ;;
            -vv)LOG_LEVEL=3

                DUMP_ENV=1
                DUMP_HTTP=1

                VERBOSE_GMAKE=1

                DEBUG_CC=1
                DEBUG_LD=1
                ;;
            -v-env)
                DUMP_ENV=1
                ;;
            -v-http)
                DUMP_HTTP=1
                ;;
            -v-gmake)
                VERBOSE_GMAKE=1
                ;;
            -v-cc)
                DEBUG_CC=1
                ;;
            -v-ld)
                DEBUG_LD=1
                ;;
            --profile=*)
                PROFILE="${1#*=}"
                ;;
            --session-dir=*)
                SESSION_DIR="${1#*=}"

                case $SESSION_DIR in
                    /*) ;;
                    *)  SESSION_DIR="$PWD/$SESSION_DIR"
                esac
                ;;
            --download-dir=*)
                DOWNLOAD_DIR="${1#*=}"

                case $DOWNLOAD_DIR in
                    /*) ;;
                    *)  DOWNLOAD_DIR="$PWD/$DOWNLOAD_DIR"
                esac
                ;;
            --prefix=*)
                PACKAGE_INSTALL_DIR="${1#*=}"

                case $PACKAGE_INSTALL_DIR in
                    /*) ;;
                    *)  PACKAGE_INSTALL_DIR="$PWD/$PACKAGE_INSTALL_DIR"
                esac
                ;;
            --static)
                REQUEST_TO_CREATE_FULLY_STATICALLY_LINKED_EXECUTABLE=1
                ;;
            -j) shift
                isInteger "$1" || abort 1 "-j <N>, <N> must be an integer."
                BUILD_NJOBS="$1"
                ;;
            -K) REQUEST_TO_KEEP_SESSION_DIR=1 ;;
            -E) REQUEST_TO_EXPORT_COMPILE_COMMANDS_JSON=1 ;;

            -*) abort 1 "unrecognized option: $1"
                ;;
            *)  SPECIFIED_PACKAGE_LIST="$SPECIFIED_PACKAGE_LIST $1"
        esac
        shift
    done

    #########################################################################################

    : ${PROFILE:=release}
    : ${ENABLE_LTO:=1}

    : ${SESSION_DIR:="$HOME/.xbuilder/run/$$"}
    : ${DOWNLOAD_DIR:="$HOME/.xbuilder/downloads"}
    : ${PACKAGE_INSTALL_DIR:="$HOME/.xbuilder/installed/python3"}

    #########################################################################################

    AUX_INSTALL_DIR="$SESSION_DIR/auxroot"
    AUX_INCLUDE_DIR="$AUX_INSTALL_DIR/include"
    AUX_LIBRARY_DIR="$AUX_INSTALL_DIR/lib"

    #########################################################################################

    NATIVE_PLATFORM_KIND="$(uname -s | tr A-Z a-z)"
    NATIVE_PLATFORM_ARCH="$(uname -m)"

    #########################################################################################

    if [ -z "$BUILD_NJOBS" ] ; then
        if [ "$NATIVE_PLATFORM_KIND" = 'darwin' ] ; then
            NATIVE_PLATFORM_NCPU="$(sysctl -n machdep.cpu.thread_count)"
        else
            NATIVE_PLATFORM_NCPU="$(nproc)"
        fi

        BUILD_NJOBS="$NATIVE_PLATFORM_NCPU"
    fi

    #########################################################################################

    if [ "$LOG_LEVEL" = 0 ] ; then
        exec 1>/dev/null
        exec 2>&1
    else
        if [ -z "$LOG_LEVEL" ] ; then
            LOG_LEVEL=1
        fi
    fi

    #########################################################################################

    if [ -z "$TAR" ] ; then
        TAR="$(command -v bsdtar || command -v gtar || command -v tar)" || abort 1 "none of bsdtar, gtar, tar command was found."
    fi

    if [ -z "$GMAKE" ] ; then
        GMAKE="$(command -v gmake || command -v make)" || abort 1 "command not found: gmake"
    fi

    #########################################################################################

    unset CC_ARGS
    unset PP_ARGS
    unset LD_ARGS

    if [ "$NATIVE_PLATFORM_KIND" = 'darwin' ] ; then
        [ -z "$CC"      ] &&      CC="$(xcrun --sdk macosx --find clang)"
        [ -z "$CXX"     ] &&     CXX="$(xcrun --sdk macosx --find clang++)"
        [ -z "$AS"      ] &&      AS="$(xcrun --sdk macosx --find as)"
        [ -z "$LD"      ] &&      LD="$(xcrun --sdk macosx --find ld)"
        [ -z "$AR"      ] &&      AR="$(xcrun --sdk macosx --find ar)"
        [ -z "$RANLIB"  ] &&  RANLIB="$(xcrun --sdk macosx --find ranlib)"
        [ -z "$SYSROOT" ] && SYSROOT="$(xcrun --sdk macosx --show-sdk-path)"

        [ -z "$MACOSX_DEPLOYMENT_TARGET" ] && MACOSX_DEPLOYMENT_TARGET="$(sw_vers -productVersion)"

        CC_ARGS="-isysroot $SYSROOT -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -arch $NATIVE_PLATFORM_ARCH -Qunused-arguments"
        PP_ARGS="-isysroot $SYSROOT -Qunused-arguments"
        LD_ARGS="-isysroot $SYSROOT -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -arch $NATIVE_PLATFORM_ARCH"
    else
        [ -z "$CC" ] && {
             CC="$(command -v cc  || command -v clang   || command -v gcc)" || abort 1 "C Compiler not found."
        }

        [ -z "$CXX" ] && {
            CXX="$(command -v c++ || command -v clang++ || command -v g++)" || abort 1 "C++ Compiler not found."
        }

        [ -z "$AS" ] && {
            AS="$(command -v as)" || abort 1 "command not found: as"
        }

        [ -z "$LD" ] && {
            LD="$(command -v ld)" || abort 1 "command not found: ld"
        }

        [ -z "$AR" ] && {
            AR="$(command -v ar)" || abort 1 "command not found: ar"
        }

        [ -z "$RANLIB" ] && {
            RANLIB="$(command -v ranlib)" || abort 1 "command not found: ranlib"
        }

        CC_ARGS="-fPIC -fno-common"

        # https://gcc.gnu.org/onlinedocs/gcc/Link-Options.html
        LD_ARGS="-Wl,--as-needed"
    fi

    #########################################################################################

    CPP="$CC -E"

    #########################################################################################

    [ "$DEBUG_CC" = 1 ] && CC_ARGS="$CC_ARGS -v"
    [ "$DEBUG_LD" = 1 ] && LD_ARGS="$LD_ARGS -Wl,-v"

    case $PROFILE in
        debug)
            CC_ARGS="$CC_ARGS -O0 -g"
            ;;
        release)
            CC_ARGS="$CC_ARGS -Os"

            if [ "$ENABLE_LTO" = 1 ] ; then
                LD_ARGS="$LD_ARGS -flto"
            fi

            if [ "$NATIVE_PLATFORM_KIND" = darwin ] ; then
                LD_ARGS="$LD_ARGS -Wl,-S"
            else
                LD_ARGS="$LD_ARGS -Wl,-s"
            fi
    esac

    case $NATIVE_PLATFORM_KIND in
         netbsd) LD_ARGS="$LD_ARGS -lpthread" ;;
        openbsd) LD_ARGS="$LD_ARGS -lpthread" ;;
    esac

    #########################################################################################

    PP_ARGS="$PP_ARGS -I$AUX_INCLUDE_DIR"

    LD_ARGS="$LD_ARGS -L$AUX_LIBRARY_DIR"

    PATH="$AUX_INSTALL_DIR/bin:$PATH"

    #########################################################################################

      CFLAGS="$CC_ARGS   $CFLAGS"
    CXXFLAGS="$CC_ARGS $CXXFLAGS"
    CPPFLAGS="$PP_ARGS $CPPFLAGS"
     LDFLAGS="$LD_ARGS  $LDFLAGS"

    #########################################################################################

    for TOOL in CC CXX CPP AS AR RANLIB LD SYSROOT CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
    do
        export "${TOOL}"
    done

    #########################################################################################

    unset LIBS

    # autoreconf --help

    unset AUTOCONF
    unset AUTOHEADER
    unset AUTOM4TE
    unset AUTOMAKE
    unset AUTOPOINT
    unset ACLOCAL
    unset GTKDOCIZE
    unset INTLTOOLIZE
    unset LIBTOOLIZE
    unset M4
    unset MAKE

    # https://stackoverflow.com/questions/18476490/what-is-purpose-of-target-arch-variable-in-makefiles
    unset TARGET_ARCH

    # https://keith.github.io/xcode-man-pages/xcrun.1.html
    unset SDKROOT
}

configure() {
    run cd "$SESSION_DIR"

    if [ -f config/config.sub ] && [ -f config/config.guess ] ; then
        CONFIG_FILE_DIR="$SESSION_DIR/config"
    else
        if [    -d config.git ] ; then
            rm -rf config.git
        fi

        if run git clone --depth 1 https://git.savannah.gnu.org/git/config.git ; then
            CONFIG_FILE_DIR="$SESSION_DIR/config"
        else
            if  run curl -L -o _config.sub   "'https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.sub;hb=HEAD'" &&
                sh _config.sub x86_64-pc-linux &&
                run curl -L -o _config.guess "'https://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=config.guess;hb=HEAD'" &&
                sh _config.guess > /dev/null ; then
                run chmod +x _config.guess
                run chmod +x _config.sub
                run mv _config.guess config.guess
                run mv _config.sub   config.sub
                CONFIG_FILE_DIR="$SESSION_DIR"
            elif run curl -L -o _config.sub   'https://git.savannah.gnu.org/cgit/config.git/plain/config.sub' &&
                sh _config.sub x86_64-pc-linux &&
                run curl -L -o _config.guess 'https://git.savannah.gnu.org/cgit/config.git/plain/config.guess' &&
                sh _config.guess > /dev/null ; then
                run chmod +x _config.guess
                run chmod +x _config.sub
                run mv _config.guess config.guess
                run mv _config.sub   config.sub
                CONFIG_FILE_DIR="$SESSION_DIR"
            else
                CONFIG_FILE_DIR="$NDKPKG_CORE_DIR"
            fi
        fi
    fi

    run cd -

    find -type f -name config.sub   -exec cp -vf "$CONFIG_FILE_DIR/config.sub"   {} \;
    find -type f -name config.guess -exec cp -vf "$CONFIG_FILE_DIR/config.guess" {} \;

    run ./configure "--prefix=$PACKAGE_INSTALL_DIR" "$@"
    run "$GMAKE" "--jobs=$BUILD_NJOBS"
    run "$GMAKE" install
}

install_the_given_package() {
    [ -z "$1" ] && abort 1 "install_the_given_package <PACKAGE-NAME> , <PACKAGE-NAME> is unspecified."

    unset PACKAGE_SRC_URL
    unset PACKAGE_SRC_URI
    unset PACKAGE_SRC_SHA

    unset PACKAGE_DEP_LIB
    unset PACKAGE_DEP_AUX

    unset PACKAGE_DOPATCH
    unset PACKAGE_INSTALL
    unset PACKAGE_DOTWEAK

    package_info_$1

    #########################################################################################

    for PACKAGE_DEPENDENCY in $PACKAGE_DEP_LIB $PACKAGE_DEP_AUX
    do
        (install_the_given_package "$PACKAGE_DEPENDENCY")
    done

    #########################################################################################

    printf '\n%b\n' "${COLOR_PURPLE}=>> $ARG0: install package : $1${COLOR_OFF}"

    #########################################################################################

    if [ "$1" != python3 ] ; then
        PACKAGE_INSTALL_DIR="$AUX_INSTALL_DIR"
    fi

    #########################################################################################

    if [ -f "$PACKAGE_INSTALL_DIR/$1.yml" ] ; then
        note "package '$1' already has been installed, skipped."
        return 0
    fi

    #########################################################################################

    PACKAGE_SRC_FILETYPE="$(filetype_from_url "$PACKAGE_SRC_URL")"
    PACKAGE_SRC_FILENAME="$PACKAGE_SRC_SHA$PACKAGE_SRC_FILETYPE"
    PACKAGE_SRC_FILEPATH="$DOWNLOAD_DIR/$PACKAGE_SRC_FILENAME"

    #########################################################################################

    wfetch "$PACKAGE_SRC_URL" --uri="$PACKAGE_SRC_URI" --sha256="$PACKAGE_SRC_SHA" -o "$PACKAGE_SRC_FILEPATH"

    #########################################################################################

    PACKAGE_WORKING_DIR="$SESSION_DIR/$1"

    #########################################################################################

    run install -d "$PACKAGE_WORKING_DIR/src"
    run cd         "$PACKAGE_WORKING_DIR/src"

    #########################################################################################

    run "$TAR" xf "$PACKAGE_SRC_FILEPATH" --strip-components=1 --no-same-owner

    #########################################################################################

    if [ -n  "$PACKAGE_DOPATCH" ] ; then
        eval "$PACKAGE_DOPATCH"
    fi

    #########################################################################################

    if [ "$DUMP_ENV" = 1 ] ; then
        run export -p
    fi

    #########################################################################################

    if [ -n  "$PACKAGE_INSTALL" ] ; then
        eval "$PACKAGE_INSTALL"
    else
        abort 1 "PACKAGE_INSTALL variable is not set for package '$1'"
    fi

    #########################################################################################

    run cd "$PACKAGE_INSTALL_DIR"

    #########################################################################################

    if [ -n  "$PACKAGE_DOTWEAK" ] ; then
        eval "$PACKAGE_DOTWEAK"
    fi

    #########################################################################################

    run cd "$PACKAGE_INSTALL_DIR"

    #########################################################################################

    PACKAGE_INSTALL_UTS="$(date +%s)"

    cat > "$1.yml" <<EOF
src-url: $PACKAGE_SRC_URL
src-uri: $PACKAGE_SRC_URI
src-sha: $PACKAGE_SRC_SHA
dep-lib: $PACKAGE_DEP_LIB
dep-aux: $PACKAGE_DEP_AUX
install: $PACKAGE_INSTALL
builtat: $PACKAGE_INSTALL_UTS
EOF

    cat > toolchain.txt <<EOF
     CC='$CC'
    CXX='$CXX'
     AS='$AS'
     LD='$LD'
     AR='$AR'
 RANLIB='$RANLIB'
SYSROOT='$SYSROOT'
PROFILE='$PROFILE'
 CFLAGS='$CFLAGS'
LDFLAGS='$LDFLAGS'
EOF
}

package_info_libz() {
    PACKAGE_SRC_URL='https://zlib.net/fossils/zlib-1.3.1.tar.gz'
    PACKAGE_SRC_SHA='9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23'
    PACKAGE_INSTALL='configure --static'
}

package_info_libbz2() {
    PACKAGE_SRC_URL='https://sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz'
    PACKAGE_SRC_SHA='ab5a03176ee106d3f0fa90e381da478ddae405918153cca248e682cd0c4a2269'
    PACKAGE_INSTALL='
    for f in blocksort.c huffman.c crctable.c randtable.c compress.c decompress.c bzlib.c
    do
        o="${f%.c}.o"
        run "$CC" -c "$CFLAGS" "$CPPFLAGS" -D_FILE_OFFSET_BITS=64 -o "$o" "$f"
    done

    run "$AR" crs libbz2.a *.o

    run install -d     "$PACKAGE_INSTALL_DIR/include/"
    run install -d     "$PACKAGE_INSTALL_DIR/lib/"
    run cp -L bzlib.h  "$PACKAGE_INSTALL_DIR/include/"
    run cp -L libbz2.a "$PACKAGE_INSTALL_DIR/lib/"
    '
}

package_info_libexpat() {
    PACKAGE_SRC_URL='https://github.com/libexpat/libexpat/releases/download/R_2_6_3/expat-2.6.3.tar.xz'
    PACKAGE_SRC_SHA='274db254a6979bde5aad404763a704956940e465843f2a9bd9ed7af22e2c0efc'
    PACKAGE_INSTALL='configure --disable-dependency-tracking --enable-static --disable-shared --without-xmlwf --without-tests --without-examples --without-docbook'
}

package_info_liblzma() {
    PACKAGE_SRC_URL='https://github.com/tukaani-project/xz/releases/download/v5.6.3/xz-5.6.3.tar.gz'
    PACKAGE_SRC_SHA='b1d45295d3f71f25a4c9101bd7c8d16cb56348bbef3bbc738da0351e17c73317'
    PACKAGE_INSTALL='configure --disable-dependency-tracking --enable-static --disable-shared --disable-nls --enable-largefile --disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo --disable-lzma-links --disable-scripts --disable-doc'
}

package_info_libgdbm() {
    PACKAGE_SRC_URL='https://ftp.gnu.org/gnu/gdbm/gdbm-1.23.tar.gz'
    PACKAGE_SRC_SHA='74b1081d21fff13ae4bd7c16e5d6e504a4c26f7cde1dca0d963a484174bbcacd'
    PACKAGE_INSTALL='configure --disable-dependency-tracking --enable-static --disable-shared --disable-nls --enable-largefile --enable-libgdbm-compat --without-readline'
    PACKAGE_DOTWEAK='run ln -s ndbm.h include/gdbm-ndbm.h'
}

package_info_libsqlite3() {
    PACKAGE_SRC_URL='https://www.sqlite.org/2024/sqlite-autoconf-3460100.tar.gz'
    PACKAGE_SRC_SHA='67d3fe6d268e6eaddcae3727fce58fcc8e9c53869bdd07a0c61e38ddf2965071'
    PACKAGE_DEP_LIB='libz'
    PACKAGE_INSTALL='configure --disable-dependency-tracking --enable-static --disable-shared --enable-largefile --disable-editline --disable-readline'
}

package_info_libffi() {
    PACKAGE_SRC_URL='https://github.com/libffi/libffi/releases/download/v3.4.6/libffi-3.4.6.tar.gz'
    PACKAGE_SRC_SHA='b0dea9df23c863a7a50e825440f3ebffabd65df1497108e5d437747843895a4e'
    PACKAGE_INSTALL='configure --disable-dependency-tracking --enable-static --disable-shared --disable-docs --disable-symvers'
}

package_info_libiconv() {
    PACKAGE_SRC_URL='https://ftp.gnu.org/gnu/libiconv/libiconv-1.17.tar.gz'
    PACKAGE_SRC_SHA='8f74213b56238c85a50a5329f77e06198771e70dd9a739779f4c02f65d971313'
    PACKAGE_INSTALL='configure --disable-dependency-tracking --enable-static --disable-shared --enable-extra-encodings'
}

package_info_libintl() {
    PACKAGE_SRC_URL='https://ftp.gnu.org/gnu/gettext/gettext-0.22.5.tar.gz'
    PACKAGE_SRC_SHA='ec1705b1e969b83a9f073144ec806151db88127f5e40fe5a94cb6c8fa48996a0'
    PACKAGE_DEP_LIB='libiconv'
    PACKAGE_INSTALL='run cd gettext-runtime && configure --disable-dependency-tracking --enable-static --disable-shared --disable-libasprintf --disable-nls --disable-csharp --disable-java --enable-c++ --enable-nls --with-included-gettext --with-libiconv-prefix="$AUX_INSTALL_DIR"'
}

package_info_libtirpc() {
    PACKAGE_SRC_URL='https://downloads.sourceforge.net/project/libtirpc/libtirpc/1.3.5/libtirpc-1.3.5.tar.bz2'
    PACKAGE_SRC_SHA='9b31370e5a38d3391bf37edfa22498e28fe2142467ae6be7a17c9068ec0bf12f'
    PACKAGE_DEP_LIB='libz'
    PACKAGE_INSTALL='configure --disable-dependency-tracking --enable-static --disable-shared --enable-ipv6 --disable-gssapi'
    PACKAGE_DOPATCH='wfetch "https://raw.githubusercontent.com/leleliu008/sys-queue.h/v1/sys-queue.h" -o "$AUX_INCLUDE_DIR/sys/queue.h"'
}

package_info_libnsl() {
    PACKAGE_SRC_URL='https://github.com/thkukuk/libnsl/releases/download/v2.0.1/libnsl-2.0.1.tar.xz'
    PACKAGE_SRC_SHA='5c9e470b232a7acd3433491ac5221b4832f0c71318618dc6aa04dd05ffcd8fd9'
    PACKAGE_DEP_LIB='libtirpc libintl'
    PACKAGE_DOPATCH='export CPPFLAGS="$CPPFLAGS -I$AUX_INCLUDE_DIR/tirpc"'
    PACKAGE_INSTALL='configure --disable-dependency-tracking --enable-static --disable-shared'
}

package_info_libopenssl() {
    PACKAGE_SRC_URL='https://www.openssl.org/source/openssl-3.4.0.tar.gz'
    PACKAGE_SRC_URI='https://github.com/openssl/openssl/releases/download/openssl-3.4.0/openssl-3.4.0.tar.gz'
    PACKAGE_SRC_SHA='e15dda82fe2fe8139dc2ac21a36d4ca01d5313c75f99f46c4e8a27709b7294bf'
    PACKAGE_DEP_AUX='perl'
    PACKAGE_INSTALL='run ./config "--prefix=$PACKAGE_INSTALL_DIR" no-shared no-tests no-ssl3 no-ssl3-method no-zlib --libdir=lib --openssldir=etc/ssl && run "$GMAKE" build_libs "--jobs=$BUILD_NJOBS" && run "$GMAKE" install_dev'
    # https://github.com/openssl/openssl/blob/master/INSTALL.md
}

package_info_libncurses() {
    PACKAGE_SRC_URL='https://ftp.gnu.org/gnu/ncurses/ncurses-6.5.tar.gz'
    PACKAGE_SRC_SHA='136d91bc269a9a5785e5f9e980bc76ab57428f604ce3e5a5a90cebc767971cc6'
    PACKAGE_DOPATCH='
unset TERMINFO
export LDCONFIG=true'
    PACKAGE_INSTALL='configure \
        --with-pkg-config-libdir="$PACKAGE_INSTALL_DIR/lib/pkgconfig" \
        --without-ada \
        --without-tests \
        --without-debug \
        --without-shared \
        --without-valgrind \
        --enable-const \
        --enable-widec \
        --enable-termcap \
        --enable-warnings \
        --enable-pc-files \
        --enable-ext-mouse \
        --enable-ext-colors \
        --disable-stripping \
        --disable-assertions \
        --disable-gnat-projects \
        --disable-echo'
    PACKAGE_DOTWEAK='
for f in curses.h ncurses.h form.h menu.h panel.h term.h termcap.h
do
    ln -s "ncursesw/$f" "include/$f"
done

for item in libncurses libpanel libmenu libform
do
    ln -s "${item}w.a" "lib/${item}.a"
done

ln -s libncurses++w.a lib/libncurses++.a

ln -s ncursesw.pc lib/pkgconfig/ncurses.pc'
}

package_info_libedit() {
    PACKAGE_SRC_URL='https://thrysoee.dk/editline/libedit-20240808-3.1.tar.gz'
    PACKAGE_SRC_SHA='5f0573349d77c4a48967191cdd6634dd7aa5f6398c6a57fe037cc02696d6099f'
    PACKAGE_DEP_LIB='libncurses'
    PACKAGE_INSTALL='configure --disable-dependency-tracking --enable-static --disable-shared --disable-examples'
    PACKAGE_DOTWEAK='run ln -s libedit.a lib/libreadline.a'
}

package_info_libuuid() {
    PACKAGE_SRC_URL='https://mirrors.edge.kernel.org/pub/linux/utils/util-linux/v2.40/util-linux-2.40.4.tar.xz'
    PACKAGE_SRC_SHA='5c1daf733b04e9859afdc3bd87cc481180ee0f88b5c0946b16fdec931975fb79'
    PACKAGE_DEP_AUX='automake libtool'
    PACKAGE_INSTALL='configure \
        --without-python \
        --without-systemd \
        --enable-widechar \
        --enable-libuuid \
        --enable-static \
        --disable-shared \
        --disable-all-programs \
        --disable-bash-completion \
        --disable-use-tty-group \
        --disable-chfn-chsh \
        --disable-login \
        --disable-su \
        --disable-runuser \
        --disable-makeinstall-chown \
        --disable-makeinstall-setuid'

    if [ "$NATIVE_PLATFORM_KIND" = darwin ] ; then
        PACKAGE_DOPATCH='
        wfetch 'https://github.com/util-linux/util-linux/commit/9445f477cfcfb3615ffde8f93b1b98c809ee4eca.patch?full_index=1' -o patch.diff
        patch -p1 < patch.diff
        '
    fi

    PACKAGE_DOTWEAK='run ln -s uuid/uuid.h include/uuid.h'
}

package_info_perl() {
    PACKAGE_SRC_URL='https://cpan.metacpan.org/authors/id/P/PE/PEVANS/perl-5.38.2.tar.xz'
    PACKAGE_SRC_URI='https://distfiles.macports.org/perl5.38/perl-5.38.2.tar.xz'
    PACKAGE_SRC_SHA='d91115e90b896520e83d4de6b52f8254ef2b70a8d545ffab33200ea9f1cf29e8'
    PACKAGE_INSTALL='run ./Configure "-Dprefix=$PACKAGE_INSTALL_DIR" -Dman1dir=none -Dman3dir=none -des -Dmake=gmake -Duselargefiles -Duseshrplib -Dusethreads -Dusenm=false -Dusedl=true && run "$GMAKE" "--jobs=$BUILD_NJOBS" && run "$GMAKE" install'
}

package_info_autoconf() {
    PACKAGE_SRC_URL='https://ftp.gnu.org/gnu/autoconf/autoconf-2.71.tar.gz'
    PACKAGE_SRC_SHA='431075ad0bf529ef13cb41e9042c542381103e80015686222b8a9d4abef42a1c'
    PACKAGE_DEP_AUX='perl gm4'
    PACKAGE_INSTALL='configure'
}

package_info_automake() {
    PACKAGE_SRC_URL='https://ftp.gnu.org/gnu/automake/automake-1.16.5.tar.xz'
    PACKAGE_SRC_SHA='f01d58cd6d9d77fbdca9eb4bbd5ead1988228fdb73d6f7a201f5f8d6b118b469'
    PACKAGE_DEP_AUX='autoconf'
    PACKAGE_INSTALL='configure'
}

package_info_libtool() {
    PACKAGE_SRC_URL='https://ftp.gnu.org/gnu/libtool/libtool-2.4.7.tar.xz'
    PACKAGE_SRC_SHA='4f7f217f057ce655ff22559ad221a0fd8ef84ad1fc5fcb6990cecc333aa1635d'
    PACKAGE_INSTALL='configure --enable-ltdl-install'
    PACKAGE_DEP_AUX='gm4'
    PACKAGE_DOTWEAK='
run ln -s libtool    bin/glibtool
run ln -s libtoolize bin/glibtoolize
'
}

package_info_gm4() {
    PACKAGE_SRC_URL='https://ftp.gnu.org/gnu/m4/m4-1.4.19.tar.xz'
    PACKAGE_SRC_SHA='63aede5c6d33b6d9b13511cd0be2cac046f2e70fd0a07aa9573a04a82783af96'
    PACKAGE_INSTALL='configure'
}

package_info_libxcrypt() {
    PACKAGE_SRC_URL='https://github.com/besser82/libxcrypt/releases/download/v4.4.36/libxcrypt-4.4.36.tar.xz'
    PACKAGE_SRC_SHA='e5e1f4caee0a01de2aee26e3138807d6d3ca2b8e67287966d1fefd65e1fd8943'
    PACKAGE_DEP_AUX='perl'
    PACKAGE_DOPATCH='export LDFLAGS="-static $LDFLAGS"'
    PACKAGE_INSTALL='configure --disable-dependency-tracking --enable-obsolete-api=glibc --disable-xcrypt-compat-files --disable-failure-tokens --disable-valgrind'
}

package_info_python3() {
    case $PYTHON_EDITION in
        3.9)
            PACKAGE_SRC_URL='https://www.python.org/ftp/python/3.9.21/Python-3.9.21.tgz'
            PACKAGE_SRC_SHA='3126f59592c9b0d798584755f2bf7b081fa1ca35ce7a6fea980108d752a05bb1'
            ;;
        3.10)
            PACKAGE_SRC_URL='https://www.python.org/ftp/python/3.10.16/Python-3.10.16.tgz'
            PACKAGE_SRC_SHA='f2e22ed965a93cfeb642378ed6e6cdbc127682664b24123679f3d013fafe9cd0'
            ;;
        3.11)
            PACKAGE_SRC_URL='https://www.python.org/ftp/python/3.11.11/Python-3.11.11.tgz'
            PACKAGE_SRC_SHA='883bddee3c92fcb91cf9c09c5343196953cbb9ced826213545849693970868ed'
            ;;
        3.12)
            PACKAGE_SRC_URL='https://www.python.org/ftp/python/3.12.8/Python-3.12.8.tgz'
            PACKAGE_SRC_SHA='5978435c479a376648cb02854df3b892ace9ed7d32b1fead652712bee9d03a45'
            ;;
        3.13)
            PACKAGE_SRC_URL='https://www.python.org/ftp/python/3.13.1/Python-3.13.1.tgz'
            PACKAGE_SRC_SHA='1513925a9f255ef0793dbf2f78bb4533c9f184bdd0ad19763fd7f47a400a7c55'
            ;;
        *)  abort 1 "unsupported python edition: $PYTHON_EDITION"
    esac

    PACKAGE_DEP_LIB='libz libbz2 liblzma libgdbm libexpat libsqlite3 libffi libopenssl libedit'

    case $NATIVE_PLATFORM_KIND in
        darwin) PACKAGE_DEP_LIB="$PACKAGE_DEP_LIB libuuid" ;;
         linux) PACKAGE_DEP_LIB="$PACKAGE_DEP_LIB libuuid libnsl libxcrypt"
    esac

    PACKAGE_INSTALL='configure --with-system-expat --with-system-ffi --with-readline=editline --with-openssl=$PACKAGE_INSTALL_DIR --with-ensurepip=yes --with-lto --enable-ipv6 --enable-static --disable-shared --enable-largefile --disable-option-checking --disable-nls --disable-debug --enable-loadable-sqlite-extensions --disable-profiling py_cv_module__tkinter=disabled'
    PACKAGE_DOPATCH='
gsed -n -E "s/^#([a-z_\*].*)$/\1/p"  Modules/Setup > Modules/Setup.local
gsed -i "s|shared|static|"       Modules/Setup.local
gsed -i "/^_tkinter /d"          Modules/Setup.local
gsed -i "/^_testinternalcapi/d"  Modules/Setup.local
gsed -i "s/-ltermcap/-lncurses/" Modules/Setup.local

unset NATIVE_PLATFORM_KIND_DARWIN

case $NATIVE_PLATFORM_KIND in
    linux)
        gsed -i "s/-lnsl/-lnsl -lintl -liconv/" Modules/Setup.local
        ;;
    darwin)
        NATIVE_PLATFORM_KIND_DARWIN=1

        printf "!<arch>\n" > "$AUX_LIBRARY_DIR/librt.a"
        printf "!<arch>\n" > "$AUX_LIBRARY_DIR/libcrypt.a"

        gsed -i "/ossaudiodev/d" Modules/Setup.local
        gsed -i "/spwdmodule/d"  Modules/Setup.local
        gsed -i "/nismodule/d"   Modules/Setup.local
        ;;
    dragonfly)
        printf "!<arch>\n" > "$AUX_LIBRARY_DIR/libuuid.a"

        gsed -i "/spwdmodule/d"  Modules/Setup.local
        gsed -i "/nismodule/d"   Modules/Setup.local
        gsed -i "s/-luuid//"     Modules/Setup.local
        ;;
    openbsd)
        printf "!<arch>\n" > "$AUX_LIBRARY_DIR/libdl.a"
        printf "!<arch>\n" > "$AUX_LIBRARY_DIR/librt.a"
        printf "!<arch>\n" > "$AUX_LIBRARY_DIR/libcrypt.a"
        printf "!<arch>\n" > "$AUX_LIBRARY_DIR/libuuid.a"

        gsed -i "/ossaudiodev/d" Modules/Setup.local
        gsed -i "/spwdmodule/d"  Modules/Setup.local
        gsed -i "/nismodule/d"   Modules/Setup.local
        gsed -i "s/-luuid//"     Modules/Setup.local
        ;;
    *bsd)
        printf "!<arch>\n" > "$AUX_LIBRARY_DIR/libdl.a"
        printf "!<arch>\n" > "$AUX_LIBRARY_DIR/libuuid.a"

        gsed -i "/spwdmodule/d"  Modules/Setup.local
        gsed -i "/nismodule/d"   Modules/Setup.local
        gsed -i "s/-luuid//"     Modules/Setup.local
        ;;
esac

unset PYTHONHOME
unset PYTHONPATH

if [ "$REQUEST_TO_CREATE_FULLY_STATICALLY_LINKED_EXECUTABLE" = 1 ] ; then
    if [ "$NATIVE_PLATFORM_KIND_DARWIN" != 1 ] ; then
        export LDFLAGS="$LDFLAGS -static"
    fi
fi

export CPPFLAGS="$CPPFLAGS -I$AUX_INCLUDE_DIR/tirpc"

export ZLIB_CFLAGS="-I$AUX_INCLUDE_DIR"
export ZLIB_LIBS="-L$AUX_LIBRARY_DIR -lz"

export BZIP2_CFLAGS="-I$AUX_INCLUDE_DIR"
export BZIP2_LIBS="-L$AUX_LIBRARY_DIR -lbz2"

export LIBLZMA_CFLAGS="-I$AUX_INCLUDE_DIR"
export LIBLZMA_LIBS="-L$AUX_LIBRARY_DIR -llzma"

export LIBSQLITE3_CFLAGS="-I$AUX_INCLUDE_DIR"
export LIBSQLITE3_LIBS="-L$AUX_LIBRARY_DIR -lsqlite3"

export LIBUUID_CFLAGS="-I$AUX_INCLUDE_DIR"
export LIBUUID_LIBS="-L$AUX_LIBRARY_DIR -luuid"

export LIBNSL_CFLAGS="-I$AUX_INCLUDE_DIR"
export LIBNSL_LIBS="-L$AUX_LIBRARY_DIR -lnsl -ltirpc"

export GDBM_CFLAGS="-I$AUX_INCLUDE_DIR"
export GDBM_LIBS="-L$AUX_LIBRARY_DIR -lgdbm -lgdbm_compat"

export OPENSSL_INCLUDES="-I$AUX_INCLUDE_DIR"
export OPENSSL_LDFLAGS="-L$AUX_LIBRARY_DIR"
export OPENSSL_LIBS="-lssl -lcrypto -lpthread -ldl"

export LIBS=-lm'
}


help() {
    printf '%b\n' "\
${COLOR_GREEN}A self-contained and relocatable CPython distribution builder${COLOR_OFF}

${COLOR_GREEN}$ARG0 --help${COLOR_OFF}
${COLOR_GREEN}$ARG0 -h${COLOR_OFF}
    show help of this command.

${COLOR_GREEN}$ARG0 config${COLOR_OFF}
    show config.

${COLOR_GREEN}$ARG0 install <PYTHON-EDITION> [OPTIONS]${COLOR_OFF}
    Influential environment variables: TAR, GMAKE, CC, CXX, AS, LD, AR, RANLIB, CFLAGS, CXXFLAGS, CPPFLAGS, LDFLAGS

    PYTHON-EDITION: 3.9, 3.10, 3.11, 3.12, 3.13

    OPTIONS:
        ${COLOR_BLUE}--prefix=<DIR>${COLOR_OFF}
            specify where to be installed into.

        ${COLOR_BLUE}--session-dir=<DIR>${COLOR_OFF}
            specify the session directory.

        ${COLOR_BLUE}--download-dir=<DIR>${COLOR_OFF}
            specify the download directory.

        ${COLOR_BLUE}--profile=<debug|release>${COLOR_OFF}
            specify the build profile.

            debug:
                  CFLAGS: -O0 -g
                CXXFLAGS: -O0 -g

            release:
                  CFLAGS: -Os
                CXXFLAGS: -Os
                CPPFLAGS: -DNDEBUG
                 LDFLAGS: -flto -Wl,-s

        ${COLOR_BLUE}-j <N>${COLOR_OFF}
            specify the number of jobs you can run in parallel.

        ${COLOR_BLUE}-E${COLOR_OFF}
            export compile_commands.json

        ${COLOR_BLUE}-K${COLOR_OFF}
            keep the session directory even if this packages are successfully installed.

        ${COLOR_BLUE}-x${COLOR_OFF}
            debug current running shell.

        ${COLOR_BLUE}-q${COLOR_OFF}
            silent mode. no any messages will be output to terminal.

        ${COLOR_BLUE}-v${COLOR_OFF}
            verbose mode. many messages will be output to terminal.

            This option is equivalent to -v-* options all are supplied.

        ${COLOR_BLUE}-vv${COLOR_OFF}
            very verbose mode. many many messages will be output to terminal.

            This option is equivalent to -v-* options all are supplied.

        ${COLOR_BLUE}-v-env${COLOR_OFF}
            show all environment variables before starting to build.

        ${COLOR_BLUE}-v-http${COLOR_OFF}
            show http request/response.

        ${COLOR_BLUE}-v-gmake${COLOR_OFF}
            pass V=1 argument to gmake command.

        ${COLOR_BLUE}-v-cc${COLOR_OFF}
            pass -v argument to the C/C++ compiler.

        ${COLOR_BLUE}-v-ld${COLOR_OFF}
            pass -v argument to the linker.
"
}

show_config() {
    unset PACKAGE_SRC_URL
    unset PACKAGE_SRC_URI
    unset PACKAGE_SRC_SHA

    unset PACKAGE_DEP_LIB
    unset PACKAGE_DEP_AUX

    unset PACKAGE_DOPATCH
    unset PACKAGE_INSTALL
    unset PACKAGE_DOTWEAK

    package_info_$1

    cat <<EOF
$1:
    src-url: $PACKAGE_SRC_URL
    src-sha: $PACKAGE_SRC_SHA

EOF

    for DEP_PKG_NAME in $PACKAGE_DEP_LIB
    do
        (show_config "$DEP_PKG_NAME")
    done
}

ARG0="$0"

case $1 in
    ''|--help|-h)
        help
        ;;
    python-version)
        shift
        [ -z "$1" ] && abort 1 '$ARG0 python-version <PYTHON-EDITION>, <PYTHON-EDITION> is unspecified. It can be 3.13, 3.12, 3.11, 3.10, 3.9'
        PYTHON_EDITION="$1"

        unset PACKAGE_SRC_URL

        package_info_python3

        PACKAGE_SRC_FILENAME="${PACKAGE_SRC_URL##*/}"
        PACKAGE_SRC_FILENAME_PREFIX="${PACKAGE_SRC_FILENAME%.tgz}"
        PACKAGE_VERSION="${PACKAGE_SRC_FILENAME_PREFIX##*-}"

        printf '%s\n' "$PACKAGE_VERSION"
        ;;
    config)
        shift
        [ -z "$1" ] && abort 1 '$ARG0 config <PYTHON-EDITION>, <PYTHON-EDITION> is unspecified. It can be 3.13, 3.12, 3.11, 3.10, 3.9'
        PYTHON_EDITION="$1"
        show_config python3
        ;;
    install)
        shift

        inspect_install_arguments "$@"

        install_the_given_package python3

        ######################################################

        run cd lib

        LIBPYTHON_FILENAME="libpython$PYTHON_EDITION.a"

        LIBPYTHON_FILEPATH="$(find "python$PYTHON_EDITION" -maxdepth 2 -mindepth 2 -type f -name "$LIBPYTHON_FILENAME")"

        run ln -sf "../../$LIBPYTHON_FILENAME" "$LIBPYTHON_FILEPATH"

        run rm -rf python$PYTHON_EDITION/test/

        find -depth -type d -name '__pycache__' -exec rm -rfv {} +

        gsed -i "/^prefix=/c prefix=\${pcfiledir}/../.." pkgconfig/*.pc

        ######################################################

        run cd ../bin

        if [ -f 2to3 ] ; then
            run ln -sf 2to3-$PYTHON_EDITION 2to3
        fi

        for item in idle pip pydoc
        do
            run ln -sf "${item}${PYTHON_EDITION}" "${item}${PYTHON_EDITION%%.*}"
        done

        for f in *
        do
            [ -L "$f" ] && continue

            X="$(head -c2 "$f")"

            if [ "$X" = '#!' ] ; then
                Y="$(head -n 1 "$f")"

                case "$Y" in
                    */bin/python3*)
                        gsed -i '1c #!/usr/bin/env python3' "$f"
                esac
            fi
        done

        ######################################################

        if [ "$REQUEST_TO_KEEP_SESSION_DIR" != 1 ] ; then
            rm -rf "$SESSION_DIR"
        fi
        ;;
    *)  abort 1 "unrecognized argument: $1"
esac
