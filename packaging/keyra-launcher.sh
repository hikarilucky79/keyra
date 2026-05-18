#!/bin/sh
# Keyra Flatpak Launcher
export LD_LIBRARY_PATH="/app/bin/lib:$LD_LIBRARY_PATH"

if ! pgrep -x "keyra-daemon" > /dev/null; then
    /app/bin/keyra-daemon &
fi

cd /app/bin
exec ./keyra_app "$@"
