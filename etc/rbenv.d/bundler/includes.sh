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

# Gets the bundle installation path by inspecting the ".bundle/config" file
# and also the ~/.bundle/config file, if present.
function get_bundle_path {

    local -- bundle_config="${1}/.bundle/config"

    if [[ ! -f "$bundle_config" ]]; then
        return 1
    fi

    local -- bundle_path=$(cat -- "$bundle_config" "${HOME}/.bundle/config" 2> /dev/null \
        | sed -En -- "s/^BUNDLE_PATH: (.*)\$/\\1/gp" | head -n 1)

    if [[ -n "${bundle_path%%/*}" ]]; then
        bundle_path="${1}/${bundle_path}"
    fi

    if [[ ! -d "$bundle_path" ]]; then
        return 1
    fi

    echo "$bundle_path"
}

# Given a bundle path (i.e. one returned by get_bundle_path) and
# the name of a binary (e.g. "rails"), return the path to that binary,
# if it is present. Depending on how the bundle was created by bundler,
# the binary may be in one of two locations:
# 
# 1. ruby/*/bin/rails
# 2. bin/rails
#
function find_bundled_executable {

  local -- bundle_path=$1
  local -- binary_name=$2
  
  shopt -s -- nullglob \
      && bundled_executables=("$bundle_path"/ruby/*/bin/"$binary_name") \
      ; shopt -u -- nullglob

  if (( ${#bundled_executables[@]} > 0 )); then
      echo ${bundled_executables[0]}
  elif [[ -x "$bundle_path"/bin/"$binary_name" ]]; then
      echo "$bundle_path"/bin/"$binary_name"
  fi
}

# The local, per-project rbenv directory.
if [[ "$(rbenv-version-name)" != "system" ]]; then
    RBENV_DIR=$(dirname -- "$(rbenv-version-file)")
fi

# The plugins root directory.
plugin_root_dir=$(dirname -- "$(dirname -- "$(dirname -- "$(dirname -- "${BASH_SOURCE[0]}")")")")

# Whether the plugin is disabled.
if [[ -f "${plugin_root_dir}/share/rbenv/bundler/disabled" ]]; then
    plugin_disabled="1"
else
    plugin_disabled=""
fi
