#!/bin/sh

set -e

COLOR_GREEN='\033[0;32m'        # Green
COLOR_PURPLE='\033[0;35m'       # Purple
COLOR_OFF='\033[0m'             # Reset

echo() {
    printf '%b\n' "$*"
}

run() {
    echo "${COLOR_PURPLE}==>${COLOR_OFF} ${COLOR_GREEN}$@${COLOR_OFF}"
    eval "$@"
}

__setup_dragonflybsd() {
__setup_freebsd
}

__setup_freebsd() {
    run $sudo pkg install -y curl libnghttp2 coreutils gmake gcc

    run $sudo ln -sf /usr/local/bin/gln        /usr/bin/ln
    run $sudo ln -sf /usr/local/bin/gmake      /usr/bin/make
    run $sudo ln -sf /usr/local/bin/gstat      /usr/bin/stat
    run $sudo ln -sf /usr/local/bin/gdate      /usr/bin/date
    run $sudo ln -sf /usr/local/bin/gnproc     /usr/bin/nproc
    run $sudo ln -sf /usr/local/bin/gbase64    /usr/bin/base64
    run $sudo ln -sf /usr/local/bin/gunlink    /usr/bin/unlink
    run $sudo ln -sf /usr/local/bin/ginstall   /usr/bin/install
    run $sudo ln -sf /usr/local/bin/grealpath  /usr/bin/realpath
    run $sudo ln -sf /usr/local/bin/gsha256sum /usr/bin/sha256sum
}

__setup_openbsd() {
    run $sudo pkg_add coreutils gmake gcc%11 libarchive

    run $sudo ln -sf /usr/local/bin/gln        /usr/bin/ln
    run $sudo ln -sf /usr/local/bin/gmake      /usr/bin/make
    run $sudo ln -sf /usr/local/bin/gstat      /usr/bin/stat
    run $sudo ln -sf /usr/local/bin/gdate      /usr/bin/date
    run $sudo ln -sf /usr/local/bin/gnproc     /usr/bin/nproc
    run $sudo ln -sf /usr/local/bin/gbase64    /usr/bin/base64
    run $sudo ln -sf /usr/local/bin/gunlink    /usr/bin/unlink
    run $sudo ln -sf /usr/local/bin/ginstall   /usr/bin/install
    run $sudo ln -sf /usr/local/bin/grealpath  /usr/bin/realpath
    run $sudo ln -sf /usr/local/bin/gsha256sum /usr/bin/sha256sum
}

__setup_netbsd() {
    run $sudo pkgin -y update
    run $sudo pkgin -y install coreutils gmake bsdtar

    run $sudo ln -sf /usr/pkg/bin/gln        /usr/bin/ln
    run $sudo ln -sf /usr/pkg/bin/gmake      /usr/bin/make
    run $sudo ln -sf /usr/pkg/bin/gstat      /usr/bin/stat
    run $sudo ln -sf /usr/pkg/bin/gdate      /usr/bin/date
    run $sudo ln -sf /usr/pkg/bin/gnproc     /usr/bin/nproc
    run $sudo ln -sf /usr/pkg/bin/gbase64    /usr/bin/base64
    run $sudo ln -sf /usr/pkg/bin/gunlink    /usr/bin/unlink
    run $sudo ln -sf /usr/pkg/bin/ginstall   /usr/bin/install
    run $sudo ln -sf /usr/pkg/bin/grealpath  /usr/bin/realpath
    run $sudo ln -sf /usr/pkg/bin/gsha256sum /usr/bin/sha256sum
}

__setup_macos() {
    run brew install coreutils make
}

__setup_linux() {
    . /etc/os-release

    case $ID in
        ubuntu)
            run $sudo apt-get -y update
            run $sudo apt-get -y install curl libarchive-tools make g++ patchelf
            run $sudo ln -sf /usr/bin/make /usr/bin/gmake
            ;;
        alpine)
            run $sudo apk update
            run $sudo apk add libarchive-tools make g++ libc-dev linux-headers patchelf
    esac
}

unset IFS

unset sudo

[ "$(id -u)" -eq 0 ] || sudo=sudo

TARGET_OS_KIND="${2%%-*}"

__setup_$TARGET_OS_KIND

PREFIX="python-$1-$2"

PYTHON_EDITION="${1%.*}"

run $sudo install -d -g `id -g -n` -o `id -u -n` "$PREFIX"

[ -f cacert.pem ] && run export SSL_CERT_FILE="$PWD/cacert.pem"

run ./build.sh install "$PYTHON_EDITION" --prefix="$PREFIX"

run cp build.sh pack.sh "$PREFIX/"

if [ "$TARGET_OS_KIND" = linux ] ; then
    run mv python.c "$PREFIX/bin/"

    run cd "$PREFIX/bin/"

    run install -d ../runtime/

    run mv "python$PYTHON_EDITION" "python$PYTHON_EDITION.exe"

    run chmod -x "python$PYTHON_EDITION.exe"

    DYNAMIC_LOADER_PATH="$(patchelf --print-interpreter "python$PYTHON_EDITION.exe")"
    DYNAMIC_LOADER_NAME="${DYNAMIC_LOADER_PATH##*/}"

    sed -i "s|ld-linux-x86-64.so.2|$DYNAMIC_LOADER_NAME|" python.c

    run gcc -static -std=gnu99 -Os -flto -s -o "python$PYTHON_EDITION" python.c

    NEEDEDs="$(patchelf --print-needed "python$PYTHON_EDITION.exe")"

    for NEEDED_FILENAME in $NEEDEDs
    do
        NEEDED_FILEPATH="$(gcc -print-file-name="$NEEDED_FILENAME")"
        run cp -L "$NEEDED_FILEPATH" ../runtime/
    done

    run cd -
fi

run bsdtar cvaPf "$PREFIX.tar.xz" "$PREFIX"
