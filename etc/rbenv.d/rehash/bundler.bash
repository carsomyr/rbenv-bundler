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

# The rbenv-bundler plugin delegate for "rbenv rehash".

source -- "$(dirname -- "$(dirname -- "${BASH_SOURCE[0]}")")/bundler/includes.sh"

if [[ -n "$plugin_disabled" ]]; then
    return 0
fi

manifest_dir="${plugin_root_dir}/share/rbenv/bundler"
rehash_rb_script="${plugin_root_dir}/etc/rbenv.d/bundler/rehash.rb"

mkdir -p -- "$manifest_dir"
touch -- "${manifest_dir}/manifest.txt"

"$rehash_rb_script" --refresh --verbose --out-dir "$manifest_dir" -- "$PWD" || true

manifest_entries=$(cat -- "${manifest_dir}/manifest.txt")

ifs_save=$IFS

IFS=$'\n'
manifest_entries=($manifest_entries)
IFS=$ifs_save

for (( i = 0; i < ${#manifest_entries[@]}; i += 2 )); do

    gemspec_entries=$(cat -- "${manifest_dir}/${manifest_entries[$(($i + 1))]}")

    ifs_save=$IFS

    IFS=$'\n'
    gemspec_entries=($gemspec_entries)
    IFS=$ifs_save

    for (( j = 0; j < ${#gemspec_entries[@]}; j += 2 )); do

        gem_executable="${gemspec_entries[$(($j + 1))]}/${gemspec_entries[$j]}"

        if [[ ! -f "$gem_executable" ]]; then
            continue
        fi

        cd -- "$SHIM_PATH" && make_shims "$gem_executable"; cd -- "$PWD"
    done
done
