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

# __mangle <string> [prefix:-__ab_parser_object_]
__mangle() {
    local -a mangled=("${2:-__ab_parser_object_}")
    local oldifs="$IFS"
    IFS=$'\n'
    for n in $(seq 1 "${#1}"); do
        local char="${n:0:$n}"
        mangled+=("$(printf %x "'$char")")
    done
    IFS=''
    echo "${mangled[*]}"
    IFS="$oldifs"
}

# __levenshtein <s1> <s2>
__levenshtein () {
    local -r target="$1" given="$2"
    local -r targetLength="${#target}" givenLength="${#given}"
    local alt cost ins gIndex=0 lowest nextGIndex nextTIndex tIndex
    local -A leven

    while (( gIndex <= givenLength )); do
        tIndex=0
        while (( tIndex <= targetLength )); do
            (( gIndex == 0 )) && leven["0,$tIndex"]="$tIndex"
            (( tIndex == 0 )) && leven["$gIndex,0"]="$gIndex"
            (( tIndex++ ))
        done
        (( gIndex++ ))
    done
    gIndex=0
    while (( gIndex < givenLength )); do
        tIndex=0
        while (( tIndex < targetLength )); do
            [[ "${target:tIndex:1}" == "${given:gIndex:1}" ]] && cost=0 || cost=1
            (( nextTIndex = tIndex + 1 ))
            (( nextGIndex = gIndex + 1 ))
            (( del = leven[$gIndex,$nextTIndex] + 1 ))
            (( ins = leven[$nextGIndex,$tIndex] + 1 ))
            (( alt = leven[$gIndex,$tIndex] + cost ))
            (( lowest = ins <= del ? ins : del ))
            (( lowest = alt <= lowest ? alt : lowest ))
            leven["$nextGIndex,$nextTIndex"]="$lowest"
            (( tIndex++ ))
        done
        (( gIndex++ ))
    done
    printf %d "$lowest"
}

__min() {
    local lowest="$1"; shift
    for n in "$@"; do
        (( lowest = n <= lowest ? n : lowest ))
    done
    printf %d "$lowest"
}

__get_closest_match() {
    local -n match_array="$2"
    local -a levdist
    for s in "${match_array[@]}"; do
        levdist+="$(__levenshtein "$1" "$s")"
    done

    local match
    for i in "${!levdist[@]}"; do
        (( levdist["$i"] == $(__min "${levdist[@]}") )) && {
            match="${match_array[$i]}"
            break
        }
    done
    printf %s "$match"
}

argbarse.option() {
    local -A parsed_args=()
    while (( $# > 0 )); do
        case "$1" in
        --choices=*)
            parsed_args[choices]="${1#*=}"
            ;;
        --choices)
            shift
            parsed_args[choices]="$1"
            ;;
        --narg=*)
            parsed_args[narg]="${1#*=}"
            ;;
        --narg)
            shift
            parsed_args[narg]="$1"
            ;;
        -*)
            printf -v _ab_func_error "invalid option '%s'" "$1" >&2
            return 1
            ;;
        :*)
            local -A opts
            : "${1#:}"
            if [[ "${#_}" -eq 2 && "$_" =~ ^\-[a-zA-Z0-9]$ ]]; then
                opts[short]="${BASH_REMATCH[0]#-}"
            elif [[ "${#_}" -gt 3 && "$_" =~ ^\-\-[a-zA-Z0-9][a-zA-Z0-9_\-][a-zA-Z0-9_\-]*$ ]]; then
                opts[long]="${BASH_REMATCH[0]#--}"
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

    [[ -n "${opts[short]}" ]] && {
        # shellcheck disable=SC2034 # used by bobject
        local -A options_short_obj
        bobject set-object --ref parser \
            '.["'"$mangled_name"'"].["options"].["short"].["'"${opts[short]}"'"]' \
            options_short_obj 
        bobject get-array --value parser \
            ".$mangled_name.options_list.short"
        # shellcheck disable=SC2034 # used by bobject
        local _tmp="${opts[short]}"
        bobject set-string --ref parser \
            '.["'"$mangled_name"'"].["options_list"].["short"].['$((${#REPLY}+1))']' \
            _tmp
        for p in "${!parsed_args[@]}"; do
            local v="${parsed_args[$p]}"
            [[ "$p" = choices ]] && {
                local oldifs="$IFS"
                IFS=','
                # shellcheck disable=SC2034 # used by bobject
                read -ra options_choices <<< "$v"
                IFS="$oldifs"
                bobject set-array --ref parser \
                    '.["'"$mangled_name"'"].["options"].["short"].["'"${opts[short]}"'"].["choices"]' \
                    options_choices
                continue
            }
            bobject set-string --ref parser \
                '.["'"$mangled_name"'"].["options"].["short"].["'"${opts[short]}"'"].["'"$p"'"]' \
                v
        done
    }
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
    # shellcheck disable=SC2034 # used by bobject
    local -n parser="$mangled_name"

    # shellcheck disable=SC2034 # used by bobject
    local -A temp_object=()
    bobject set-object --ref parser ".$mangled_name" temp_object
    for k in "${!parsed_args[@]}"; do
        # shellcheck disable=SC2034 # used by bobject
        local v="${parsed_args[$k]}"
        bobject set-string --ref parser ".$mangled_name.$k" v
    done

    # shellcheck disable=SC2034 # used by bobject
    local -A options options_list flags flags_list
    bobject set-object --ref parser ".$mangled_name.options" options
    bobject set-object --ref parser ".$mangled_name.options_list" options_list
    bobject set-object --ref parser ".$mangled_name.flags" flags
    bobject set-object --ref parser ".$mangled_name.flags_list" flags_list

    # shellcheck disable=SC2034 # used by bobject
    local -A options_short options_long flags_short flags_long
    bobject set-object --ref parser ".$mangled_name.options.short" options_short
    bobject set-object --ref parser ".$mangled_name.options.long" options_long
    bobject set-object --ref parser ".$mangled_name.flags.short" flags_short
    bobject set-object --ref parser ".$mangled_name.flags.long" flags_long

    # shellcheck disable=SC2034 # used by bobject
    local -a options_list_short options_list_long flags_list_short flags_list_long
    bobject set-array --ref parser \
        ".$mangled_name.options_list.short" \
        options_list_short
    bobject set-array --ref parser \
        ".$mangled_name.options_list.long" \
        options_list_long
    bobject set-array --ref parser \
        ".$mangled_name.flags_list.short" \
        flags_list_short 
    bobject set-array --ref parser \
        ".$mangled_name.flags_list.long" \
        flags_list_long
}

argbarse parser --name "$0" --description "lol" --epilog "lol"
argbarse.option parser :-a --narg 10 --choices "a,b,c"
bobject.print "$(__mangle parser)"
