#!/bin/bash

if [ -z "$BASH" ]; then 
	echo 'E: Used shell is not "bash": consider installing it or setting up development environment manually' >&2
	exit 1
fi
if [ -z "${#BASH_VERSINFO[@]}" ] || [ ${#BASH_VERSINFO[@]} -lt 2 ]; then
	echo 'E: Cannot get bash version information: consider updating' >&2
	exit 1
fi

set -euo pipefail


## Script behaviour options (uncomment to activate)
# RECREATE_VENVS=1   # Don't ask wether to recreate existing venv (1: recreate, 0: skip receration)
# NO_INSTALL_PKGS=1  # Don't install packages from requirements.txt (TODO, NOT IMPLEMENTED)

# shellcheck disable=SC2034
SCRIPT_NAME="${BASH_SOURCE##*/}"
SCRIPT_DIR="${BASH_SOURCE%/*}"
SCRIPTS_DIR="$SCRIPT_DIR"
ROOT_REPO_DIR="$SCRIPT_DIR/../"
LIBS_DIR="$SCRIPTS_DIR/libs"

# shellcheck disable=SC1091
source "$LIBS_DIR/lib_msg.sh"

check_req_cmds() {
    msg "## Checking for required commands"
    cmds=(pyenv direnv)
    not_found_cmds=()
    for cmd in "${cmds[@]}"; do
        command -v "$cmd" >/dev/null || not_found_cmds+=("$cmd")
    done
    if [[ ${#not_found_cmds[@]} -ne 0 ]]; then
        err "E: The following commands weren't found, consider installing them:"
        for not_found_cmd in "${not_found_cmds[@]}"; do
            echo "> $not_found_cmd" >&2
        done
        exit 1
    fi
}
check_req_cmds

if command -v realpath > /dev/null; then
    ROOT_REPO_DIR="$(realpath "$ROOT_REPO_DIR")"
fi

# Find envrc files with bash-native glob patterns, no find command & executable required
find_envrcs() {
    local dir="$1"
    
    if ! [[ -d "$dir" ]]; then
        err "\"$dir\" path is not a directory or does not exist."
        return 1
    fi

    # Loop through all files in dir
    for file in "$dir"/* "$dir"/.*; do
        # If the glob didn't match anything (e.g., empty dir), skip
        [[ -e "$file" ]] || continue
        if [[ -d "$file" ]]; then
            find_envrcs "$file"
        elif [[ -f "$file" ]] && [[ "${file##*/}" = ".envrc" ]]; then
            printf '%s\n' "$file"
        fi
    done
}

die_python_version() {
    local envrcs=$1
    local pyenv_version=$2
    die "envrc file \"$envrcs\" sets PYENV_VERSION=\"$pyenv_version\" variable to\n  an unallowed value for this project, should be of form \"<name_of_your_environment>@<python_version_to_use>\""
}

# Initialize pyenv in current shell process
init_pyenv() {
    export PYENV_ROOT="$HOME/.pyenv"
    [[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
}

# Initialize pyenv-virtualenv in current shell process
init_pyenv_virtualenv() {
    eval "$(pyenv virtualenv-init -)"
} 


setup() {
    # Initialize pyenv & pyenv-virtualenv to use pyenv commands
    init_pyenv
    init_pyenv_virtualenv

    # Find .envrc files
    msg "## Searching for \".envrc\" files"
    local envrcs=()
    local envrcs_raw
    if command -v find > /dev/null; then
        envrcs_raw="$(find "$ROOT_REPO_DIR" -type f -name .envrc)"
    else
        envrcs_raw="$(find_envrcs "$ROOT_REPO_DIR")"
    fi
    while read -r -d $'\n'; do
        envrcs+=("$REPLY")
    done <<< "$envrcs_raw"

    # Load .envrc files, parse PYENV_VERSION to get python versions and venv names
    msg "## Loading & Parsing \".envrc\" files"
    local pyenv_venvs_name=()
    local pyenv_venvs_ver=()
    local -i venv_i
    local pyenv_all_vers=()
    while read -r -d $'\n'; do
        pyenv_all_vers+=("$REPLY")
    done < <(pyenv install -l)
    pyenv_all_vers=("${pyenv_all_vers[@]:1}") # ignore first line, it's pyenv text header for human-readability
    for venv_i in "${!envrcs[@]}"; do
        # shellcheck disable=SC1090
        source "${envrcs[venv_i]}"
        pyenv_venvs_name+=("${PYENV_VERSION%%@*}")
        pyenv_venvs_ver+=("${PYENV_VERSION##*@}")
        # Check venv version validity
        if ! [[ " ${pyenv_all_vers[*]} " == *" ${pyenv_venvs_ver[venv_i]} "* ]]; then
            die_python_version "${envrcs[venv_i]}" "$PYENV_VERSION"
        fi
        if ! [[ "${pyenv_venvs_name[venv_i]}@${pyenv_venvs_ver[venv_i]}" == "$PYENV_VERSION" ]]; then
            die_python_version "${envrcs[venv_i]}" "$PYENV_VERSION"
        fi
    done
    unset PYENV_VERSION

    # Check for venv name uniqueness
    local pyenv_venvs_uniq=()
    local pyenv_venvs=()
    for venv_i in "${!pyenv_venvs_ver[@]}"; do
        pyenv_venvs+=("${pyenv_venvs_name[venv_i]}@${pyenv_venvs_ver[venv_i]}")
        if [[ " ${pyenv_venvs_uniq[*]} " != *" ${pyenv_venvs[venv_i]} "* ]]; then
            pyenv_venvs_uniq+=("${pyenv_venvs[venv_i]}")
        fi
        if [[ $((venv_i + 1)) -ne ${#pyenv_venvs_uniq[@]} ]]; then
            die "envrc file \"${envrcs[venv_i]}\" sets PYENV_VERSION=\"${pyenv_venvs[venv_i]}\"\n  variable to an unallowed value for this project, it's has a duplicate, consider changing value" >&2
        fi
    done

    # Get unique python versions
    local pyenv_ver_uniq=()
    for pyenv_venv_ver in "${pyenv_venvs_ver[@]}"; do
        if [[ " ${pyenv_ver_uniq[*]} " != *" $pyenv_venv_ver "* ]]; then
            pyenv_ver_uniq+=("$pyenv_venv_ver")
        fi
    done

    # Install in parallel all unique python versions
    msg "## Installing required python versions"
    trap 'pkill --signal SIGTERM --parent $$' EXIT
    local procs=()
    for pyenv_ver_uniq in "${pyenv_ver_uniq[@]}"; do
        pyenv install -s "$pyenv_ver_uniq" &
        procs+=($!)
    done
    wait "${procs[@]}"
    trap - EXIT

    # Create venvs
    msg "## Creating venvs"
    # shellcheck disable=SC2125
    local cur_pyenv_venv
    local cur_pyenv_venvs
    for cur_pyenv_venv in "$PYENV_ROOT/versions/"*; do
        # remove path, leave only current pyenv venv identifiers
        cur_pyenv_venvs+=" ${cur_pyenv_venv/$PYENV_ROOT\/versions\//}"
    done
    cur_pyenv_venvs+=" "
    local -i recreate=2;
    for venv_i in "${!pyenv_venvs[@]}"; do
        if [[ " $cur_pyenv_venvs " == *" ${pyenv_venvs[venv_i]} "* ]]; then
            if [[ -z "${RECREATE_VENVS+x}" ]]; then
                while true; do
                    msgn "Environment \"${pyenv_venvs[venv_i]}\" is already present, do you want to recreate it? [N/y]: "
                    read -rn 1
                    if [[ "$REPLY" == 'Y' || "$REPLY" == 'y' ]]; then
                        recreate=1
                        break
                    elif [[ "$REPLY" == 'N' || "$REPLY" == 'n' || "$REPLY" == '' ]]; then
                        if [[ "$REPLY" != '' ]]; then  # Don't print enter after user-inputted enter
                            echo ''
                        fi
                        recreate=0
                        break
                    else
                        echo "$SCRIPT_DIR: W: Input \"$REPLY\" not recognized, try again ( Ctrl + C to quit )"
                    fi
                done
                if [[ $recreate -eq 1 ]]; then
                    pyenv virtualenv-delete -f "${pyenv_venvs[venv_i]}" 1>/dev/null
                    pyenv virtualenv "${pyenv_venvs_ver[venv_i]}" "${pyenv_venvs[venv_i]}" 1>/dev/null
                fi
            else
                case "$RECREATE_VENVS" in
                    "0")
                        msg "## Skipping \"${pyenv_venvs[venv_i]}\" venv recreation"
                        ;;
                    "1")
                        msg "## Recreating \"${pyenv_venvs[venv_i]}\" venv"
                        pyenv virtualenv-delete -f "${pyenv_venvs[venv_i]}" 1>/dev/null
                        pyenv virtualenv "${pyenv_venvs_ver[venv_i]}" "${pyenv_venvs[venv_i]}" 1>/dev/null
                        ;;
                    *)
                        die "Unrecognized value for RECREATE_VENVS=\"$RECREATE_VENVS\", expected: undefined, \"1\" to recreate, \"0\" to skip recreation"
                        ;;
                esac
            fi
        else
            pyenv virtualenv "${pyenv_venvs_ver[venv_i]}" "${pyenv_venvs[venv_i]}" 1>/dev/null
        fi
    done

    # Allow direnvs
    local envrc
    for envrc in "${envrcs[@]}"; do
        direnv allow "${envrc%\/.envrc}"
    done

    # Install requirements.txt packages
    if [[ -z "${NO_INSTALL_PKGS+x}" ]]; then
        msg "## Installing required python packages from \"requirement.txt\" files"
        for venv_i in "${!envrcs[@]}"; do
            reqtxt_path="${envrcs[venv_i]%\/.envrc}/requirements.txt"
            if [[ -e "$reqtxt_path" ]]; then
                pyenv shell "${pyenv_venvs[venv_i]}"
                pip install -r "$reqtxt_path"
            else
                warn "\"$reqtxt_path\" file couldn't be found, consider\n  creating it with \"pyenv shell ${pyenv_venvs[venv_i]}; pip freeze > $reqtxt_path\" command, skipping"
            fi
        done
    else
        msg "## Skipping required python packages installation from \"requirements.txt\" files"
    fi
}

pushd "$ROOT_REPO_DIR" > /dev/null
setup
popd > /dev/null
