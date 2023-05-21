#!/usr/bin/env bash

(( BASH_VERSINFO[0] < 4 || BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3 )) && {
    printf "argbarse requires Bash >= 4.3 in order to run!\n" >&2
    exit 1
}

declare -rp SOURCE_VERSION >/dev/null 2>&1 || {
    printf "Make sure bash-source (source.sh) is loaded!\n" >&2
    exit 1
}

# Make sure argbarse is not loaded again
declare -rp ARGBARSE_LOADED >/dev/null 2>&1 &&
    return 0
declare -r ARGBARSE_LOADED=1

# shellcheck disable=SC1091 # we use source.sh
source "argbarse/init"
