#!/usr/bin/env bash

source log.sh
LOG_FILE=log.txt

(( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3 || BASH_VERSINFO[0] > 4 )) || {
    printf "argbarse requires Bash 4.3+\n" >&2
    return 1 2>/dev/null
    # shellcheck disable=SC2317 # it's reachable
    exit 1
}

declare -rp ARGBARSE_VERSION >/dev/null 2>&1 && return >/dev/null 2>&1
declare -r ARGBARSE_VERSION="0.1.0"

#@BUNDLED_BOBJECT@

__mangle() {
    local -a mangled=("__")
    for n in $(seq 1 "${#1}"); do
        local char="${n:0:$n}"
        mangled+=("$(printf %x "'$char")")
    done
    local old="$IFS"
    IFS=''
    echo "${mangled[*]}"
    IFS="$old"
}

argbarse_option() {
    local -A parsed_args=()
    local n_arg=0
    while (( $# > 0 )); do
        case "$1" in
        --args=*)
            parsed_args[args]="${1#*=}"
            ;;
        --args)
            shift
            parsed_args[args]="$1"
            ;;
        -*)
            printf -v func_error "invalid option '%s'" "$1" >&2
            return 1
            ;;
        *)
            local -n parser="$(__mangle "$1")"; shift
            IFS=' ' read -ra opts <<< "$1"
            ;;
        esac
        shift
    done

    
}

argbarse() {
    local -A parsed_args=()
    while (( $# > 0 )); do
        case "$1" in
        --name=*)
            parsed_args[name]="${1#*=}"
            ;;
        --name)
            shift
            parsed_args[name]="$1"
            ;;
        --description=*)
            parsed_args[description]="${1#*=}"
            ;;
        --description)
            shift
            parsed_args[description]="$1"
            ;;
        --epilog=*)
            parsed_args[epilog]="${1#*=}"
            ;;
        --epilog)
            shift
            parsed_args[epilog]="$1"
            ;;
        -*)
            printf -v func_error "invalid option '%s'" "$1" >&2
            return 1
            ;;
        *)
            local parser_name="$1"
            ;;
        esac
        shift
    done

    log "$parser_name"
    declare -gA "$(__mangle "$parser_name")"=\(\)
    local -n parser="$(__mangle "$parser_name")"
    for k in "${!parsed_args[@]}"; do
        local v="${parsed_args[$k]}"
        log "$K" "$V"
        bobject set-string --ref parser ".$k" v
    done

    declare -p
}

argbarse a
