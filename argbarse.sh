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

##############################################################################
#= bash-object 0.8.2 (https://github.com/bash-bastion/bash-object)

# shellcheck shell=bash

# @description Convert a user string into an array representing successive
# object / array access
# @exitcode 1 Miscellaneous error
# @exitcode 2 Parsing error
bash_object.parse_querytree() {
	declare -ga REPLY_QUERYTREE=()

	local flag_parser_type=

	local arg=
	for arg; do case $arg in
	--simple)
		flag_parser_type='simple'
		shift ;;
	--advanced)
		flag_parser_type='advanced'
		shift ;;
	esac done; unset -v arg

	local querytree="$1"

	if [ "$flag_parser_type" = 'simple' ]; then
		if [ "${querytree::1}" != . ]; then
			bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'Querytree must begin with a dot'
			return
		fi

		local old_ifs="$IFS"; IFS=.
		for key in $querytree; do
			if [ -z "$key" ]; then
				continue
			fi

			REPLY_QUERYTREE+=("$key")
		done
		IFS="$old_ifs"
	elif [ "$flag_parser_type" = 'advanced' ]; then
		local char=
		local mode='MODE_DEFAULT'
		local -i PARSER_COLUMN_NUMBER=0

		# Append dot so parsing does not fail at end
		# This makes parsing a lot easier, since it always expects a dot after a ']'
		querytree="${querytree}."

		# Reply represents an accessor (e.g. 'sub_key')
		local reply=

		while IFS= read -rN1 char; do
			PARSER_COLUMN_NUMBER+=1

			if [ -n "${TRACE_BASH_OBJECT_PARSE+x}" ]; then
				printf '%s\n' "-- $mode: '$char'" >&3
			fi

			case $mode in
			MODE_DEFAULT)
				if [ "$char" = . ]; then
					mode='MODE_EXPECTING_BRACKET'
				else
					bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'Querytree must begin with a dot'
					return
				fi
				;;
			MODE_BEFORE_DOT)
				if [ "$char" = . ]; then
					mode='MODE_EXPECTING_BRACKET'
				else
					bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'Each part in a querytree must be deliminated by a dot'
					return
				fi
				;;
			MODE_EXPECTING_BRACKET)
				if [ "$char" = \[ ]; then
					mode='MODE_EXPECTING_OPENING_STRING_OR_NUMBER'
				elif [ "$char" = $'\n' ]; then
					return
				else
					bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'A dot MUST be followed by an opening bracket in this mode'
					return
				fi
				;;
			MODE_EXPECTING_OPENING_STRING_OR_NUMBER)
				reply=

				if [ "$char" = \" ]; then
					mode='MODE_EXPECTING_STRING'
				elif [ "$char" = ']' ]; then
					bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'Key cannot be empty'
					return
				else
					case "$char" in
					0|1|2|3|4|5|6|7|8|9)
						reply=$'\x1C'"$char"
						mode='MODE_EXPECTING_READ_NUMBER'
						;;
					*)
						bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'A number or opening quote must follow an open bracket'
						return
						;;
					esac
				fi
				;;
			MODE_EXPECTING_STRING)
				if [ "$char" = \\ ]; then
					mode='MODE_STRING_ESCAPE_SEQUENCE'
				elif [ "$char" = \" ]; then
					if [ -z "$reply" ]; then
						bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'Key cannot be empty'
						return
					fi

					REPLY_QUERYTREE+=("$reply")
					mode='MODE_EXPECTING_CLOSING_BRACKET'
				elif [ "$char" = $'\n' ]; then
					bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'Querytree is not complete'
					return
				else
					reply+="$char"
				fi
				;;
			MODE_STRING_ESCAPE_SEQUENCE)
				case "$char" in
					\\) reply+=\\ ;;
					\") reply+=\" ;;
					']') reply+=']' ;;
					*)
						bash_object.util.die 'ERROR_QUERYTREE_INVALID' "Escape sequence of '$char' not valid"
						return
						;;
				esac
				mode='MODE_EXPECTING_STRING'
				;;
			MODE_EXPECTING_READ_NUMBER)
				if [ "$char" = ']' ]; then
					REPLY_QUERYTREE+=("$reply")
					mode='MODE_BEFORE_DOT'
				else
					case "$char" in
					0|1|2|3|4|5|6|7|8|9)
						reply+="$char"
						;;
					*)
						bash_object.util.die 'ERROR_QUERYTREE_INVALID' "Expecting number, found '$char'"
						return
						;;
					esac
				fi
				;;
			MODE_EXPECTING_CLOSING_BRACKET)
				if [ "$char" = ']' ]; then
					mode='MODE_BEFORE_DOT'
				else
					bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'Expected a closing bracket after the closing quotation mark'
					return
				fi
				;;
			esac
		done <<< "$querytree"
	else
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Must pass either '--simple' or '--advanced'"
		return
	fi
}

# @description Parse a virtual object into its components
bash_object.parse_virtual_object() {
	REPLY1=; REPLY2=
	local virtual_object="$1"

	local virtual_metadatas="${virtual_object%%&*}" # type=string;attr=smthn;
	local virtual_object_name="${virtual_object#*&}" # __bash_object_383028

	if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
		bash_object.trace_print 2 "virtual_object: '$virtual_object'"
		bash_object.trace_print 2 "virtual_metadatas: '$virtual_metadatas'"
		bash_object.trace_print 2 "virtual_object_name: '$virtual_object_name'"
	fi

	# Parse info about the virtual object
	local vmd= vmd_key= vmd_value= vmd_dtype=
	while IFS= read -rd \; vmd; do
		if [ -z "$vmd" ]; then
			continue
		fi

		vmd="${vmd%;}"
		vmd_key="${vmd%%=*}"
		vmd_value="${vmd#*=}"

		if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
			bash_object.trace_print 2 "vmd: '$vmd'"
			bash_object.trace_print 3 "vmd_key: '$vmd_key'"
			bash_object.trace_print 3 "vmd_value: '$vmd_value'"
		fi

		case "$vmd_key" in
			type) vmd_dtype="$vmd_value" ;;
		esac
	done <<< "$virtual_metadatas"

	REPLY1=$virtual_object_name
	REPLY2=$vmd_dtype
}
# shellcheck shell=bash

bash_object.traverse-get() {
	unset REPLY; REPLY=

	if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
		bash_object.trace_print 0 ''
		bash_object.trace_print 0 "CALL: bash_object.traverse-get: $*"
	fi

	local flag_as_what=
	local -a args=()

	local arg=
	for arg; do case $arg in
	--ref)
		if [ -n "$flag_as_what" ]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Flags '--ref' and '--value' are mutually exclusive"
			return
		fi
		flag_as_what='as-ref'
		;;
	--value)
		if [ -n "$flag_as_what" ]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Flags '--ref' and '--value' are mutually exclusive"
			return
		fi
		flag_as_what='as-value'
		;;
	--)
		break
		;;
	*)
		args+=("$arg")
		;;
	esac done; unset -v arg

	if [ -z "$flag_as_what" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Must pass either the '--ref' or '--value' flag"
		return
	fi

	# Ensure correct number of arguments have been passed
	if (( ${#args[@]} != 3)); then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Expected 3 arguments, but received ${#args[@]}"
		return
	fi

	# Ensure parameters are not empty
	if [ -z "${args[0]}" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Positional parameter 1 is empty. Please check passed parameters"
		return
	fi
	if [ -z "${args[1]}" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Positional parameter 2 is empty. Please check passed parameters"
		return
	fi
	if [ -z "${args[2]}" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Positional parameter 3 is empty. Please check passed parameters"
		return
	fi

	local final_value_type="${args[0]}"
	local root_object_name="${args[1]}"
	local querytree="${args[2]}"

	# Start traversing at the root object
	local current_object_name="$root_object_name"
	local -n __current_object="$root_object_name"
	local vmd_dtype=

	# A stack of all the evaluated querytree elements
	# local -a querytree_stack=()

	# Parse the querytree, and recurse over their elements
	case "$querytree" in
		*']'*) bash_object.parse_querytree --advanced "$querytree" ;;
		*) bash_object.parse_querytree --simple "$querytree" ;;
	esac
	local i=
	for ((i=0; i<${#REPLY_QUERYTREE[@]}; i++)); do
		local key="${REPLY_QUERYTREE[$i]}"

		local is_index_of_array='no'
		if [ "${key::1}" = $'\x1C' ]; then
			key="${key#?}"
			is_index_of_array='yes'
		fi

		# querytree_stack+=("$key")
		# bash_object.util.generate_querytree_stack_string
		# local querytree_stack_string="$REPLY"

		bash_object.trace_loop

		# If the past vmd_dtype is an array and 'key' is not a number
		if [[ $vmd_dtype == 'array' && $key == *[!0-9]* ]]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Cannot index an array with a non-integer ($key)"
			return
		# If the past vmd_dtype is an array and 'key' is a number
		elif [[ $vmd_dtype == 'object' && $key != *[!0-9]* ]]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Cannot index an object with an integer ($key)"
			return
		# If 'key' is not a member of object or index of array, error
		elif [ -z "${__current_object[$key]+x}" ]; then
			bash_object.util.die 'ERROR_NOT_FOUND' "Key or index '$key' (querytree index '$i') does not exist"
			return
		# If 'key' is a valid member of an object or index of array
		else
			local key_value="${__current_object[$key]}"

			# If 'key_value' is a virtual object, dereference it
			if [ "${key_value::2}" = $'\x1C\x1D' ]; then
				if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
					bash_object.trace_print 2 "BLOCK: OBJECT/ARRAY"
				fi

				local old_current_object_name="$current_object_name"

				virtual_item="${key_value#??}"
				bash_object.parse_virtual_object "$virtual_item"
				local current_object_name="$REPLY1"
				local vmd_dtype="$REPLY2"
				local -n __current_object="$current_object_name"

				if [ -n "${VERIFY_BASH_OBJECT+x}" ]; then
					# Ensure the 'final_value' is the same type as specified by the user (WET)
					local __current_object_type=
					if ! __current_object_type="$(declare -p "$current_object_name" 2>/dev/null)"; then
						bash_object.util.die 'ERROR_INTERNAL' "The variable '$current_object_name' does not exist"
						return
					fi
					__current_object_type="${__current_object_type#declare -}"
					case "${__current_object_type::1}" in
						A) __current_object_type='object' ;;
						a) __current_object_type='array' ;;
						-) __current_object_type='string' ;;
						*) __current_object_type='other' ;;
					esac
					case "$vmd_dtype" in
					object)
						if [ "$__current_object_type" != object ]; then
							bash_object.util.die 'ERROR_VOBJ_INCORRECT_TYPE' "Virtual object has a reference of type '$vmd_dtype', but when dereferencing, a variable of type '$__current_object_type' was found"
							return
						fi
						;;
					array)
						if [ "$__current_object_type" != array ]; then
							bash_object.util.die 'ERROR_VOBJ_INCORRECT_TYPE' "Virtual object has a reference of type '$vmd_dtype', but when dereferencing, a variable of type '$__current_object_type' was found"
							return
						fi
						;;
					*)
						bash_object.util.die 'ERROR_VOBJ_INVALID_TYPE' "Unexpected vmd_dtype '$vmd_dtype'"
						return
						;;
					esac
				fi

				# Ensure no circular references (WET)
				if [ "$old_current_object_name" = "$current_object_name" ]; then
					bash_object.util.die 'ERROR_SELF_REFERENCE' "Virtual object '$current_object_name' cannot reference itself"
					return
				fi

				if ((i+1 < ${#REPLY_QUERYTREE[@]})); then
					# Do nothing, and continue to next element in query. We already check for the
					# validity of the virtual object above, so no need to do anything here
					:
				elif ((i+1 == ${#REPLY_QUERYTREE[@]})); then
					# We are last element of query, return the object
					if [ "$final_value_type" = object ]; then
						case "$vmd_dtype" in
						object)
							if [ "$flag_as_what" = 'as-value' ]; then
								declare -gA REPLY=()
								local key=
								for key in "${!__current_object[@]}"; do
									REPLY["$key"]="${__current_object[$key]}"
								done
							elif [ "$flag_as_what" = 'as-ref' ]; then
								bash_object.util.die 'ERROR_INTERNAL' "--ref not implemented"
								return
								# declare -gn REPLY="$current_object_name"
							else
								bash_object.util.die 'ERROR_INTERNAL' "Unexpected flag_as_what '$flag_as_what'"
								return
							fi
							;;
						array)
							bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Queried for object, but found existing $vmd_dtype"
							return
							;;
						*)
							bash_object.util.die 'ERROR_VOBJ_INVALID_TYPE' "Unexpected vmd_dtype '$vmd_dtype'"
							return
							;;
						esac
					elif [ "$final_value_type" = array ]; then
						case "$vmd_dtype" in
						object)
							bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Queried for array, but found existing $vmd_dtype"
							return
							;;
						array)
							if [ "$flag_as_what" = 'as-value' ]; then
								declare -ga REPLY=()
								# shellcheck disable=SC2190
								REPLY=("${__current_object[@]}")
							elif [ "$flag_as_what" = 'as-ref' ]; then
								bash_object.util.die 'ERROR_INTERNAL' "--ref not implemented"
								return
							else
								bash_object.util.die 'ERROR_INTERNAL' "Unexpected flag_as_what '$flag_as_what'"
								return
							fi
							;;
						*)
							bash_object.util.die 'ERROR_VOBJ_INVALID_TYPE' "Unexpected vmd_dtype '$vmd_dtype'"
							return
							;;
						esac
					elif [ "$final_value_type" = string ]; then
						case "$vmd_dtype" in
						object)
							bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Queried for string, but found existing $vmd_dtype"
							return
							;;
						array)
							bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Queried for string, but found existing $vmd_dtype"
							return
							;;
						*)
							bash_object.util.die 'ERROR_VOBJ_INVALID_TYPE' "Unexpected vmd_dtype '$vmd_dtype'"
							return
						esac
					else
						bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "Unexpected final_value_type '$final_value_type'"
						return
					fi
				fi
			# Otherwise, 'key_value' is a string
			else
				if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
					bash_object.trace_print 2 "BLOCK: STRING"
				fi

				if ((i+1 < ${#REPLY_QUERYTREE[@]})); then
					bash_object.util.die 'ERROR_NOT_FOUND' "The passed querytree implies that '$key' accesses an object or array, but a string with a value of '$key_value' was found instead"
					return
				elif ((i+1 == ${#REPLY_QUERYTREE[@]})); then
					local value="${__current_object[$key]}"
					if [ "$final_value_type" = object ]; then
						bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Queried for $final_value_type, but found existing string '$value'"
						return
					elif [ "$final_value_type" = array ]; then
						bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Queried for $final_value_type, but found existing string '$value'"
						return
					elif [ "$final_value_type" = string ]; then
						if [ "$flag_as_what" = 'as-value' ]; then
							# shellcheck disable=SC2178
							REPLY="$value"
						elif [ "$flag_as_what" = 'as-ref' ]; then
							bash_object.util.die 'ERROR_INTERNAL' "--ref not implemented"
							return
						else
							bash_object.util.die 'ERROR_INTERNAL' "Unexpected flag_as_what '$flag_as_what'"
							return
						fi

					fi
				fi
			fi
		fi

		bash_object.trace_current_object
		if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
			bash_object.trace_print 0 "END BLOCK"
		fi
	done; unset i
}
# shellcheck shell=bash

bash_object.traverse-set() {
	if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
		bash_object.trace_print 0 ''
		bash_object.trace_print 0 "CALL: bash_object.traverse-set: $*"
	fi

	local flag_pass_by_what=
	local -a args=()

	local arg=
	for arg; do case $arg in
	--ref)
		if [ -n "$flag_pass_by_what" ]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Flags '--ref' and '--value' are mutually exclusive"
			return
		fi
		flag_pass_by_what='by-ref'
		;;
	--value)
		if [ -n "$flag_pass_by_what" ]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Flags '--ref' and '--value' are mutually exclusive"
			return
		fi
		flag_pass_by_what='by-value'
		;;
	--)
		# All arguments after '--' are in '$@'
		break
		;;
	*)
		args+=("$arg")
		;;
	esac; if ! shift; then
		bash_object.util.die 'ERROR_INTERNAL' 'Shift failed, but was expected to succeed'
		return
	fi; done; unset -v arg

	if [ -z "$flag_pass_by_what" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Must pass either the '--ref' or '--value' flag"
		return
	fi

	if [ "$flag_pass_by_what" = 'by-ref' ]; then
		if (( ${#args[@]} != 4)); then
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Expected 4 arguments (with --ref), but received ${#args[@]}"
			return
		fi
	elif [ "$flag_pass_by_what" = 'by-value' ]; then
		if (( ${#args[@]} != 3)); then
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Expected 3 arguments (with --value) before '--', but received ${#args[@]})"
			return
		fi
	else
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Unexpected final_value_type '$final_value_type'"
		return
	fi

	local final_value_type="${args[0]}"
	local root_object_name="${args[1]}"
	local querytree="${args[2]}"

	# Ensure parameters are not empty
	if [ -z "$final_value_type" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Positional parameter 1 is empty. Please check passed parameters"
		return
	fi
	if [ -z "$root_object_name" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Positional parameter 2 is empty. Please check passed parameters"
		return
	fi
	if [ -z "$querytree" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Positional parameter 3 is empty. Please check passed parameters"
		return
	fi

	# Set final_value after we ensure 'final_value_type' is non-empty
	local final_value=
	if [ "$flag_pass_by_what" = 'by-ref' ]; then
		final_value="${args[3]}"

		if [ -z "$final_value" ]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Positional parameter 4 is empty. Please check passed parameters"
			return
		fi
	elif [ "$flag_pass_by_what" = 'by-value' ]; then
		if [ "$final_value_type" = object ]; then
			final_value="__bash_object_${RANDOM}_$RANDOM"
			local -A "$final_value"
			local -n final_value_ref="$final_value"
			final_value_ref=()

			if [ "$1" != -- ]; then
				bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Must pass '--' and the value when using --value"
				return
			fi
			shift

			if (( $# & 1 )); then
				bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "When passing --value with set-object, an even number of values must be passed after the '--'"
				return
			fi

			while (( $# )); do
				local key="$1"
				if ! shift; then
					bash_object.util.die 'ERROR_INTERNAL' 'Shift failed, but was expected to succeed'
					return
				fi

				local value="$1"
				if ! shift; then
					bash_object.util.die 'ERROR_INTERNAL' 'Shift failed, but was expected to succeed'
					return
				fi

				final_value_ref["$key"]="$value"
			done; unset key value
		elif [ "$final_value_type" = array ]; then
			local -a final_value="__bash_object_${RANDOM}_$RANDOM"
			local -n final_value_ref="$final_value"
			if [ "$1" != -- ]; then
				bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Must pass '--' and the value when using --value"
				return
			fi
			shift

			final_value_ref=("$@")
		elif [ "$final_value_type" = string ]; then
			local final_value="__bash_object_${RANDOM}_$RANDOM"
			local -n final_value_ref="$final_value"
			if [ "$1" != -- ]; then
				bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Must pass '--' and the value when using --value"
				return
			fi
			shift

			if (( $# > 1)); then
				bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "When passing --value with set-string, only one value must be passed after the '--'"
				return
			fi
			final_value_ref="$1"
		else
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Unexpected final_value_type '$final_value_type'"
			return
		fi
	else
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Unexpected final_value_type '$final_value_type'"
		return
	fi

	if [ -z "$final_value" ]; then
		bash_object.util.die 'ERROR_INTERNAL' "Variable 'final_value' is empty"
		return
	fi

	if [ -n "${VERIFY_BASH_OBJECT+x}" ]; then
		# Ensure the root object exists, and is an associative array
		local root_object_type=
		if root_object_type="$(declare -p "$root_object_name" 2>/dev/null)"; then :; else
			bash_object.util.die 'ERROR_NOT_FOUND' "The associative array '$root_object_name' does not exist"
			return
		fi
		root_object_type="${root_object_type#declare -}"
		if [ "${root_object_type::1}" != 'A' ]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "The 'root object' must be an associative array"
			return
		fi

		if [ "$flag_pass_by_what" = 'by-ref' ]; then
			# Ensure the 'final_value' is the same type as specified by the user
			local actual_final_value_type=
			if ! actual_final_value_type="$(declare -p "$final_value" 2>/dev/null)"; then
				bash_object.util.die 'ERROR_NOT_FOUND' "The variable '$final_value' does not exist"
				return
			fi
			actual_final_value_type="${actual_final_value_type#declare -}"
			case "${actual_final_value_type::1}" in
				A) actual_final_value_type='object' ;;
				a) actual_final_value_type='array' ;;
				-) actual_final_value_type='string' ;;
				*) actual_final_value_type='other' ;;
			esac

			if [ "$final_value_type" = object ]; then
				if [ "$actual_final_value_type" != object ]; then
					bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "Argument 'set-$final_value_type' was specified, but a variable with type '$actual_final_value_type' was passed"
					return
				fi
			elif [ "$final_value_type" = array ]; then
				if [ "$actual_final_value_type" != array ]; then
					bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "Argument 'set-$final_value_type' was specified, but a variable with type '$actual_final_value_type' was passed"
					return
				fi
			elif [ "$final_value_type" = string ]; then
				if [ "$actual_final_value_type" != string ]; then
					bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "Argument 'set-$final_value_type' was specified, but a variable with type '$actual_final_value_type' was passed"
					return
				fi
			else
				bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "Unexpected final_value_type '$final_value_type'"
				return
			fi
		fi
	fi

	# Start traversing at the root object
	local current_object_name="$root_object_name"
	local -n __current_object="$root_object_name"
	local vmd_dtype=

	# A stack of all the evaluated querytree elements
	local -a querytree_stack=()

	# Parse the querytree, and recurse over their elements
	case "$querytree" in
		*']'*) bash_object.parse_querytree --advanced "$querytree" ;;
		*) bash_object.parse_querytree --simple "$querytree" ;;
	esac
	local i=
	for ((i=0; i<${#REPLY_QUERYTREE[@]}; i++)); do
		local key="${REPLY_QUERYTREE[$i]}"

		local is_index_of_array='no'
		if [ "${key::1}" = $'\x1C' ]; then
			key="${key#?}"
			is_index_of_array='yes'
		fi

		querytree_stack+=("$key")
		bash_object.util.generate_querytree_stack_string
		local querytree_stack_string="$REPLY"

		bash_object.trace_loop

		# If the past vmd_dtype is an array and 'key' is not a number
		if [[ $vmd_dtype == 'array' && $key == *[!0-9]* ]]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Cannot index an array with a non-integer ($key)"
			return
		# If the past vmd_dtype is an array and 'key' is a number
		elif [[ $vmd_dtype == 'object' && $key != *[!0-9]* ]]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Cannot index an object with an integer ($key)"
			return
		# If 'key' is not a member of object or index of array, error
		elif [ -z "${__current_object[$key]+x}" ]; then
			# If we are before the last element in the query, then error
			if ((i+1 < ${#REPLY_QUERYTREE[@]})); then
				bash_object.util.die 'ERROR_NOT_FOUND' "Key or index '$key' (querytree index '$i') does not exist"
				return
			# If we are at the last element in the query, and it doesn't exist, create it
			elif ((i+1 == ${#REPLY_QUERYTREE[@]})); then
				if [ "$final_value_type" = object ]; then
					bash_object.util.generate_vobject_name "$root_object_name" "$querytree_stack_string"
					local global_object_name="$REPLY"

					if bash_object.ensure.variable_does_not_exist "$global_object_name"; then :; else
						return
					fi

					if ! declare -gA "$global_object_name"; then
						bash_object.util.die 'ERROR_INTERNAL' "Could not declare variable '$global_object_name'"
						return
					fi
					local -n global_object="$global_object_name"
					global_object=()

					__current_object["$key"]=$'\x1C\x1D'"type=object;&$global_object_name"

					local -n ___object_to_copy_from="$final_value"

					for key in "${!___object_to_copy_from[@]}"; do
						# shellcheck disable=SC2034
						global_object["$key"]="${___object_to_copy_from[$key]}"
					done
				elif [ "$final_value_type" = array ]; then
					bash_object.util.generate_vobject_name "$root_object_name" "$querytree_stack_string"
					local global_array_name="$REPLY"

					if bash_object.ensure.variable_does_not_exist "$global_array_name"; then :; else
						return
					fi

					if ! declare -ga "$global_array_name"; then
						bash_object.util.die 'ERROR_INTERNAL' "Could not declare variable $global_object_name"
						return
					fi
					local -n global_array="$global_array_name"
					global_array=()

					__current_object["$key"]=$'\x1C\x1D'"type=array;&$global_array_name"

					local -n ___array_to_copy_from="$final_value"

					# shellcheck disable=SC2034
					global_array=("${___array_to_copy_from[@]}")
				elif [ "$final_value_type" = string ]; then
					local -n ___string_to_copy_from="$final_value"
					__current_object["$key"]="$___string_to_copy_from"
				else
					bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "Unexpected final_value_type '$final_value_type'"
					return
				fi
			fi
		# If 'key' is a valid member of an object or index of array
		else
			local key_value="${__current_object[$key]}"

			# If 'key_value' is a virtual object, dereference it
			if [ "${key_value::2}" = $'\x1C\x1D' ]; then
				if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
					bash_object.trace_print 2 "BLOCK: OBJECT/ARRAY"
				fi

				local old_current_object_name="$current_object_name"

				virtual_item="${key_value#??}"
				bash_object.parse_virtual_object "$virtual_item"
				local current_object_name="$REPLY1"
				local vmd_dtype="$REPLY2"
				local -n __current_object="$current_object_name"

				if [ -n "${VERIFY_BASH_OBJECT+x}" ]; then
					# Ensure the 'final_value' is the same type as specified by the user (WET)
					local __current_object_type=
					if ! __current_object_type="$(declare -p "$current_object_name" 2>/dev/null)"; then
						bash_object.util.die 'ERROR_INTERNAL' "The variable '$current_object_name' does not exist"
						return
					fi
					__current_object_type="${__current_object_type#declare -}"
					case "${__current_object_type::1}" in
						A) __current_object_type='object' ;;
						a) __current_object_type='array' ;;
						-) __current_object_type='string' ;;
						*) __current_object_type='other' ;;
					esac
					case "$vmd_dtype" in
					object)
						if [ "$__current_object_type" != object ]; then
							bash_object.util.die 'ERROR_VOBJ_INCORRECT_TYPE' "Virtual object has a reference of type '$vmd_dtype', but when dereferencing, a variable of type '$__current_object_type' was found"
							return
						fi
						;;
					array)
						if [ "$__current_object_type" != array ]; then
							bash_object.util.die 'ERROR_VOBJ_INCORRECT_TYPE' "Virtual object has a reference of type '$vmd_dtype', but when dereferencing, a variable of type '$__current_object_type' was found"
							return
						fi
						;;
					*)
						bash_object.util.die 'ERROR_VOBJ_INVALID_TYPE' "Unexpected vmd_dtype '$vmd_dtype'"
						return
						;;
					esac
				fi

				# Ensure no circular references (WET)
				if [ "$old_current_object_name" = "$current_object_name" ]; then
					bash_object.util.die 'ERROR_SELF_REFERENCE' "Virtual object '$current_object_name' cannot reference itself"
					return
				fi

				if ((i+1 < ${#REPLY_QUERYTREE[@]})); then
					# Do nothing, and continue to next element in query. We already check for the
					# validity of the virtual object above, so no need to do anything here
					:
				elif ((i+1 == ${#REPLY_QUERYTREE[@]})); then
					# We are last element of query, but do not set the object there is one that already exists
					if [ "$final_value_type" = object ]; then
						case "$vmd_dtype" in
						object) :;;
						array)
							bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Assigning an $final_value_type, but found existing $vmd_dtype"
							return
							;;
						*)
							bash_object.util.die 'ERROR_VOBJ_INVALID_TYPE' "Unexpected vmd_dtype '$vmd_dtype'"
							return
							;;
						esac
					elif [ "$final_value_type" = array ]; then
						case "$vmd_dtype" in
						object)
							bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Assigning an $final_value_type, but found existing $vmd_dtype"
							return
							;;
						array) :;;
						*)
							bash_object.util.die 'ERROR_VOBJ_INVALID_TYPE' "Unexpected vmd_dtype '$vmd_dtype'"
							return
							;;
						esac
					elif [ "$final_value_type" = string ]; then
						case "$vmd_dtype" in
						object)
							bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Assigning an $final_value_type, but found existing $vmd_dtype"
							return
							;;
						array)
							bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Assigning an $final_value_type, but found existing $vmd_dtype"
							return
							;;
						*)
							bash_object.util.die 'ERROR_VOBJ_INVALID_TYPE' "Unexpected vmd_dtype '$vmd_dtype'"
							return
							;;
						esac
					else
						bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "Unexpected final_value_type '$final_value_type'"
						return
					fi
				fi
			# Otherwise, 'key_value' is a string
			else
				if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
					bash_object.trace_print 2 "BLOCK: STRING"
				fi

				if ((i+1 < ${#REPLY_QUERYTREE[@]})); then
					bash_object.util.die 'ERROR_NOT_FOUND' "The passed querytree implies that '$key' accesses an object or array, but a string with a value of '$key_value' was found instead"
					return
				elif ((i+1 == ${#REPLY_QUERYTREE[@]})); then
					local value="${__current_object[$key]}"
					if [ "$final_value_type" = object ]; then
						bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Assigning an $final_value_type, but found existing string '$value'"
						return
					elif [ "$final_value_type" = array ]; then
						bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Assigning an $final_value_type, but found existing string '$value'"
						return
					elif [ "$final_value_type" = string ]; then
						local -n ___string_to_copy_from="$final_value"
						__current_object["$key"]="$___string_to_copy_from"
					else
						bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "Unexpected final_value_type '$final_value_type'"
						return
					fi
				fi
			fi
		fi

		bash_object.trace_current_object
		if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
			bash_object.trace_print 0 "END BLOCK"
		fi
	done; unset i
}
# shellcheck shell=bash

# @description Convert a user string into an array representing successive
# object / array access
# @exitcode 1 Miscellaneous error
# @exitcode 2 Parsing error
bash_object.parse_querytree() {
	declare -ga REPLY_QUERYTREE=()

	local flag_parser_type=

	local arg=
	for arg; do case $arg in
	--simple)
		flag_parser_type='simple'
		shift ;;
	--advanced)
		flag_parser_type='advanced'
		shift ;;
	esac done; unset -v arg

	local querytree="$1"

	if [ "$flag_parser_type" = 'simple' ]; then
		if [ "${querytree::1}" != . ]; then
			bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'Querytree must begin with a dot'
			return
		fi

		local old_ifs="$IFS"; IFS=.
		for key in $querytree; do
			if [ -z "$key" ]; then
				continue
			fi

			REPLY_QUERYTREE+=("$key")
		done
		IFS="$old_ifs"
	elif [ "$flag_parser_type" = 'advanced' ]; then
		local char=
		local mode='MODE_DEFAULT'
		local -i PARSER_COLUMN_NUMBER=0

		# Append dot so parsing does not fail at end
		# This makes parsing a lot easier, since it always expects a dot after a ']'
		querytree="${querytree}."

		# Reply represents an accessor (e.g. 'sub_key')
		local reply=

		while IFS= read -rN1 char; do
			PARSER_COLUMN_NUMBER+=1

			if [ -n "${TRACE_BASH_OBJECT_PARSE+x}" ]; then
				printf '%s\n' "-- $mode: '$char'" >&3
			fi

			case $mode in
			MODE_DEFAULT)
				if [ "$char" = . ]; then
					mode='MODE_EXPECTING_BRACKET'
				else
					bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'Querytree must begin with a dot'
					return
				fi
				;;
			MODE_BEFORE_DOT)
				if [ "$char" = . ]; then
					mode='MODE_EXPECTING_BRACKET'
				else
					bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'Each part in a querytree must be deliminated by a dot'
					return
				fi
				;;
			MODE_EXPECTING_BRACKET)
				if [ "$char" = \[ ]; then
					mode='MODE_EXPECTING_OPENING_STRING_OR_NUMBER'
				elif [ "$char" = $'\n' ]; then
					return
				else
					bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'A dot MUST be followed by an opening bracket in this mode'
					return
				fi
				;;
			MODE_EXPECTING_OPENING_STRING_OR_NUMBER)
				reply=

				if [ "$char" = \" ]; then
					mode='MODE_EXPECTING_STRING'
				elif [ "$char" = ']' ]; then
					bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'Key cannot be empty'
					return
				else
					case "$char" in
					0|1|2|3|4|5|6|7|8|9)
						reply=$'\x1C'"$char"
						mode='MODE_EXPECTING_READ_NUMBER'
						;;
					*)
						bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'A number or opening quote must follow an open bracket'
						return
						;;
					esac
				fi
				;;
			MODE_EXPECTING_STRING)
				if [ "$char" = \\ ]; then
					mode='MODE_STRING_ESCAPE_SEQUENCE'
				elif [ "$char" = \" ]; then
					if [ -z "$reply" ]; then
						bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'Key cannot be empty'
						return
					fi

					REPLY_QUERYTREE+=("$reply")
					mode='MODE_EXPECTING_CLOSING_BRACKET'
				elif [ "$char" = $'\n' ]; then
					bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'Querytree is not complete'
					return
				else
					reply+="$char"
				fi
				;;
			MODE_STRING_ESCAPE_SEQUENCE)
				case "$char" in
					\\) reply+=\\ ;;
					\") reply+=\" ;;
					']') reply+=']' ;;
					*)
						bash_object.util.die 'ERROR_QUERYTREE_INVALID' "Escape sequence of '$char' not valid"
						return
						;;
				esac
				mode='MODE_EXPECTING_STRING'
				;;
			MODE_EXPECTING_READ_NUMBER)
				if [ "$char" = ']' ]; then
					REPLY_QUERYTREE+=("$reply")
					mode='MODE_BEFORE_DOT'
				else
					case "$char" in
					0|1|2|3|4|5|6|7|8|9)
						reply+="$char"
						;;
					*)
						bash_object.util.die 'ERROR_QUERYTREE_INVALID' "Expecting number, found '$char'"
						return
						;;
					esac
				fi
				;;
			MODE_EXPECTING_CLOSING_BRACKET)
				if [ "$char" = ']' ]; then
					mode='MODE_BEFORE_DOT'
				else
					bash_object.util.die 'ERROR_QUERYTREE_INVALID' 'Expected a closing bracket after the closing quotation mark'
					return
				fi
				;;
			esac
		done <<< "$querytree"
	else
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Must pass either '--simple' or '--advanced'"
		return
	fi
}

# @description Parse a virtual object into its components
bash_object.parse_virtual_object() {
	REPLY1=; REPLY2=
	local virtual_object="$1"

	local virtual_metadatas="${virtual_object%%&*}" # type=string;attr=smthn;
	local virtual_object_name="${virtual_object#*&}" # __bash_object_383028

	if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
		bash_object.trace_print 2 "virtual_object: '$virtual_object'"
		bash_object.trace_print 2 "virtual_metadatas: '$virtual_metadatas'"
		bash_object.trace_print 2 "virtual_object_name: '$virtual_object_name'"
	fi

	# Parse info about the virtual object
	local vmd= vmd_key= vmd_value= vmd_dtype=
	while IFS= read -rd \; vmd; do
		if [ -z "$vmd" ]; then
			continue
		fi

		vmd="${vmd%;}"
		vmd_key="${vmd%%=*}"
		vmd_value="${vmd#*=}"

		if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
			bash_object.trace_print 2 "vmd: '$vmd'"
			bash_object.trace_print 3 "vmd_key: '$vmd_key'"
			bash_object.trace_print 3 "vmd_value: '$vmd_value'"
		fi

		case "$vmd_key" in
			type) vmd_dtype="$vmd_value" ;;
		esac
	done <<< "$virtual_metadatas"

	REPLY1=$virtual_object_name
	REPLY2=$vmd_dtype
}
# shellcheck shell=bash

bobject.print() {
	local object_name="$1"

	if [ -z "$object_name" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' 'Positional parameter 1 is empty. Please check passed parameters'
		return
	fi

	if declare -p "$object_name" &>/dev/null; then :; else
		bash_object.util.die 'ERROR_NOT_FOUND' "The variable '$object_name' does not exist"
		return
	fi

	bash_object.util.print_hierarchy "$object_name" 0
}
# shellcheck shell=bash

bobject.unset() {
	local object_name="$1"

	if [ -z "$object_name" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' 'Positional parameter 1 is empty. Please check passed parameters'
		return
	fi

	if declare -p "$object_name" &>/dev/null; then :; else
		bash_object.util.die 'ERROR_NOT_FOUND' "The variable '$object_name' does not exist"
		return
	fi

	bash_object.util.unset "$object_name"
}
# shellcheck shell=bash

bobject() {
	local subcmd="$1"
	if ! shift; then
		bash_object.util.die 'ERROR_INTERNAL' 'Shift failed, but was expected to succeed'
		return
	fi

	case $subcmd in
		get-string)
			bash_object.traverse-get string "$@"
			;;
		get-array)
			bash_object.traverse-get array "$@"
			;;
		get-object)
			bash_object.traverse-get object "$@"
			;;
		set-string)
			bash_object.traverse-set string "$@"
			;;
		set-array)
			bash_object.traverse-set array "$@"
			;;
		set-object)
			bash_object.traverse-set object "$@"
			;;
		*)
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Subcommand '$subcmd' not recognized"
			return
	esac
}
# shellcheck shell=bash

bash_object.traverse-get() {
	unset REPLY; REPLY=

	if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
		bash_object.trace_print 0 ''
		bash_object.trace_print 0 "CALL: bash_object.traverse-get: $*"
	fi

	local flag_as_what=
	local -a args=()

	local arg=
	for arg; do case $arg in
	--ref)
		if [ -n "$flag_as_what" ]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Flags '--ref' and '--value' are mutually exclusive"
			return
		fi
		flag_as_what='as-ref'
		;;
	--value)
		if [ -n "$flag_as_what" ]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Flags '--ref' and '--value' are mutually exclusive"
			return
		fi
		flag_as_what='as-value'
		;;
	--)
		break
		;;
	*)
		args+=("$arg")
		;;
	esac done; unset -v arg

	if [ -z "$flag_as_what" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Must pass either the '--ref' or '--value' flag"
		return
	fi

	# Ensure correct number of arguments have been passed
	if (( ${#args[@]} != 3)); then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Expected 3 arguments, but received ${#args[@]}"
		return
	fi

	# Ensure parameters are not empty
	if [ -z "${args[0]}" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Positional parameter 1 is empty. Please check passed parameters"
		return
	fi
	if [ -z "${args[1]}" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Positional parameter 2 is empty. Please check passed parameters"
		return
	fi
	if [ -z "${args[2]}" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Positional parameter 3 is empty. Please check passed parameters"
		return
	fi

	local final_value_type="${args[0]}"
	local root_object_name="${args[1]}"
	local querytree="${args[2]}"

	# Start traversing at the root object
	local current_object_name="$root_object_name"
	local -n __current_object="$root_object_name"
	local vmd_dtype=

	# A stack of all the evaluated querytree elements
	# local -a querytree_stack=()

	# Parse the querytree, and recurse over their elements
	case "$querytree" in
		*']'*) bash_object.parse_querytree --advanced "$querytree" ;;
		*) bash_object.parse_querytree --simple "$querytree" ;;
	esac
	local i=
	for ((i=0; i<${#REPLY_QUERYTREE[@]}; i++)); do
		local key="${REPLY_QUERYTREE[$i]}"

		local is_index_of_array='no'
		if [ "${key::1}" = $'\x1C' ]; then
			key="${key#?}"
			is_index_of_array='yes'
		fi

		# querytree_stack+=("$key")
		# bash_object.util.generate_querytree_stack_string
		# local querytree_stack_string="$REPLY"

		bash_object.trace_loop

		# If the past vmd_dtype is an array and 'key' is not a number
		if [[ $vmd_dtype == 'array' && $key == *[!0-9]* ]]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Cannot index an array with a non-integer ($key)"
			return
		# If the past vmd_dtype is an array and 'key' is a number
		elif [[ $vmd_dtype == 'object' && $key != *[!0-9]* ]]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Cannot index an object with an integer ($key)"
			return
		# If 'key' is not a member of object or index of array, error
		elif [ -z "${__current_object[$key]+x}" ]; then
			bash_object.util.die 'ERROR_NOT_FOUND' "Key or index '$key' (querytree index '$i') does not exist"
			return
		# If 'key' is a valid member of an object or index of array
		else
			local key_value="${__current_object[$key]}"

			# If 'key_value' is a virtual object, dereference it
			if [ "${key_value::2}" = $'\x1C\x1D' ]; then
				if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
					bash_object.trace_print 2 "BLOCK: OBJECT/ARRAY"
				fi

				local old_current_object_name="$current_object_name"

				virtual_item="${key_value#??}"
				bash_object.parse_virtual_object "$virtual_item"
				local current_object_name="$REPLY1"
				local vmd_dtype="$REPLY2"
				local -n __current_object="$current_object_name"

				if [ -n "${VERIFY_BASH_OBJECT+x}" ]; then
					# Ensure the 'final_value' is the same type as specified by the user (WET)
					local __current_object_type=
					if ! __current_object_type="$(declare -p "$current_object_name" 2>/dev/null)"; then
						bash_object.util.die 'ERROR_INTERNAL' "The variable '$current_object_name' does not exist"
						return
					fi
					__current_object_type="${__current_object_type#declare -}"
					case "${__current_object_type::1}" in
						A) __current_object_type='object' ;;
						a) __current_object_type='array' ;;
						-) __current_object_type='string' ;;
						*) __current_object_type='other' ;;
					esac
					case "$vmd_dtype" in
					object)
						if [ "$__current_object_type" != object ]; then
							bash_object.util.die 'ERROR_VOBJ_INCORRECT_TYPE' "Virtual object has a reference of type '$vmd_dtype', but when dereferencing, a variable of type '$__current_object_type' was found"
							return
						fi
						;;
					array)
						if [ "$__current_object_type" != array ]; then
							bash_object.util.die 'ERROR_VOBJ_INCORRECT_TYPE' "Virtual object has a reference of type '$vmd_dtype', but when dereferencing, a variable of type '$__current_object_type' was found"
							return
						fi
						;;
					*)
						bash_object.util.die 'ERROR_VOBJ_INVALID_TYPE' "Unexpected vmd_dtype '$vmd_dtype'"
						return
						;;
					esac
				fi

				# Ensure no circular references (WET)
				if [ "$old_current_object_name" = "$current_object_name" ]; then
					bash_object.util.die 'ERROR_SELF_REFERENCE' "Virtual object '$current_object_name' cannot reference itself"
					return
				fi

				if ((i+1 < ${#REPLY_QUERYTREE[@]})); then
					# Do nothing, and continue to next element in query. We already check for the
					# validity of the virtual object above, so no need to do anything here
					:
				elif ((i+1 == ${#REPLY_QUERYTREE[@]})); then
					# We are last element of query, return the object
					if [ "$final_value_type" = object ]; then
						case "$vmd_dtype" in
						object)
							if [ "$flag_as_what" = 'as-value' ]; then
								declare -gA REPLY=()
								local key=
								for key in "${!__current_object[@]}"; do
									REPLY["$key"]="${__current_object[$key]}"
								done
							elif [ "$flag_as_what" = 'as-ref' ]; then
								bash_object.util.die 'ERROR_INTERNAL' "--ref not implemented"
								return
								# declare -gn REPLY="$current_object_name"
							else
								bash_object.util.die 'ERROR_INTERNAL' "Unexpected flag_as_what '$flag_as_what'"
								return
							fi
							;;
						array)
							bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Queried for object, but found existing $vmd_dtype"
							return
							;;
						*)
							bash_object.util.die 'ERROR_VOBJ_INVALID_TYPE' "Unexpected vmd_dtype '$vmd_dtype'"
							return
							;;
						esac
					elif [ "$final_value_type" = array ]; then
						case "$vmd_dtype" in
						object)
							bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Queried for array, but found existing $vmd_dtype"
							return
							;;
						array)
							if [ "$flag_as_what" = 'as-value' ]; then
								declare -ga REPLY=()
								# shellcheck disable=SC2190
								REPLY=("${__current_object[@]}")
							elif [ "$flag_as_what" = 'as-ref' ]; then
								bash_object.util.die 'ERROR_INTERNAL' "--ref not implemented"
								return
							else
								bash_object.util.die 'ERROR_INTERNAL' "Unexpected flag_as_what '$flag_as_what'"
								return
							fi
							;;
						*)
							bash_object.util.die 'ERROR_VOBJ_INVALID_TYPE' "Unexpected vmd_dtype '$vmd_dtype'"
							return
							;;
						esac
					elif [ "$final_value_type" = string ]; then
						case "$vmd_dtype" in
						object)
							bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Queried for string, but found existing $vmd_dtype"
							return
							;;
						array)
							bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Queried for string, but found existing $vmd_dtype"
							return
							;;
						*)
							bash_object.util.die 'ERROR_VOBJ_INVALID_TYPE' "Unexpected vmd_dtype '$vmd_dtype'"
							return
						esac
					else
						bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "Unexpected final_value_type '$final_value_type'"
						return
					fi
				fi
			# Otherwise, 'key_value' is a string
			else
				if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
					bash_object.trace_print 2 "BLOCK: STRING"
				fi

				if ((i+1 < ${#REPLY_QUERYTREE[@]})); then
					bash_object.util.die 'ERROR_NOT_FOUND' "The passed querytree implies that '$key' accesses an object or array, but a string with a value of '$key_value' was found instead"
					return
				elif ((i+1 == ${#REPLY_QUERYTREE[@]})); then
					local value="${__current_object[$key]}"
					if [ "$final_value_type" = object ]; then
						bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Queried for $final_value_type, but found existing string '$value'"
						return
					elif [ "$final_value_type" = array ]; then
						bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Queried for $final_value_type, but found existing string '$value'"
						return
					elif [ "$final_value_type" = string ]; then
						if [ "$flag_as_what" = 'as-value' ]; then
							# shellcheck disable=SC2178
							REPLY="$value"
						elif [ "$flag_as_what" = 'as-ref' ]; then
							bash_object.util.die 'ERROR_INTERNAL' "--ref not implemented"
							return
						else
							bash_object.util.die 'ERROR_INTERNAL' "Unexpected flag_as_what '$flag_as_what'"
							return
						fi

					fi
				fi
			fi
		fi

		bash_object.trace_current_object
		if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
			bash_object.trace_print 0 "END BLOCK"
		fi
	done; unset i
}
# shellcheck shell=bash

bash_object.traverse-set() {
	if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
		bash_object.trace_print 0 ''
		bash_object.trace_print 0 "CALL: bash_object.traverse-set: $*"
	fi

	local flag_pass_by_what=
	local -a args=()

	local arg=
	for arg; do case $arg in
	--ref)
		if [ -n "$flag_pass_by_what" ]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Flags '--ref' and '--value' are mutually exclusive"
			return
		fi
		flag_pass_by_what='by-ref'
		;;
	--value)
		if [ -n "$flag_pass_by_what" ]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Flags '--ref' and '--value' are mutually exclusive"
			return
		fi
		flag_pass_by_what='by-value'
		;;
	--)
		# All arguments after '--' are in '$@'
		break
		;;
	*)
		args+=("$arg")
		;;
	esac; if ! shift; then
		bash_object.util.die 'ERROR_INTERNAL' 'Shift failed, but was expected to succeed'
		return
	fi; done; unset -v arg

	if [ -z "$flag_pass_by_what" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Must pass either the '--ref' or '--value' flag"
		return
	fi

	if [ "$flag_pass_by_what" = 'by-ref' ]; then
		if (( ${#args[@]} != 4)); then
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Expected 4 arguments (with --ref), but received ${#args[@]}"
			return
		fi
	elif [ "$flag_pass_by_what" = 'by-value' ]; then
		if (( ${#args[@]} != 3)); then
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Expected 3 arguments (with --value) before '--', but received ${#args[@]})"
			return
		fi
	else
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Unexpected final_value_type '$final_value_type'"
		return
	fi

	local final_value_type="${args[0]}"
	local root_object_name="${args[1]}"
	local querytree="${args[2]}"

	# Ensure parameters are not empty
	if [ -z "$final_value_type" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Positional parameter 1 is empty. Please check passed parameters"
		return
	fi
	if [ -z "$root_object_name" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Positional parameter 2 is empty. Please check passed parameters"
		return
	fi
	if [ -z "$querytree" ]; then
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Positional parameter 3 is empty. Please check passed parameters"
		return
	fi

	# Set final_value after we ensure 'final_value_type' is non-empty
	local final_value=
	if [ "$flag_pass_by_what" = 'by-ref' ]; then
		final_value="${args[3]}"

		if [ -z "$final_value" ]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Positional parameter 4 is empty. Please check passed parameters"
			return
		fi
	elif [ "$flag_pass_by_what" = 'by-value' ]; then
		if [ "$final_value_type" = object ]; then
			final_value="__bash_object_${RANDOM}_$RANDOM"
			local -A "$final_value"
			local -n final_value_ref="$final_value"
			final_value_ref=()

			if [ "$1" != -- ]; then
				bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Must pass '--' and the value when using --value"
				return
			fi
			shift

			if (( $# & 1 )); then
				bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "When passing --value with set-object, an even number of values must be passed after the '--'"
				return
			fi

			while (( $# )); do
				local key="$1"
				if ! shift; then
					bash_object.util.die 'ERROR_INTERNAL' 'Shift failed, but was expected to succeed'
					return
				fi

				local value="$1"
				if ! shift; then
					bash_object.util.die 'ERROR_INTERNAL' 'Shift failed, but was expected to succeed'
					return
				fi

				final_value_ref["$key"]="$value"
			done; unset key value
		elif [ "$final_value_type" = array ]; then
			local -a final_value="__bash_object_${RANDOM}_$RANDOM"
			local -n final_value_ref="$final_value"
			if [ "$1" != -- ]; then
				bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Must pass '--' and the value when using --value"
				return
			fi
			shift

			final_value_ref=("$@")
		elif [ "$final_value_type" = string ]; then
			local final_value="__bash_object_${RANDOM}_$RANDOM"
			local -n final_value_ref="$final_value"
			if [ "$1" != -- ]; then
				bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Must pass '--' and the value when using --value"
				return
			fi
			shift

			if (( $# > 1)); then
				bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "When passing --value with set-string, only one value must be passed after the '--'"
				return
			fi
			final_value_ref="$1"
		else
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Unexpected final_value_type '$final_value_type'"
			return
		fi
	else
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID' "Unexpected final_value_type '$final_value_type'"
		return
	fi

	if [ -z "$final_value" ]; then
		bash_object.util.die 'ERROR_INTERNAL' "Variable 'final_value' is empty"
		return
	fi

	if [ -n "${VERIFY_BASH_OBJECT+x}" ]; then
		# Ensure the root object exists, and is an associative array
		local root_object_type=
		if root_object_type="$(declare -p "$root_object_name" 2>/dev/null)"; then :; else
			bash_object.util.die 'ERROR_NOT_FOUND' "The associative array '$root_object_name' does not exist"
			return
		fi
		root_object_type="${root_object_type#declare -}"
		if [ "${root_object_type::1}" != 'A' ]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "The 'root object' must be an associative array"
			return
		fi

		if [ "$flag_pass_by_what" = 'by-ref' ]; then
			# Ensure the 'final_value' is the same type as specified by the user
			local actual_final_value_type=
			if ! actual_final_value_type="$(declare -p "$final_value" 2>/dev/null)"; then
				bash_object.util.die 'ERROR_NOT_FOUND' "The variable '$final_value' does not exist"
				return
			fi
			actual_final_value_type="${actual_final_value_type#declare -}"
			case "${actual_final_value_type::1}" in
				A) actual_final_value_type='object' ;;
				a) actual_final_value_type='array' ;;
				-) actual_final_value_type='string' ;;
				*) actual_final_value_type='other' ;;
			esac

			if [ "$final_value_type" = object ]; then
				if [ "$actual_final_value_type" != object ]; then
					bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "Argument 'set-$final_value_type' was specified, but a variable with type '$actual_final_value_type' was passed"
					return
				fi
			elif [ "$final_value_type" = array ]; then
				if [ "$actual_final_value_type" != array ]; then
					bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "Argument 'set-$final_value_type' was specified, but a variable with type '$actual_final_value_type' was passed"
					return
				fi
			elif [ "$final_value_type" = string ]; then
				if [ "$actual_final_value_type" != string ]; then
					bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "Argument 'set-$final_value_type' was specified, but a variable with type '$actual_final_value_type' was passed"
					return
				fi
			else
				bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "Unexpected final_value_type '$final_value_type'"
				return
			fi
		fi
	fi

	# Start traversing at the root object
	local current_object_name="$root_object_name"
	local -n __current_object="$root_object_name"
	local vmd_dtype=

	# A stack of all the evaluated querytree elements
	local -a querytree_stack=()

	# Parse the querytree, and recurse over their elements
	case "$querytree" in
		*']'*) bash_object.parse_querytree --advanced "$querytree" ;;
		*) bash_object.parse_querytree --simple "$querytree" ;;
	esac
	local i=
	for ((i=0; i<${#REPLY_QUERYTREE[@]}; i++)); do
		local key="${REPLY_QUERYTREE[$i]}"

		local is_index_of_array='no'
		if [ "${key::1}" = $'\x1C' ]; then
			key="${key#?}"
			is_index_of_array='yes'
		fi

		querytree_stack+=("$key")
		bash_object.util.generate_querytree_stack_string
		local querytree_stack_string="$REPLY"

		bash_object.trace_loop

		# If the past vmd_dtype is an array and 'key' is not a number
		if [[ $vmd_dtype == 'array' && $key == *[!0-9]* ]]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Cannot index an array with a non-integer ($key)"
			return
		# If the past vmd_dtype is an array and 'key' is a number
		elif [[ $vmd_dtype == 'object' && $key != *[!0-9]* ]]; then
			bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Cannot index an object with an integer ($key)"
			return
		# If 'key' is not a member of object or index of array, error
		elif [ -z "${__current_object[$key]+x}" ]; then
			# If we are before the last element in the query, then error
			if ((i+1 < ${#REPLY_QUERYTREE[@]})); then
				bash_object.util.die 'ERROR_NOT_FOUND' "Key or index '$key' (querytree index '$i') does not exist"
				return
			# If we are at the last element in the query, and it doesn't exist, create it
			elif ((i+1 == ${#REPLY_QUERYTREE[@]})); then
				if [ "$final_value_type" = object ]; then
					bash_object.util.generate_vobject_name "$root_object_name" "$querytree_stack_string"
					local global_object_name="$REPLY"

					if bash_object.ensure.variable_does_not_exist "$global_object_name"; then :; else
						return
					fi

					if ! declare -gA "$global_object_name"; then
						bash_object.util.die 'ERROR_INTERNAL' "Could not declare variable '$global_object_name'"
						return
					fi
					local -n global_object="$global_object_name"
					global_object=()

					__current_object["$key"]=$'\x1C\x1D'"type=object;&$global_object_name"

					local -n ___object_to_copy_from="$final_value"

					for key in "${!___object_to_copy_from[@]}"; do
						# shellcheck disable=SC2034
						global_object["$key"]="${___object_to_copy_from[$key]}"
					done
				elif [ "$final_value_type" = array ]; then
					bash_object.util.generate_vobject_name "$root_object_name" "$querytree_stack_string"
					local global_array_name="$REPLY"

					if bash_object.ensure.variable_does_not_exist "$global_array_name"; then :; else
						return
					fi

					if ! declare -ga "$global_array_name"; then
						bash_object.util.die 'ERROR_INTERNAL' "Could not declare variable $global_object_name"
						return
					fi
					local -n global_array="$global_array_name"
					global_array=()

					__current_object["$key"]=$'\x1C\x1D'"type=array;&$global_array_name"

					local -n ___array_to_copy_from="$final_value"

					# shellcheck disable=SC2034
					global_array=("${___array_to_copy_from[@]}")
				elif [ "$final_value_type" = string ]; then
					local -n ___string_to_copy_from="$final_value"
					__current_object["$key"]="$___string_to_copy_from"
				else
					bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "Unexpected final_value_type '$final_value_type'"
					return
				fi
			fi
		# If 'key' is a valid member of an object or index of array
		else
			local key_value="${__current_object[$key]}"

			# If 'key_value' is a virtual object, dereference it
			if [ "${key_value::2}" = $'\x1C\x1D' ]; then
				if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
					bash_object.trace_print 2 "BLOCK: OBJECT/ARRAY"
				fi

				local old_current_object_name="$current_object_name"

				virtual_item="${key_value#??}"
				bash_object.parse_virtual_object "$virtual_item"
				local current_object_name="$REPLY1"
				local vmd_dtype="$REPLY2"
				local -n __current_object="$current_object_name"

				if [ -n "${VERIFY_BASH_OBJECT+x}" ]; then
					# Ensure the 'final_value' is the same type as specified by the user (WET)
					local __current_object_type=
					if ! __current_object_type="$(declare -p "$current_object_name" 2>/dev/null)"; then
						bash_object.util.die 'ERROR_INTERNAL' "The variable '$current_object_name' does not exist"
						return
					fi
					__current_object_type="${__current_object_type#declare -}"
					case "${__current_object_type::1}" in
						A) __current_object_type='object' ;;
						a) __current_object_type='array' ;;
						-) __current_object_type='string' ;;
						*) __current_object_type='other' ;;
					esac
					case "$vmd_dtype" in
					object)
						if [ "$__current_object_type" != object ]; then
							bash_object.util.die 'ERROR_VOBJ_INCORRECT_TYPE' "Virtual object has a reference of type '$vmd_dtype', but when dereferencing, a variable of type '$__current_object_type' was found"
							return
						fi
						;;
					array)
						if [ "$__current_object_type" != array ]; then
							bash_object.util.die 'ERROR_VOBJ_INCORRECT_TYPE' "Virtual object has a reference of type '$vmd_dtype', but when dereferencing, a variable of type '$__current_object_type' was found"
							return
						fi
						;;
					*)
						bash_object.util.die 'ERROR_VOBJ_INVALID_TYPE' "Unexpected vmd_dtype '$vmd_dtype'"
						return
						;;
					esac
				fi

				# Ensure no circular references (WET)
				if [ "$old_current_object_name" = "$current_object_name" ]; then
					bash_object.util.die 'ERROR_SELF_REFERENCE' "Virtual object '$current_object_name' cannot reference itself"
					return
				fi

				if ((i+1 < ${#REPLY_QUERYTREE[@]})); then
					# Do nothing, and continue to next element in query. We already check for the
					# validity of the virtual object above, so no need to do anything here
					:
				elif ((i+1 == ${#REPLY_QUERYTREE[@]})); then
					# We are last element of query, but do not set the object there is one that already exists
					if [ "$final_value_type" = object ]; then
						case "$vmd_dtype" in
						object) :;;
						array)
							bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Assigning an $final_value_type, but found existing $vmd_dtype"
							return
							;;
						*)
							bash_object.util.die 'ERROR_VOBJ_INVALID_TYPE' "Unexpected vmd_dtype '$vmd_dtype'"
							return
							;;
						esac
					elif [ "$final_value_type" = array ]; then
						case "$vmd_dtype" in
						object)
							bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Assigning an $final_value_type, but found existing $vmd_dtype"
							return
							;;
						array) :;;
						*)
							bash_object.util.die 'ERROR_VOBJ_INVALID_TYPE' "Unexpected vmd_dtype '$vmd_dtype'"
							return
							;;
						esac
					elif [ "$final_value_type" = string ]; then
						case "$vmd_dtype" in
						object)
							bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Assigning an $final_value_type, but found existing $vmd_dtype"
							return
							;;
						array)
							bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Assigning an $final_value_type, but found existing $vmd_dtype"
							return
							;;
						*)
							bash_object.util.die 'ERROR_VOBJ_INVALID_TYPE' "Unexpected vmd_dtype '$vmd_dtype'"
							return
							;;
						esac
					else
						bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "Unexpected final_value_type '$final_value_type'"
						return
					fi
				fi
			# Otherwise, 'key_value' is a string
			else
				if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
					bash_object.trace_print 2 "BLOCK: STRING"
				fi

				if ((i+1 < ${#REPLY_QUERYTREE[@]})); then
					bash_object.util.die 'ERROR_NOT_FOUND' "The passed querytree implies that '$key' accesses an object or array, but a string with a value of '$key_value' was found instead"
					return
				elif ((i+1 == ${#REPLY_QUERYTREE[@]})); then
					local value="${__current_object[$key]}"
					if [ "$final_value_type" = object ]; then
						bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Assigning an $final_value_type, but found existing string '$value'"
						return
					elif [ "$final_value_type" = array ]; then
						bash_object.util.die 'ERROR_ARGUMENTS_INCORRECT_TYPE' "Assigning an $final_value_type, but found existing string '$value'"
						return
					elif [ "$final_value_type" = string ]; then
						local -n ___string_to_copy_from="$final_value"
						__current_object["$key"]="$___string_to_copy_from"
					else
						bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "Unexpected final_value_type '$final_value_type'"
						return
					fi
				fi
			fi
		fi

		bash_object.trace_current_object
		if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
			bash_object.trace_print 0 "END BLOCK"
		fi
	done; unset i
}
# shellcheck shell=bash

# @description Ensure the variable already exists
bash_object.ensure.variable_does_exist() {
	local variable_name="$1"

	if [ -z "$variable_name" ]; then
		bash_object.util.die 'ERROR_INTERNAL' "Parameter to function 'bash_object.ensure.variable_does_exist' was empty"
		return
	fi

	if ! declare -p "$variable_name" &>/dev/null; then
		bash_object.util.die 'ERROR_INTERNAL' "Variable '$variable_name' does not exist, but it should"
		return
	fi
}

# @description Ensure the variable does not exist
bash_object.ensure.variable_does_not_exist() {
	local variable_name="$1"

	if [ -z "$variable_name" ]; then
		bash_object.util.die 'ERROR_INTERNAL' "Parameter to function 'bash_object.ensure.variable_does_not_exist' was empty"
		return
	fi

	if declare -p "$variable_name" &>/dev/null; then
		bash_object.util.die 'ERROR_INTERNAL' "Variable '$variable_name' exists, but it shouldn't"
		return
	fi
}
# shellcheck shell=bash

bash_object.trace_loop() {
	if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
		bash_object.trace_print 0 "-- START LOOP ITERATION"
		bash_object.trace_print 0 "i+1: '$((i+1))'"
		bash_object.trace_print 0 "\${#REPLY_QUERYTREE[@]}: ${#REPLY_QUERYTREE[@]}"
		bash_object.trace_print 0 "key: '$key'"
		bash_object.trace_print 0 "current_object_name: '$current_object_name'"
		bash_object.trace_print 0 "current_object=("
		for debug_key in "${!current_object[@]}"; do
			bash_object.trace_print 0 "  [$debug_key]='${current_object[$debug_key]}'"
		done
		bash_object.trace_print 0 ")"
	fi
}

bash_object.trace_current_object() {
	if [ -n "${TRACE_BASH_OBJECT_TRAVERSE+x}" ]; then
		bash_object.trace_print 0 "key: '$key'"
		bash_object.trace_print 0 "current_object_name: '$current_object_name'"
		bash_object.trace_print 0 "current_object=("
		for debug_key in "${!current_object[@]}"; do
			bash_object.trace_print 0 "  [$debug_key]='${current_object[$debug_key]}'"
		done
		bash_object.trace_print 0 ")"
	fi
}

bash_object.trace_print() {
	local level="$1"
	local message="$2"

	local padding=
	case "$level" in
		0) padding= ;;
		1) padding="  " ;;
		2) padding="    " ;;
		3) padding="      " ;;
	esac

	printf '%s\n' "TRACE $level: $padding| $message" >&3
}
# shellcheck shell=bash

# shellcheck disable=SC2192,SC2034
declare -gA ERRORS_BASH_OBJECT=(
	[ERROR_NOT_FOUND]=
	[ERROR_INTERNAL]=
	[ERROR_SELF_REFERENCE]="A virtual object cannot reference itself"

	[ERROR_ARGUMENTS_INVALID]="Wrong number, empty, or missing required arguments to function"
	[ERROR_ARGUMENTS_INVALID_TYPE]="The type of the final value specified by the user is neither 'object', 'array', nor 'string'"
	[ERROR_ARGUMENTS_INCORRECT_TYPE]="The type of the final value does not match that of the actual final value (at end of query string). Or, the type implied by your query string does not match up with the queried object"

	[ERROR_QUERYTREE_INVALID]="The querytree could not be parsed"

	[ERROR_VOBJ_INVALID_TYPE]="The type of the virtual object is neither 'object' nor 'array'"
	[ERROR_VOBJ_INCORRECT_TYPE]="The type of the virtual object does not match with the type of the variable it references"
)

bash_object.util.die() {
	local error_key="$1"
	local error_context="${2:-<empty>}"

	local error_output=
	case "$error_key" in
	ERROR_QUERYTREE_INVALID)
		printf -v error_output 'Failed to parse querytree:
  -> code: %s
  -> context: %s
  -> PARSER_COLUMN_NUMBER: %s
' "$error_key" "$error_context" "$PARSER_COLUMN_NUMBER"
		;;
	*)
		printf -v error_output 'Failed to perform operation:
  -> code: %s
  -> context: %s
' "$error_key" "$error_context"
		;;
	esac

	printf '%s' "$error_output"
	return 2
}

bash_object.util.generate_vobject_name() {
	unset REPLY

	local root_object_name="$1"
	local root_object_query="$2"

	local random_string=
	if ((BASH_VERSINFO[0] >= 6)) || ((BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1)); then
		random_string="${SRANDOM}_${SRANDOM}_${SRANDOM}_${SRANDOM}_${SRANDOM}"
	else
		random_string="${RANDOM}_${RANDOM}_${RANDOM}_${RANDOM}_${RANDOM}"
	fi

	printf -v REPLY '%q' "__bash_object_${root_object_name}___${root_object_query}_${random_string}"
}

# @description Prints the contents of a particular variable or vobject
bash_object.util.print_hierarchy() {
	local object_name="$1"
	local current_indent="$2"

	if object_type="$(declare -p "$object_name" 2>/dev/null)"; then :; else
		bash_object.util.die 'ERROR_NOT_FOUND' "The variable '$object_name' does not exist"
		return
	fi
	object_type="${object_type#declare -}"

	local -n _object="$object_name"
	if [ "${object_type::1}" = 'A' ]; then
		for object_key in "${!_object[@]}"; do
			local object_value="${_object[$object_key]}"
			if [ "${object_value::2}" = $'\x1C\x1D' ]; then
				# object_value is a vobject
				bash_object.parse_virtual_object "$object_value"
				local virtual_object_name="$REPLY1"
				local vmd_dtype="$REPLY2"

				printf '%*s' "$current_indent" ''
				printf '%s\n' "|__ $object_key ($virtual_object_name)"

				bash_object.util.print_hierarchy "$virtual_object_name" $((current_indent+3))
			else
				# object_value is a string
				printf '%*s' "$current_indent" ''
				printf '%s\n' "|__ $object_key: $object_value"
			fi
		done; unset object_key
	elif [ "${object_type::1}" = 'a' ]; then
		for object_value in "${_object[@]}"; do
			# object_value is a vobject
			if [ "${object_value::2}" = $'\x1C\x1D' ]; then
				bash_object.parse_virtual_object "$object_value"
				local virtual_object_name="$REPLY1"
				local vmd_dtype="$REPLY2"

				printf '%*s' "$current_indent" ''
				printf '%s\n' "|- $object_value ($virtual_object_name)"

				bash_object.util.print_hierarchy "$virtual_object_name" $((current_indent+2))
			else
				printf '%*s' "$current_indent" ''
				printf '%s\n' "|- $object_value"
			fi
		done
	else
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "The type of the named object ($object_name) is neither an array nor an object"
		return
	fi
}

# @description Prints the contents of a particular variable or vobject
bash_object.util.unset() {
	local object_name="$1"

	if object_type="$(declare -p "$object_name" 2>/dev/null)"; then :; else
		bash_object.util.die 'ERROR_NOT_FOUND' "The variable '$object_name' does not exist"
		return
	fi
	object_type="${object_type#declare -}"

	local -n _object="$object_name"
	if [ "${object_type::1}" = 'A' ]; then
		for object_key in "${!_object[@]}"; do
			local object_value="${_object[$object_key]}"
			if [ "${object_value::2}" = $'\x1C\x1D' ]; then
				# object_value is a vobject
				bash_object.parse_virtual_object "$object_value"
				local virtual_object_name="$REPLY1"
				local vmd_dtype="$REPLY2"

				bash_object.util.unset "$virtual_object_name"
				unset "$virtual_object_name"
			fi
		done; unset object_key
	elif [ "${object_type::1}" = 'a' ]; then
		for object_value in "${_object[@]}"; do
			# object_value is a vobject
			if [ "${object_value::2}" = $'\x1C\x1D' ]; then
				bash_object.parse_virtual_object "$object_value"
				local virtual_object_name="$REPLY1"
				local vmd_dtype="$REPLY2"

				bash_object.util.unset "$virtual_object_name"
				unset "$virtual_object_name"
			fi
		done
	else
		bash_object.util.die 'ERROR_ARGUMENTS_INVALID_TYPE' "The type of the named object ($object_name) is neither an array nor an object"
		return
	fi
}

# @description A stringified version of the querytree stack. This is used when
# generating objects to prevent conflicts
bash_object.util.generate_querytree_stack_string() {
	unset REPLY; REPLY=

	local oldIFS="$IFS"
	IFS='_'
	REPLY="${querytree_stack[*]}"
	IFS="$oldIFS"
}

#= eof bash-object
##############################################################################

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
