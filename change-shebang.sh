#!/bin/sh

set -e

cd bin

for f in *
do
    [ -L "$f" ] && continue

    X="$(head -c2 "$f")"

    if [ "$X" = '#!' ] ; then
        Y="$(head -n 1 "$f")"

        case "$Y" in
            */bin/python3*)
                sed -i '1c #!/usr/bin/env python3' "$f"
        esac
    fi
done
