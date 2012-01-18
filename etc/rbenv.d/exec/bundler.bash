#!/usr/bin/env bash
#
# Copyright (C) 2011 Roy Liu
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#   * Redistributions of source code must retain the above copyright notice,
#     this list of conditions and the following disclaimer.
#   * Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#   * Neither the name of the author nor the names of any contributors may be
#     used to endorse or promote products derived from this software without
#     specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

# The rbenv-bundler plugin delegate for "rbenv exec".

source -- "$(dirname -- "$(dirname -- "${BASH_SOURCE[0]}")")/bundler/includes.sh"

if [[ -n "$plugin_disabled" ]] || { ! bundle_path=$(get_bundle_path "$RBENV_DIR"); } then
    return
fi

if { ! bundled_executable=$(find_bundled_executable "$bundle_path" "$RBENV_COMMAND"); } then
    return
fi

# Instead of running "$RBENV_COMMAND", run "bundle exec ${RBENV_COMMAND}" instead.

RBENV_BIN_PATH=$(dirname -- "$bundled_executable")
RBENV_COMMAND="bundle"
RBENV_COMMAND_PATH=$(which env)

# The first argument is ignored by later processing.
set -- "-" "--" "RBENV_DIR=." "bundle" "exec" "$@"
