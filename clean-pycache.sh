#!/bin/sh
find -depth -type d -name '__pycache__' -exec rm -rfv {} +
