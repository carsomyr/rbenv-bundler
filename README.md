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

        $ git clone -- git@github.com:carsomyr/rbenv-bundler \
          ~/.rbenv/plugins/bundler

3. Make sure that there is a reasonably up-to-date system Ruby (1.8 or 1.9) with
   the Bundler gem installed, available for the plugin's use.

        $ ruby -r bundler -e "puts RUBY_VERSION"
          1.9.3

### Usage

1. Just as you would run `rbenv rehash` upon installation of a new Ruby
   distribution or a gem with associated executable, you will also need to run
   it inside Bundler-controlled project directories with local, rbenv-installed
   Ruby versions set.

        $ # Suppose the project uses Ruby version 1.9.3-p194.
        $ rbenv local 1.9.3-p194

        $ # Install the version-specific Bundler gem.
        $ gem install bundler

        $ # Suppose you already have a Gemfile.
        $ bundle install --path vendor/bundle

        $ # Don't forget to rehash!
        $ rbenv rehash

        $ # If "rake" is a Bundler-installed gem executable, report its location
        $ # with "rbenv which". The result should look like
        $ # "${PWD}/vendor/local/ruby/1.8/bin/rake"
        $ rbenv which rake

        $ # Run "rake" without having to type "bundle exec rake".
        $ rake

2. If you wish to disable the plugin, type `rbenv bundler off`. Type `rbenv
   bundler on` to enable.

### Version History

**0.92** (April 14, 2012)

* Fix issue [#14](https://github.com/carsomyr/rbenv-bundler/issues/14), where
  Git-based dependencies would not resolve correctly with the `rehash.rb`
  script. When using a Git repository as a dependency, Bundler loads its
  .gemspec file, which in turn may modify the Ruby state arbitrarily in ways
  that aren't readily reversible. To sidestep such behavior, the plugin now
  forks a child process for making sensitive Bundler calls.
* Fix issue [#12](https://github.com/carsomyr/rbenv-bundler/issues/12), where
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
* Fix issue [#6](https://github.com/carsomyr/rbenv-bundler/issues/6), where
  nonexistent directories would cause the rehash mechanism to return
  prematurely. Credit [@mbrictson](https://github.com/mbrictson).

**0.90** (September 28, 2011)

* Update plugin scripts to use the RBENV_DIR environment variable.
* Start release tagging.
