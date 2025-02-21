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
    run $sudo pkg install -y curl libnghttp2 coreutils findutils gsed gmake gcc

    run $sudo ln -sf /usr/local/bin/gln        bin/ln
    run $sudo ln -sf /usr/local/bin/gsed       bin/sed
    run $sudo ln -sf /usr/local/bin/gfind      bin/find
    run $sudo ln -sf /usr/local/bin/gmake      bin/make
    run $sudo ln -sf /usr/local/bin/gstat      bin/stat
    run $sudo ln -sf /usr/local/bin/gdate      bin/date
    run $sudo ln -sf /usr/local/bin/ghead      bin/head
    run $sudo ln -sf /usr/local/bin/gnproc     bin/nproc
    run $sudo ln -sf /usr/local/bin/gbase64    bin/base64
    run $sudo ln -sf /usr/local/bin/gunlink    bin/unlink
    run $sudo ln -sf /usr/local/bin/ginstall   bin/install
    run $sudo ln -sf /usr/local/bin/grealpath  bin/realpath
    run $sudo ln -sf /usr/local/bin/gsha256sum bin/sha256sum
}

__setup_openbsd() {
    run $sudo pkg_add curl coreutils findutils gsed gmake gcc%11 libarchive

    run $sudo ln -sf /usr/local/bin/gln        bin/ln
    run $sudo ln -sf /usr/local/bin/gsed       bin/sed
    run $sudo ln -sf /usr/local/bin/gfind      bin/find
    run $sudo ln -sf /usr/local/bin/gmake      bin/make
    run $sudo ln -sf /usr/local/bin/gstat      bin/stat
    run $sudo ln -sf /usr/local/bin/gdate      bin/date
    run $sudo ln -sf /usr/local/bin/ghead      bin/head
    run $sudo ln -sf /usr/local/bin/gnproc     bin/nproc
    run $sudo ln -sf /usr/local/bin/gbase64    bin/base64
    run $sudo ln -sf /usr/local/bin/gunlink    bin/unlink
    run $sudo ln -sf /usr/local/bin/ginstall   bin/install
    run $sudo ln -sf /usr/local/bin/grealpath  bin/realpath
    run $sudo ln -sf /usr/local/bin/gsha256sum bin/sha256sum
}

__setup_netbsd() {
    run $sudo pkgin -y update
    run $sudo pkgin -y install curl coreutils findutils gsed gmake bsdtar

    run $sudo ln -sf /usr/pkg/bin/gln        bin/ln
    run $sudo ln -sf /usr/pkg/bin/gsed       bin/sed
    run $sudo ln -sf /usr/pkg/bin/gfind      bin/find
    run $sudo ln -sf /usr/pkg/bin/gmake      bin/make
    run $sudo ln -sf /usr/pkg/bin/gstat      bin/stat
    run $sudo ln -sf /usr/pkg/bin/gdate      bin/date
    run $sudo ln -sf /usr/pkg/bin/ghead      bin/head
    run $sudo ln -sf /usr/pkg/bin/gnproc     bin/nproc
    run $sudo ln -sf /usr/pkg/bin/gbase64    bin/base64
    run $sudo ln -sf /usr/pkg/bin/gunlink    bin/unlink
    run $sudo ln -sf /usr/pkg/bin/ginstall   bin/install
    run $sudo ln -sf /usr/pkg/bin/grealpath  bin/realpath
    run $sudo ln -sf /usr/pkg/bin/gsha256sum bin/sha256sum
}

__setup_macos() {
    run brew install coreutils findutils gnu-sed make

    run ln -sf `command -v gsed`       bin/sed
    run ln -sf `command -v gfind`      bin/find
}

__setup_linux() {
    . /etc/os-release

    case $ID in
        ubuntu)
            run $sudo apt-get -y update
            run $sudo apt-get -y install curl sed vim findutils libarchive-tools make g++ patchelf
            run $sudo ln -sf /usr/bin/make bin/gmake
            run $sudo ln -sf /usr/bin/sed  bin/gsed
            ;;
        alpine)
            run $sudo apk update
            run $sudo apk add curl sed vim findutils libarchive-tools make g++ libc-dev linux-headers patchelf
            run $sudo ln -sf /usr/bin/make bin/gmake
            run $sudo ln -sf     /bin/sed  bin/gsed
    esac
}

unset IFS

unset sudo

[ "$(id -u)" -eq 0 ] || sudo=sudo

TARGET_OS_KIND="${2%%-*}"

######################################################

install -d bin/

__setup_$TARGET_OS_KIND

export PATH="$PWD/bin:$PATH"

######################################################

PREFIX="python-$1-$2"

run $sudo install -d -g `id -g` -o `id -u` "$PREFIX"

[ -f cacert.pem ] && run export SSL_CERT_FILE="$PWD/cacert.pem"

######################################################

PYTHON_EDITION="${1%.*}"

run ./build.sh install "$PYTHON_EDITION" --prefix="$PREFIX"

run cp *.sh "$PREFIX/"

######################################################

run cd "$PREFIX/lib"

LIBPYTHON_FILENAME="libpython$PYTHON_EDITION.a"

LIBPYTHON_FILEPATH="$(find "python$PYTHON_EDITION" -maxdepth 2 -mindepth 2 -type f -name "$LIBPYTHON_FILENAME")"

run ln -sf "../../$LIBPYTHON_FILENAME" "$LIBPYTHON_FILEPATH"

run rm -rf python$PYTHON_EDITION/test/

gsed -i '1c #!/usr/bin/env python3' "${LIBPYTHON_FILEPATH%/*}/python-config.py"

gsed -i '/^prefix=/c prefix=${pcfiledir}/../..' pkgconfig/*.pc

find -depth -type d -name __pycache__ -exec rm -rfv {} +

######################################################

run cd -
run cd "$PREFIX/bin"

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

run cd -

######################################################

if [ "$TARGET_OS_KIND" = linux ] ; then
    run cd "$PREFIX"
    run ./linux-portable.sh
    run cd -
fi

######################################################

run bsdtar cvaf "$PREFIX.tar.xz" "$PREFIX"
