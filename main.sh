#!/usr/bin/env bash

(( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3 || BASH_VERSINFO[0] > 4 )) || {
    printf "argbarse requires Bash 4.3+\n" >&2
    return 1 2>/dev/null
    # shellcheck disable=SC2317 # it's reachable
    exit 1
}

declare -rp ARGBARSE_VERSION >/dev/null 2>&1 && return >/dev/null 2>&1
declare -r ARGBARSE_VERSION="0.1.0"

#@BUNDLED_BOBJECT@


