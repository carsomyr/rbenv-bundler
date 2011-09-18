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

# Contains includes common to rbenv-bundler plugin scripts.

# Gets the bundle installation path by inspecting the ".bundle/config" file.
function get_bundle_path {

    local -- bundle_config="${1}/.bundle/config"

    if [[ ! -f "$bundle_config" ]]; then
        return 1
    fi

    local -- bundle_path=$(cat -- "$bundle_config" | sed -En -- "s/^BUNDLE_PATH: (.*)\$/\\1/gp")

    if [[ -n "${bundle_path%%/*}" ]]; then
        bundle_path="${1}/${bundle_path}"
    fi

    if [[ ! -d "$bundle_path" ]]; then
        return 1
    fi

    echo "$bundle_path"
}

# The local, per-project rbenv directory.
if [[ "$(rbenv-version-name)" != "system" ]]; then
    LOCAL_DIR=$(dirname -- "$(rbenv-version-file)")
else
    LOCAL_DIR=$PWD
fi

# The plugins root directory.
PLUGIN_ROOT_DIR=$(dirname -- "$(dirname -- "$(dirname -- "$(dirname -- "${BASH_SOURCE[0]}")")")")

# Whether the plugin is disabled.
if [[ -f "${PLUGIN_ROOT_DIR}/share/rbenv/bundler/disabled" ]]; then
    PLUGIN_DISABLED="1"
else
    PLUGIN_DISABLED=""
fi
