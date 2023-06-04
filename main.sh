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


__mangle() {
    local -a mangled=("__ab_object_")
    for n in $(seq 1 "${#1}"); do
        local char="${n:0:$n}"
        mangled+=("$(printf %x "'$char")")
    done
    local old="$IFS"
    IFS=''
    echo "${mangled[*]}"
    IFS="$old"
}

__min() {
    printf "%s\n" "$@" | sort -g | head -n1
}

__levenshtein() {
    local s1="$1" s2="$2"

    [[ "$s1" = "$s2" ]] && {
        printf 0
        return
    }

    if (( ! ${#s1} )); then
        printf "%d" "${#s2}"
        return
    elif (( ! ${#s2} )); then
        printf "%d" "${#s1}"
        return
    fi

    # shellcheck disable=SC2034 # used by bobject
    local -a temp_object=()
    local -a matrix=() 
    local -a i_array=()
    local -a j_array=()
    bobject set-array --ref matrix ".matrix" temp_object
    for i in $(seq 0 "${#s1}"); do 
        bobject set-array --ref matrix ".[\"matrix\"].[$i]" i_array
        bobject set-string --ref matrix ".[\"matrix\"].[$i].[0]" i
    done

    for j in $(seq 0 "${#s2}"); do
        bobject set-array --ref matrix ".[\"matrix\"].[0]" j_array
        bobject set-string --ref matrix ".[\"matrix\"].[0].[$j]" j
    done

    for i in $(seq 1 "${#s1}"); do
        for j in $(seq 1 "${#s2}"); do
            # shellcheck disable=SC2034 # used by object
            local cost ij_val
            if [[ "$(printf %x "'${s1:0:$i}")" = "$(printf %x "'${s2:0:$j}")" ]]; then
                cost=0
            else cost=1; fi
            bobject get-string --value matrix ".[\"matrix\"].[$((i-1))].[$j]"
            local a=$(( REPLY + 1 ))
            bobject get-string --value matrix ".[\"matrix\"].[$i].[$((j-1))]"
            local b=$(( REPLY + 1 ))
            bobject get-string --value matrix ".[\"matrix\"].[$((i-1))].[$((j-1))]"
            local c=$(( REPLY + cost ))
            # shellcheck disable=SC2034 # used by bobject
            ij_val="$(__min "$a" "$b" "$c")"
            bobject set-string --ref matrix ".[\"matrix\"].[$i].[$j]" ij_val
        done

   done
   bobject get-string --value matrix ".[\"matrix\"].[${#s1}].[${#s2}]"
   printf %s "$REPLY"
}

argbarse.option() {
    local -A parsed_args=()
    local n_arg=0
    while (( $# > 0 )); do
        case "$1" in
        --argn=*)
            parsed_args[args]="${1#*=}"
            ;;
        --argn)
            shift
            parsed_args[args]="$1"
            ;;
        -*)
            printf -v _ab_func_error "invalid option '%s'" "$1" >&2
            return 1
            ;;
        :*)
            local -A opts=
            : "${1#:}"
            if [[ "${#_}" -eq 2 && "$_" =~ ^\-[a-zA-Z0-9]$ ]]; then
                opts[short]="${BASH_REMATCH[0]}"
            elif [[ "${#_}" -gt 3 && "$_" =~ ^\-\-[a-zA-Z0-9][a-zA-Z0-9_\-][a-zA-Z0-9_\-]*$ ]]; then
                opts[long]="${BASH_REMATCH[0]}"
            else
                printf -v _ab_func_error "invalid option name '%s'" "${1#:}"
                return 1
            fi
            ;;
        *)
            local mangled_name
            mangled_name="$(__mangle "$1")"
            local -n parser="$mangled_name"
            ;;
        esac
        shift
    done

    [[ "$mangled_name" = "__" || -z "$mangled_name" ]] && {
        printf -v _ab_func_error "empty variable name"
        return 1
    }

    declare -p opts
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
            # shellcheck disable=SC2034 # exported to outside
            printf -v _ab_func_error "invalid option '%s'" "$1" >&2
            return 1
            ;;
        *)
            local parser_name="$1"
            ;;
        esac
        shift
    done

    local mangled_name
    mangled_name="$(__mangle "$parser_name")"
    declare -gA "$mangled_name"=
    # shellcheck disable=SC2034 # used in bobject
    local -n parser="$mangled_name"

    # shellcheck disable=SC2034 # used in bobject
    local -A temp_object=()
    bobject set-object --ref parser ".$mangled_name" temp_object
    for k in "${!parsed_args[@]}"; do
        # shellcheck disable=SC2034 # used in bobject
        local v="${parsed_args[$k]}"
        bobject set-string --ref parser ".$mangled_name.$k" v
    done
}

__levenshtein hi ih
