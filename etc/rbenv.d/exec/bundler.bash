# Copyright 2012 Roy Liu
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

# The plugin delegate for `rbenv exec`.

source -- "$(dirname -- "$(dirname -- "${BASH_SOURCE[0]}")")/bundler/includes.sh"

if [[ -z "$plugin_enabled" ]]; then
    return -- 0
fi

manifest_dir="${plugin_root_dir}/share/rbenv/bundler"

if { ! bundled_executable=$(find_bundled_executable "$manifest_dir"); } then
    # Use the internally provided script on `bundle install` or `bundle update` to automagically rehash afterwards.
    if [[ "$RBENV_COMMAND" == "bundle" ]] && { [[ "$2" == "install" ]] || [[ "$2" == "update" ]]; } then
        RBENV_BIN_PATH="${plugin_root_dir}/etc/rbenv.d/bundler"
        RBENV_COMMAND_PATH="${RBENV_BIN_PATH}/bundler"
    fi

    return -- 0
fi

# Run `bundle exec ${RBENV_COMMAND}` instead of `$RBENV_COMMAND`.

RBENV_COMMAND="bundle"
RBENV_COMMAND_PATH=$(rbenv-which "$RBENV_COMMAND")
RBENV_BIN_PATH=${RBENV_COMMAND_PATH%/*}

# The first argument is ignored by later processing.
set -- "-" "exec" "$@"
