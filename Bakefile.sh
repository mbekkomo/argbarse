#!/usr/bin/env bash

: "${BOBJECT_COMMIT:=778ccd3}"

__command_exist() {
    command -v "$1" >/dev/null 2>&1 ||
        bake.die "No command '$1' in path, make sure it is exist"

    true
}

__fetch_bobject() {
    __command_exist git

    [[ ! -d ".deps/bash-object" ]] && {
        mkdir .deps >/dev/null 2>&1
        git clone https://github.com/bash-bastion/bash-object \
            .deps/bash-object
        git -C .deps/bash-object checkout  "$BOBJECT_COMMIT"
    }

    true
}

task.bundle() {
    __fetch_bobject

    local bundled
    bundled="$(cat <<EOF
##############################################################################
#= bash-object ${BOBJECT_COMMIT:0:7} (https://github.com/bash-bastion/bash-object)

$(cat .deps/bash-object/pkg/src/{*,**/*}.sh)

#= eof bash-object
##############################################################################
EOF
    )"

    : "$(cat main.sh 2>/dev/null)"
    echo "${_//#@BUNDLED_BOBJECT@/$bundled}" > argbarse.sh
}

task.release() {
    __command_exist gh

    local version="$1"

    {
        if ! git rev-parse --verify release >/dev/null 2>&1; then
            git checkout -b release
        else
            git checkout release
            git merge origin/main
        fi

        git add .
        sed -i 's:/.deps:#/.deps:g' .gitignore
        git commit -m "release argbarse $version"
        git tag "v$version"

        git push origin release
        : "$(git remote get-url origin)"
        : "${_#https://github.com/}"
        gh release create "v$version" \
            -R "${_%.git}" changelog.md

        git checkout main
    } || git checkout main
}
