#!/usr/bin/env bash
set -euo pipefail
root=${1:?Usage: fetch-segger.sh VENDOR_DIRECTORY}

fetch() {
    local repo=$1 revision=$2 destination="$root/$1"
    if [[ ! -d "$destination/.git" ]]; then
        mkdir -p "$destination"
        git -C "$destination" init -q
        git -C "$destination" remote add origin "https://github.com/SEGGERMicro/$repo.git"
    fi
    if ! git -C "$destination" cat-file -e "$revision^{commit}" 2>/dev/null; then
        git -C "$destination" fetch --depth 1 origin "$revision"
    fi
    git -C "$destination" checkout --detach "$revision"
}

fetch SystemView 92ca7a810c5765ba64911919acd511c61b6b083f
fetch RTT 9106eaa39babe53e00994d7828c1afb29390cdc1
