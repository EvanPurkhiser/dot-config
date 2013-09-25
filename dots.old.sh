#!/bin/bash

set -e

# Use default Free desktop specification if this isn't defined
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# Get the path to the dot-configuration repository. The root is the location of
# this bash script. Must resolve the symlink
config_root="${BASH_SOURCE[0]}"

while [ -h "$config_root" ]
do
	config_root="$(readlink "$config_root")"
done;

config_root="$(dirname "$config_root")"
config_root="$(cd "$config_root" && pwd)"

# This is the file that the current groups configuration is stored in
groups_file="${XDG_CACHE_HOME:-$HOME/.cache}/.config-groups"

# This is the magic string for explicit append points
append_point="!!@@"

# error [message]
#
# Exit the script and print a error
#
# message: The message to print to stderr just before exiting
function error()
{
	echo -e "Error: $1" 1>&2
	exit 1
}

# list-groups
#
# Echos a list of all available configuration groups that can be enabled. All
# directories aside from the base directory are expected to contain groups.
function list-groups()
{
	# The base group is an implicit group
	echo "base"

	# All other groups are nested under directories
	find "$config_root" -maxdepth 2 -mindepth 2 \
		-not -path "$config_root/.git/*" \
		-not -path "$config_root/base/*" \
		-type d -printf '%P\n'
}

# set-groups
#
# Set the list of configuration groups that should be used to compile the
# configuration tree upon calling `install`. These valeus are stored in the
# $groups_file
#
# args: Each argument represents a group to be stored in the groups_file
function set-groups()
{
	# Only set the groups if they aren't already set
	[[ -f "$groups_file" ]] && error "Groups already set, use clear-groups first"
	[[ $# == 0 ]] && error "No groups specified"

	local groups="$(IFS=$'\n'; echo "$*")"

	# Find any config groups that aren't available
	local invalid_groups="$(echo "$groups" | grep \
		--invert-match  \
		--fixed-strings \
		--line-regexp "$(list-groups)" | tr "\n" " ")"

	# Error out if any groups aren't valid
	[[ -n "$invalid_groups" ]] && error "Invalid groups: ${invalid_groups}"

	# Save the groups configuration
	mkdir -p "{$groups_file%/*}"
	echo "$groups" > "$groups_file"
}

# clear-groups
#
# Removes the $groups_file
function clear-groups()
{
	rm -f "$groups_file"
}

# build-tree [build-path] [groups]
#
# This function will create the entirely pre-processed file tree containing all
# configuration files required for the specified configuration groups.
#
# groups:     A list of configuration groups that should be used to
# build_path: This should be a directory path where the configuration files
#             should be compiled into. If the directory doesn't exit it will
#             be created. If the string is null a temp directory will be created
function build-tree()
{
	[[ $# < 1 ]] && error "Invalid ammount of agruments"

	local groups=($1)
	local build_path="$2"

	# Create a temporary directory if the build_path is null
	if [ -z "$build_path" ]
	then
		build_path="$(mktemp -d)"
	fi

	# Handle each configuration groups tree
	for group in "${groups[@]}"
	do
		# Pass each file to be installed to compile-tree
		find "$config_root/$group" -type f -printf "%P\0" \
			| while read -d $'\0' file
		do
			compile-file "${group%/}" "$file" "$build_path"
		done
	done

	# Handle explicit named append point files
	compile-named-append-points "$build_path"

	# Clean up any unused explicit end points
	find "$build_path" -0 | xargs -0 sed 's/"


	echo "$build_path"
}

# compile-file
#
# Installs a file into the build directory. If the file already exists then the
# file will either be overriden, appended, or appended at a explicit point.
#
# config_group: The named configuration group we are currently installing for
# source_file:  The name of the file being insatlled for this group
# build_path:   The location of the build directory to install the file into
function compile-file()
{
	[[ $# != 3 ]] && error "Invalid ammount of arguments"

	local config_group="$1"
	local source_file="$2"
	local build_path="$3"

	local install_path="$build_path/$source_file"
	local source_path="$config_root/$config_group/$source_file"

	# Create the install directory if it doesn't exist
	mkdir -p "${install_path%/*}"

	# If the file is a 'override' (.override) file then copy it, replacing what
	# ever file may have been already
	if [[ "${source_file##*.}" == "override" ]]
	then
		cp --preserve=all "$source_path" "${install_path%.*}"
		return
	fi

	# If the file already exists then 'extend' the file
	if [[ -f "$install_path" ]]
	then
		# Test if the file has a default endpoint
		local insert_lines="$(test-for-extension "$install_path" "")"

		# Append to the end (default 'extend' mode) if no insert line(s)
		# are identified
		if [[ -z "$insert_lines" ]]
		then
			file-cat-appendable "$source_path" >> "$install_path"
		else
			replace-lines-with "$source_path" "$install_path" "$insert_lines"
		fi

	# If the file doesn't exist in the build directory copy it
	else
		cp --preserve=all "$source_path" "$install_path"
	fi
}

# test-for-extension
#
# Test a file to see if it contains a explicit append point identifier. The
# identifier used is a `!!@@`. To check for a specific (named) identifier that
# has a name after the identifier, pass the name as well. If no name is passed,
# we look for the default indicator.
#
# file_pah:       The file to test for an extension
# extension_name: The name of the extension to look foor
#
# echos:          The line(s) that the identifier is on
function test-for-extension()
{
	[[ $# != 1 && $# != 2 ]] && error "Invalid ammount of arguments"

	local file_path="$1"
	local extension_name="$2"

	grep -n "^[ \t]*${append_point}${extension_name}$" "$file_path" | cut -f 1 -d :

	return ${PIPESTATUS[0]}
}

# replace-lines-with
#
# Replace one or more lines line in a file with the contents of another file.
# This is primarly used to create the 'extended' files where the $append_point
# is used.
#
# file_to_insert: The file that will be inserted into the other file
# target_file:    The file that will have a specific line replaced with a new
#                 files contents
# target_lines:   The line(s) to replace with new contents
function replace-lines-with()
{
	[[ $# != 3 ]] && error "Invalid ammount of arguments"

	local file_to_insert="$1"
	local target_file="$2"
	local target_lines=($3)

	# Don't do anything if no lines were passed
	[[ ${#target_lines[@]} == 0 ]] && return

	local start_line=1
	local temp_file="$(mktemp)"

	for (( i=0; i < ${#target_lines[@]}; ++i ))
	do
		local line_prev=$((${target_lines[i]} - 1))
		local line_next=$((${target_lines[i]} + 1))
		local next_line=$((${target_lines[i+1]} - 1))

		# If there is no next line then go to the end of the file
		[[ $next_line == -1 ]] && next_line=$(cat "$target_file" | wc -l)

		# Slice up the contents, combining it in the temp file
		(
			(( $start_line > $line_prev )) ||\
				sed -n "$start_line,${line_prev}p" "$target_file"

			file-cat-appendable "$file_to_insert"

			(( $line_next > $next_line ))  ||\
				sed -n "$line_next,${next_line}p"  "$target_file"
		) >> "$temp_file"

		start_line=$next_line
	done

	mv "$temp_file" "$target_file"
}

# file-cat-appendable
#
# Get the contents of a file to be appended (extended). This will remove the
# shebang from the first line of the file
#
# source_file: The file to prepare to be appended
function file-cat-appendable()
{
	[[ $# != 1 ]] && error "Invalid ammount of arguments"

	local source_file="$1"

	if head "$source_file" -n1 | grep -q "^#!.*$"
	then
		tail "$source_file" -n +2
	else
		cat "$source_file"
	fi
}

build-tree "$(cat "$groups_file")"
