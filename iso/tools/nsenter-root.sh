#!/bin/bash
# Run a command as fake root inside a user namespace (uids mapped from /etc/subuid).
# usage: nsenter-root.sh <command...>
exec unshare --map-auto --map-root-user --mount --pid --fork --kill-child "$@"
