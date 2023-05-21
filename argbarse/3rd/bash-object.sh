# src taken from https://github.com/bash-bastion/bash-object
# bash-object 1.8.0+778ccd3

# Make sure bash-object is not loaded again.
declare -rp BASH_OBJECT_LOADED >/dev/null 2>&1 &&
    return 0
declare -r BASH_OBJECT_LOADED=1

source argbarse/3rd/bash-object/parse.sh
source argbarse/3rd/bash-object/public/bobject-print.sh
source argbarse/3rd/bash-object/public/bobject-unset.sh
source argbarse/3rd/bash-object/public/bobject.sh
source argbarse/3rd/bash-object/traverse-get.sh
source argbarse/3rd/bash-object/traverse-set.sh
source argbarse/3rd/bash-object/util/ensure.sh
source argbarse/3rd/bash-object/util/trace.sh
source argbarse/3rd/bash-object/util/util.sh
