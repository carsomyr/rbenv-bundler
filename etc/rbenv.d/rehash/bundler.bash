# Copyright 2012 Roy Liu
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

# The rbenv-bundler plugin delegate for "rbenv rehash".

source -- "$(dirname -- "$(dirname -- "${BASH_SOURCE[0]}")")/bundler/includes.sh"

if [[ -n "$plugin_disabled" ]]; then
    return -- 0
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
