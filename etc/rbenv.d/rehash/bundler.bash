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

# The rbenv-bundler plugin delegate for "rbenv rehash".

source -- "$(dirname -- "$(dirname -- "${BASH_SOURCE[0]}")")/bundler/includes.sh"

if [[ -n "$plugin_disabled" ]]; then
    return -- 0
fi

manifest_dir="${plugin_root_dir}/share/rbenv/bundler"
rehash_script="${plugin_root_dir}/etc/rbenv.d/bundler/rehash.rb"

if { needs_rehash_script "$manifest_dir"; } then
    "$rehash_script" --refresh --verbose --out-dir "$manifest_dir" -- "$PWD" || true
fi

make_gemfile_shims "$manifest_dir"
