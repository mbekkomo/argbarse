#!/usr/bin/env sh

#
# log.sh
#
# Copyright (c) 2023 UrNightmaree
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

LOG_VERSION="0.1.0"


ESC="$(printf "\x1b")"
RST="$ESC[0m"
Ctrace="$ESC[34m"
Cdebug="$ESC[36m"
Cinfo="$ESC[32m"
Cwarn="$ESC[33m"
Cerror="$ESC[31m"
Cfatal="$ESC[35m"

level() {
    case "$1" in
    TRACE)
        echo 1
        ;;
    DEBUG)
        echo 2
        ;;
    INFO)
        echo 3
        ;;
    WARN)
        echo 4
        ;;
    ERROR)
        echo 5
        ;;
    FATAL)
        echo 6
        ;;
    esac
}

log() {
    LOG_LEVEL="${LOG_LEVEL:-TRACE}"

    format_log="%s[%-6s%s]:%s %s"
    format_logfile="[%-6s%s]: %s"

    color_rst="$RST"

    case "${1:?"specify at least mode or message"}" in
    TRACE)
        mode=TRACE
        color="$Ctrace"
        shift
        ;;
    DEBUG)
        mode=DEBUG
        color="$Cdebug"
        shift
        ;;
    INFO)
        mode=INFO
        color="$Cinfo"
        shift
        ;;
    WARN)
        mode=WARN
        color="$Cwarn"
        shift
        ;;
    ERROR)
        mode=ERROR
        color="$Cerror"
        shift
        ;;
    FATAL)
        mode=FATAL
        color="$Cfatal"
        shift
        ;;
    *)
        mode=TRACE
        color="$Ctrace"
        ;;
    esac

    [ "$(level "$mode")" -lt "$(level "$LOG_LEVEL")" ] &&
        return

    [ -n "$LOG_NOCOLOR" ] &&
        unset color color_rst

    printf "$format_log\n" "$color" "$mode" "$(date '+%H:%M:%S')" "$color_rst" "$*"

    [ -n "$LOG_FILE" ] &&
        printf "$format_logfile\n" "$mode" "$(date)" "$*" >> "$LOG_FILE"
}

export -f log
export LOG_VERSION
