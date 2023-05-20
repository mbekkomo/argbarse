#!/usr/bin/env bash

__bv_major="${BASH_VERSINFO[0]}"
__bv_minor="${BASH_VERSINFO[1]}"
(( __bv_major < 4 || __bv_major == 4 && __bv_minor < 3 )) && 
    : "${error:?"argbarse requires Bash 4.3!"}"

[[ "${BASH_SOURCE[0]}" == "$0" ]] &&
    : "${error:?"source $0 instead executing it!"}"

__argbarse_init() {
    local __
}
