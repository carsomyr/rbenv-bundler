# rbenv-bundler: A Bundler Plugin for rbenv

This plugin transparently makes rbenv's shims aware of bundle installation
paths. It saves you from the hassle of having to type `bundle exec ${command}`
when working with per-project gemsets and will enable `rbenv which ${command}`
to report Bundler-installed gem executables if available.

### Installation

1. Get [rbenv](https://github.com/sstephenson/rbenv) working. Read the
   documentation thoroughly and be sure to set up your Bash environment
   correctly.

2. Install the plugin.

        $ git clone -- git://github.com/carsomyr/rbenv-bundler.git \
          ~/.rbenv/plugins/bundler

3. Make sure that there is a 1.8.7+ system or rbenv Ruby with the Bundler gem
   installed, available for the plugin's use.

        $ ruby -r bundler -e "puts RUBY_VERSION"
          1.9.3

### Usage

1. Just as you would run `rbenv rehash` upon installation of a new Ruby
   distribution or a gem with associated executable, you will also need to run
   it inside Bundler-controlled project directories with local, rbenv-installed
   Ruby versions set.

        $ # Suppose the project uses Ruby version 1.9.3-p362.
        $ rbenv local 1.9.3-p362

        $ # Install the version-specific Bundler gem.
        $ gem install bundler

        $ # Suppose you already have a Gemfile.
        $ bundle install --path vendor/bundle

        $ # Don't forget to rehash!
        $ rbenv rehash

        $ # If "rake" is a Bundler-installed gem executable, report its location
        $ # with "rbenv which". The result should look like
        $ # "${PWD}/vendor/local/ruby/1.9.1/bin/rake"
        $ rbenv which rake

        $ # Run "rake" without having to type "bundle exec rake".
        $ rake

2. If you wish to disable the plugin, type `rbenv bundler off`. Type `rbenv
   bundler on` to enable.

### Version History

**0.95** (January 10, 2013)

* Set up the `PATH` environment variable correctly when building rbenv Ruby
  profiles.
* Make rbenv Ruby profile discovery more robust.

**0.94** (July 21, 2012)

* Relicense the project to the Apache License, Version 2.0.
* Change the `rehash.rb` script so that it detects the `BUNDLE_GEMFILE`
  environment variable and looks for a Bundler-controlled project there.
* Fix issue [\#21](https://github.com/carsomyr/rbenv-bundler/issues/21), where
  the `RbenvBundler#ensure_capable_ruby` method would claim JRuby 1.9.x as
  capable when it's not (lack of `Kernel#fork`).
* Fix issue [\#22](https://github.com/carsomyr/rbenv-bundler/issues/22). This
  addresses the corner cases when either the `manifest.txt` file doesn't exist
  or the `ruby_profiles.yml` file is first created.

**0.93** (May 4, 2012)

* Fix issue [\#19](https://github.com/carsomyr/rbenv-bundler/issues/19), where a
  crash would result from rbenv Ruby profiles not being updated to reflect the
  removal of a Ruby. The `rehash.rb` script now checks the recency of the
  `~/.rbenv/versions` directory instead of rbenv Ruby directories to determine
  if Rubies have been added or removed.
* Fix issue [\#17](https://github.com/carsomyr/rbenv-bundler/issues/17), where
  the `rehash.rb` script would attempt to parse empty child process output when
  building rbenv Ruby profiles. Such situations are now detected and skipped.
* Mask the return value of the `rehash.rb` script. Change the rehash hook so
  that it doesn't cause the shell to exit prematurely from `-e` being in effect.

**0.92** (April 14, 2012)

* Ensure that a capable Ruby runs the `rehash.rb` script. Change the `rehash.rb`
  script so that if it detects an inappropriate Ruby version, it will attempt to
  locate and `Kernel#exec` an appropriate one.
* Build rbenv Ruby profiles to induce correct Bundler search behavior. With
  knowledge of each Ruby(Gems) implementation's version information and
  directory structure, the `rehash.rb` script can configure Bundler to exhibit
  the correct search behavior in all cases.
* Fix issue [\#14](https://github.com/carsomyr/rbenv-bundler/issues/14), where
  Git-based dependencies would not resolve correctly with the `rehash.rb`
  script. When using a Git repository as a dependency, Bundler loads its
  .gemspec file, which in turn may modify the Ruby state arbitrarily in ways
  that aren't readily reversible. To sidestep such behavior, the plugin now
  forks a child process for making sensitive Bundler calls.
* Fix issue [\#12](https://github.com/carsomyr/rbenv-bundler/issues/12), where
  setups without `--path` specified would sometimes pick gem executables with
  incorrect versions. As a result of reconciling different use cases, the plugin
  has been rearchitected to use a helper script, `rehash.rb`, to explore
  Bundler-controlled directories and create a gemspec manifest for each project.
  That way, a gem executable satisfying Gemfile version constraints can be
  picked every time.

**0.91** (January 18, 2012)

* The plugin now scans `~/.bundle/config` in addition to, and as a fallback for,
  the project-local Bundler configuration file. Credit
  [@mbrictson](https://github.com/mbrictson).
* Fix issue [\#6](https://github.com/carsomyr/rbenv-bundler/issues/6), where
  nonexistent directories would cause the rehash mechanism to return
  prematurely. Credit [@mbrictson](https://github.com/mbrictson).

**0.90** (September 28, 2011)

* Update plugin scripts to use the `RBENV_DIR` environment variable.
* Start release tagging.

### License

    Copyright 2012 Roy Liu

    Licensed under the Apache License, Version 2.0 (the "License"); you may not
    use this file except in compliance with the License. You may obtain a copy
    of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
    License for the specific language governing permissions and limitations
    under the License.
